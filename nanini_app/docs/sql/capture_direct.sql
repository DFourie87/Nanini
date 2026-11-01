-- Nanini Capture: everything from the phones goes straight in -- no approving
-- in the hub any more (run once in the Supabase SQL editor; safe to re-run).
-- Needs tuckshop_auto_approve.sql (and the earlier capture SQL) run first.
--
--   * Timesheet photos: checked on the phone by the person who took them
--     ("Are the hours right?"), then each worker's hours at the sheet's farm
--     on each day are replaced by the sheet's -- as approving did in the hub.
--     Paid days, and days already clocked at another farm, are left alone.
--     A work group's sheet: its hours go in as the group's (its tariff).
--   * Fridge sheet photos: checked on the phone ("Are the counts right?"),
--     then each count goes on the worker's tuck shop account as a sale
--     (stock off the oldest batches first). The same page never twice.
--   * Work groups (Hours > WORK GROUPS on the phone): who is in which group.
--   * Hours and tuck shop sales already went straight in (unchanged).
-- If one can't go in (e.g. a worker was removed), none of it goes in and it
-- stays as it was ("pending"); the last result below counts them.

-- One tuck shop sale: the item's selling price, the stock off the oldest
-- batches first (FIFO; past the stock, at the last cost) -- as the hub and
-- _capture_apply_tuckshop work it out.
create or replace function _tuck_sell(p_employee uuid, p_item uuid, p_qty numeric, p_date date, p_note text) returns void
language plpgsql security definer set search_path = public
as $$
declare
  v_item jsonb;
  v_last_cost numeric;
  v_price numeric;
  v_left numeric;
  v_take numeric;
  v_cogs numeric := 0;
  v_batch record;
begin
  select to_jsonb(i) into v_item from tuckshop_items i where i.id = p_item for update;
  if v_item is null then
    raise exception 'an item is no longer in the tuck shop stock list';
  end if;
  v_last_cost := coalesce((v_item ->> 'last_cost_price')::numeric, 0);
  v_price := coalesce((v_item ->> 'fixed_sell_price')::numeric, round(coalesce(
               (select b.cost_price from tuckshop_batches b where b.item_id = p_item order by b.batch_date desc nulls last limit 1),
               v_last_cost) * (1 + coalesce((v_item ->> 'profit_pct')::numeric, 35) / 100)));
  v_left := p_qty;
  for v_batch in select b.id, b.qty, b.cost_price from tuckshop_batches b where b.item_id = p_item order by b.batch_date, b.id for update loop
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
  insert into tuckshop_purchases (employee_id, item_id, qty, revenue, cogs, sale_date, note, farm_id)
  values (p_employee, p_item, p_qty, v_price * p_qty, v_cogs, p_date, p_note, (v_item ->> 'farm_id')::uuid);
end;
$$;
revoke all on function _tuck_sell(uuid, uuid, numeric, date, text) from public, anon, authenticated;

-- A timesheet page checked on the phone (payload 'checked': farm_id,
-- group_name, lines [{employee_id, employee_name, date, hours}]).
create or replace function _capture_apply_timesheet(p_id uuid) returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  v_entry capture_entries%rowtype;
  v_c jsonb;
  v_farm uuid;
  v_group text;
  v_line jsonb;
  v_emp uuid;
  v_date date;
  v_hours numeric;
  v_rate numeric;
  v_threshold numeric := 9;
  v_ot numeric := 1.5;
begin
  select * into v_entry from capture_entries where id = p_id and module = 'timesheet' and status = 'pending' for update;
  if not found or v_entry.payload -> 'checked' is null then
    return false;
  end if;
  v_c := v_entry.payload -> 'checked';
  v_farm := nullif(v_c ->> 'farm_id', '')::uuid;
  v_group := nullif(v_c ->> 'group_name', '');
  select coalesce(daily_threshold, 9), coalesce(ot_multiplier, 1.5) into v_threshold, v_ot from hours_settings where id = 1;
  v_threshold := coalesce(v_threshold, 9);
  v_ot := coalesce(v_ot, 1.5);
  begin
    for v_line in select * from jsonb_array_elements(coalesce(v_c -> 'lines', '[]'::jsonb)) loop
      v_emp := (v_line ->> 'employee_id')::uuid;
      v_date := (v_line ->> 'date')::date;
      v_hours := (v_line ->> 'hours')::numeric;
      select coalesce(e.rate_per_hour, 0) into v_rate from employees e where e.id = v_emp;
      if not found then
        raise exception 'worker % is no longer in the employee list', v_line ->> 'employee_name';
      end if;
      -- Paid days are never changed.
      continue when exists (select 1 from payslips p where p.employee_id = v_emp and p.period_end >= v_date);
      -- One farm a day: already clocked at another farm, left out.
      continue when coalesce((select sum(h.hours) from hours_entries h
                               where h.employee_id = v_emp and h.entry_date = v_date
                                 and h.farm_id is not null and h.farm_id is distinct from v_farm), 0) > 0.001;
      -- This farm's hours for that day are replaced by the sheet's.
      delete from hours_entries where employee_id = v_emp and entry_date = v_date and farm_id is not distinct from v_farm;
      if v_hours > 0 then
        insert into hours_entries (employee_id, entry_date, hours, rate, daily_threshold, ot_multiplier,
                                   normal_hours, ot_hours, gross, via, group_name, farm_id)
        values (v_emp, v_date, v_hours, v_rate, v_threshold, v_ot,
                least(v_hours, v_threshold), greatest(v_hours - v_threshold, 0), v_hours * v_rate,
                case when v_group is null then 'individual' else 'group' end, v_group, v_farm);
      end if;
    end loop;
  exception when others then
    -- Nothing of this page is kept; it stays pending.
    return false;
  end;
  update capture_entries set status = 'approved', reviewed_at = now(), reviewed_by = 'Automatic (timesheet checked on the phone)' where id = p_id;
  return true;
