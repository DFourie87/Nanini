-- Tuck shop sales captured on the phones don't wait for approval: when a
-- phone sends a sale, it goes straight into the worker's purchases (as
-- approving it in the hub did -- the item's selling price, stock taken off
-- the oldest batches first) and the entry is marked approved ("Automatic").
-- If one can't be added (e.g. the worker or the item was removed), none of
-- it goes in and it stays in the inbox for the office.
-- Needs payslip_hours_auto.sql (or later) run first. Safe to re-run.

create or replace function _capture_apply_tuckshop(p_id uuid) returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  v_entry capture_entries%rowtype;
  v_p jsonb;
  v_date date;
  v_employee uuid;
  v_line jsonb;
  v_item jsonb;
  v_item_id uuid;
  v_qty numeric;
  v_last_cost numeric;
  v_price numeric;
  v_left numeric;
  v_take numeric;
  v_cogs numeric;
  v_batch record;
begin
  select * into v_entry from capture_entries where id = p_id and module = 'tuckshop' and status = 'pending' for update;
  if not found then
    return false;
  end if;
  v_p := v_entry.payload;
  v_date := (v_p ->> 'date')::date;
  v_employee := (v_p ->> 'employee_id')::uuid;
  begin
    if not exists (select 1 from employees e where e.id = v_employee) then
      raise exception '% is no longer in the employee list', v_p ->> 'employee_name';
    end if;
    if v_p ->> 'manual_total' is not null then
      -- A money total (a phone not yet updated to sell per item).
      insert into tuckshop_purchases (employee_id, item_id, qty, revenue, cogs, sale_date, note, farm_id)
      values (v_employee, null, null, (v_p ->> 'manual_total')::numeric, 0, v_date,
              'Manual shop total for ' || (v_p ->> 'date') || ' to ' || (v_p ->> 'date'), (v_p ->> 'farm_id')::uuid);
    else
      for v_line in select * from jsonb_array_elements(coalesce(v_p -> 'lines', '[]'::jsonb)) loop
        v_item_id := (v_line ->> 'item_id')::uuid;
        select to_jsonb(i) into v_item from tuckshop_items i where i.id = v_item_id for update;
        if v_item is null then
          raise exception '% is no longer in the tuck shop stock list', v_line ->> 'item_name';
        end if;
        v_qty := (v_line ->> 'qty')::numeric;
        v_last_cost := coalesce((v_item ->> 'last_cost_price')::numeric, 0);
        -- The selling price before this sale's stock comes off: the fixed
        -- price, else the newest batch's cost (or the last cost) plus the
        -- margin, to the rand -- as the hub and the phones work it out.
        v_price := coalesce((v_item ->> 'fixed_sell_price')::numeric, round(coalesce(
                     (select b.cost_price from tuckshop_batches b where b.item_id = v_item_id
                      order by b.batch_date desc nulls last limit 1),
                     v_last_cost) * (1 + coalesce((v_item ->> 'profit_pct')::numeric, 35) / 100)));
        if v_qty >= 0 then
          -- Oldest batches first (FIFO); past the stock, at the last cost.
          v_left := v_qty;
          v_cogs := 0;
          for v_batch in select b.id, b.qty, b.cost_price from tuckshop_batches b where b.item_id = v_item_id
                         order by b.batch_date, b.id for update loop
            exit when v_left <= 0;
            v_take := least(v_left, v_batch.qty);
            v_cogs := v_cogs + v_take * v_batch.cost_price;
            v_left := v_left - v_take;
            if v_batch.qty - v_take <= 0 then
              delete from tuckshop_batches where id = v_batch.id;
            else
              update tuckshop_batches set qty = v_batch.qty - v_take where id = v_batch.id;
            end if;
          end loop;
          if v_left > 0 then
            v_cogs := v_cogs + v_left * v_last_cost;
          end if;
        else
          -- A credit for an item wrongly sold: the stock goes back at the last cost.
          insert into tuckshop_batches (item_id, cost_price, qty, batch_date) values (v_item_id, v_last_cost, -v_qty, v_date);
          v_cogs := v_last_cost * v_qty;
        end if;
        insert into tuckshop_purchases (employee_id, item_id, qty, revenue, cogs, sale_date, farm_id)
        values (v_employee, v_item_id, v_qty, v_price * v_qty, v_cogs, v_date, (v_item ->> 'farm_id')::uuid);
      end loop;
    end if;
  exception when others then
    -- Nothing of this entry is kept; it stays pending for the office.
    return false;
  end;
  update capture_entries set status = 'approved', reviewed_at = now(), reviewed_by = 'Automatic (tuck shop from phone)' where id = p_id;
  return true;
end;
$$;
revoke all on function _capture_apply_tuckshop(uuid) from public, anon, authenticated;

create or replace function capture_submit(p_device_id uuid, p_entries jsonb)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  v_name text;
  v_count integer := 0;
  v_e jsonb;
  v_id uuid;
begin
  if not _capture_device_ok(p_device_id) then
    raise exception 'This phone is not approved';
  end if;
  select name into v_name from capture_devices where id = p_device_id;
  for v_e in select * from jsonb_array_elements(p_entries) loop
    v_id := null;
    insert into capture_entries (id, device_id, device_name, module, payload, summary, captured_at, status)
    values ((v_e ->> 'id')::uuid, p_device_id, v_name, v_e ->> 'module', v_e -> 'payload', left(v_e ->> 'summary', 300),
            (v_e ->> 'captured_at')::timestamptz, 'pending')
    on conflict (id) do nothing
    returning id into v_id;
    if v_id is not null then
      v_count := v_count + 1;
      -- Hours (Hours task, and hours on Payslips) and tuck shop sales need no approval.
      if v_e ->> 'module' = 'hours' then
        perform _capture_apply_hours(v_id);
      elsif v_e ->> 'module' = 'pay_check' then
        perform _capture_apply_paycheck_hours(v_id);
      elsif v_e ->> 'module' = 'tuckshop' then
        perform _capture_apply_tuckshop(v_id);
      end if;
    end if;
  end loop;
  return v_count;
end;
$$;
grant execute on function capture_submit(uuid, jsonb) to anon, authenticated;

-- Tuck shop sales already waiting in the inbox go in now (oldest first);
-- what's left (if any) is for the office to look at.
select _capture_apply_tuckshop(c.id)
from (select id from capture_entries where module = 'tuckshop' and status = 'pending' order by captured_at) c;

select (select count(*) from capture_entries where module = 'tuckshop' and reviewed_by = 'Automatic (tuck shop from phone)') as tuck_shop_sales_added,
       (select count(*) from capture_entries where module = 'tuckshop' and status = 'pending') as still_waiting;