end;
$$;
revoke all on function _capture_apply_timesheet(uuid) from public, anon, authenticated;

-- A fridge sheet page checked on the phone (payload 'checked': date, note,
-- lines [{employee_id, employee_name, item_id, item_name, qty}]).
create or replace function _capture_apply_fridge(p_id uuid) returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  v_entry capture_entries%rowtype;
  v_c jsonb;
  v_line jsonb;
  v_note text;
  v_date date;
begin
  select * into v_entry from capture_entries where id = p_id and module = 'fridge_sheet' and status = 'pending' for update;
  if not found or v_entry.payload -> 'checked' is null then
    return false;
  end if;
  v_c := v_entry.payload -> 'checked';
  v_note := v_c ->> 'note';
  v_date := (v_c ->> 'date')::date;
  begin
    -- The same page never twice.
    if v_note is null or exists (select 1 from tuckshop_purchases where note = v_note) then
      raise exception 'this page is already on the tuck shop accounts';
    end if;
    for v_line in select * from jsonb_array_elements(coalesce(v_c -> 'lines', '[]'::jsonb)) loop
      if not exists (select 1 from employees e where e.id = (v_line ->> 'employee_id')::uuid) then
        raise exception '% is no longer in the employee list', v_line ->> 'employee_name';
      end if;
      continue when coalesce((v_line ->> 'qty')::numeric, 0) <= 0;
      perform _tuck_sell((v_line ->> 'employee_id')::uuid, (v_line ->> 'item_id')::uuid, (v_line ->> 'qty')::numeric, v_date, v_note);
    end loop;
  exception when others then
    return false;
  end;
  update capture_entries set status = 'approved', reviewed_at = now(), reviewed_by = 'Automatic (fridge sheet checked on the phone)' where id = p_id;
  return true;
end;
$$;
revoke all on function _capture_apply_fridge(uuid) from public, anon, authenticated;

-- Work groups from the phone (payload: farm_id, farm_name, group_id or
-- group_name, members [{employee_id}], removed [{employee_id}]) -- as the hub
-- applied them. No groups on Doornbult and Haaskraal: nothing to do there.
create or replace function _capture_apply_work_groups(p_id uuid) returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  v_entry capture_entries%rowtype;
  v_p jsonb;
  v_group uuid;
  v_farm uuid;
  v_name text;
begin
  select * into v_entry from capture_entries where id = p_id and module = 'work_groups' and status = 'pending' for update;
  if not found then
    return false;
  end if;
  v_p := v_entry.payload;
  v_farm := nullif(v_p ->> 'farm_id', '')::uuid;
  v_name := btrim(coalesce(v_p ->> 'group_name', ''));
  begin
    if lower(coalesce(v_p ->> 'farm_name', '')) !~ '(doornbult|haaskraal)' then
      v_group := nullif(v_p ->> 'group_id', '')::uuid;
      -- A group deleted since the phone sent this isn't brought back.
      if v_group is null or exists (select 1 from employee_groups g where g.id = v_group) then
        if v_group is null then
          select g.id into v_group from employee_groups g
           where g.farm_id is not distinct from v_farm and lower(btrim(g.name)) = lower(v_name) limit 1;
          if v_group is null then
            insert into employee_groups (name, farm_id) values (v_name, v_farm) returning id into v_group;
          end if;
        end if;
        update employees set current_group_id = v_group
         where id::text in (select m ->> 'employee_id' from jsonb_array_elements(coalesce(v_p -> 'members', '[]'::jsonb)) m);
        update employees set current_group_id = null
         where current_group_id = v_group
           and id::text in (select m ->> 'employee_id' from jsonb_array_elements(coalesce(v_p -> 'removed', '[]'::jsonb)) m);
      end if;
    end if;
  exception when others then
    return false;
  end;
  update capture_entries set status = 'approved', reviewed_at = now(), reviewed_by = 'Automatic (work groups from the phone)' where id = p_id;
  return true;
end;
$$;
revoke all on function _capture_apply_work_groups(uuid) from public, anon, authenticated;

-- What the phones send: in, and straight on (as tuckshop_auto_approve.sql,
-- plus timesheets, fridge sheets and work groups).
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
      case v_e ->> 'module'
        when 'hours' then perform _capture_apply_hours(v_id);
        when 'pay_check' then perform _capture_apply_paycheck_hours(v_id);
        when 'tuckshop' then perform _capture_apply_tuckshop(v_id);
        when 'timesheet' then perform _capture_apply_timesheet(v_id);
        when 'fridge_sheet' then perform _capture_apply_fridge(v_id);
        when 'work_groups' then perform _capture_apply_work_groups(v_id);
        else null;
      end case;
    end if;
  end loop;
  return v_count;
end;
$$;
grant execute on function capture_submit(uuid, jsonb) to anon, authenticated;

-- Work groups already waiting go in now (oldest first).
select _capture_apply_work_groups(c.id)
from (select id from capture_entries where module = 'work_groups' and status = 'pending' order by captured_at) c;

-- What is still waiting from the phones (sent before this, or couldn't go in).
select coalesce(string_agg(module || ': ' || n, ', ' order by module), 'nothing') as still_pending
from (select module, count(*) as n from capture_entries where status = 'pending' group by module) x;
