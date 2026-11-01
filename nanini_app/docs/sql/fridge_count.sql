-- Tuck shop fridge counts (run once in the Supabase SQL editor; safe to
-- re-run). Needs capture_direct.sql run first.
--
-- On pay day, after the fridge sheet's pages are photographed, what's in the
-- fridge is counted on the phone (Tuck shop > FRIDGE COUNT) or typed in the
-- hub (Tuck Shop > Fridge check > Add count). The hub's Fridge check puts
-- each count against the one before it:
--   opening (the last count) + bought - taken (sheets and sales)
--   - written off = should be there; less the count = short.
-- One count per item per day: a recount the same day replaces it.
-- Stock bought is logged (tuckshop_stock_purchases) from when this is run.

create table if not exists tuckshop_counts (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references tuckshop_items (id),
  count_date date not null,
  qty numeric not null check (qty >= 0),
  counted_by text,
  created_at timestamptz not null default now()
);
create index if not exists tuckshop_counts_item_idx on tuckshop_counts (item_id, count_date);

-- Same rule as every other table: logged-in Nanini users only.
alter table tuckshop_counts enable row level security;
drop policy if exists "Nanini users" on tuckshop_counts;
create policy "Nanini users" on tuckshop_counts for all to authenticated
  using (public.is_app_user()) with check (public.is_app_user());

-- Stock bought (Tuck Shop > Stock: restock, or a new item's opening stock --
-- a batch with "paid by"), kept for the Fridge check: the batches
-- themselves are used up. Sales returned to stock (no "paid by") are not
-- purchases. Left alone if the database already logs them.
create table if not exists tuckshop_stock_purchases (
  id uuid primary key default gen_random_uuid(),
  item_id uuid references tuckshop_items (id),
  qty numeric not null,
  cost_price numeric not null default 0,
  total numeric not null default 0,
  paid_by text,
  purchase_date date not null default current_date,
  created_at timestamptz not null default now()
);
alter table tuckshop_stock_purchases enable row level security;
drop policy if exists "Nanini users" on tuckshop_stock_purchases;
create policy "Nanini users" on tuckshop_stock_purchases for all to authenticated
  using (public.is_app_user()) with check (public.is_app_user());

create or replace function _tuck_log_stock_purchase() returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.paid_by is not null and coalesce(new.qty, 0) > 0 then
    begin
      insert into tuckshop_stock_purchases (item_id, qty, cost_price, total, paid_by, purchase_date)
      values (new.item_id, new.qty, coalesce(new.cost_price, 0), new.qty * coalesce(new.cost_price, 0), new.paid_by, coalesce(new.batch_date, current_date));
    exception when others then
      null; -- never stops a restock
    end;
  end if;
  return new;
end;
$$;

do $$
begin
  if not exists (
    select 1 from pg_trigger t join pg_proc f on f.oid = t.tgfoid
     where t.tgrelid = 'tuckshop_batches'::regclass and not t.tgisinternal
       and f.proname <> '_tuck_log_stock_purchase' and f.prosrc ilike '%tuckshop_stock_purchases%') then
    drop trigger if exists tuck_log_stock_purchase on tuckshop_batches;
    create trigger tuck_log_stock_purchase after insert on tuckshop_batches
      for each row execute function _tuck_log_stock_purchase();
  end if;
end $$;

-- Live updates in the hub.
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'tuckshop_counts') then
    alter publication supabase_realtime add table tuckshop_counts;
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'tuckshop_stock_purchases') then
    alter publication supabase_realtime add table tuckshop_stock_purchases;
  end if;
end $$;

-- A fridge count from the phone (module 'fridge_sheet', payload kind
-- 'count': date, farm_id, farm_name, counts [{item_id, item_name, qty}]):
-- straight in, like the sheets.
create or replace function _capture_apply_fridge_count(p_id uuid) returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  v_entry capture_entries%rowtype;
  v_line jsonb;
begin
  select * into v_entry from capture_entries where id = p_id and module = 'fridge_sheet' and status = 'pending' for update;
  if not found or v_entry.payload ->> 'kind' is distinct from 'count' then
    return false;
  end if;
  begin
    for v_line in select * from jsonb_array_elements(coalesce(v_entry.payload -> 'counts', '[]'::jsonb)) loop
      if not exists (select 1 from tuckshop_items i where i.id = (v_line ->> 'item_id')::uuid) then
        raise exception '% is no longer in the tuck shop stock list', v_line ->> 'item_name';
      end if;
      insert into tuckshop_counts (item_id, count_date, qty, counted_by)
      values ((v_line ->> 'item_id')::uuid, (v_entry.payload ->> 'date')::date, (v_line ->> 'qty')::numeric,
              coalesce(v_entry.device_name, 'Phone'));
    end loop;
  exception when others then
    return false;
  end;
  update capture_entries set status = 'approved', reviewed_at = now(), reviewed_by = 'Automatic (fridge count from the phone)' where id = p_id;
  return true;
end;
$$;
revoke all on function _capture_apply_fridge_count(uuid) from public, anon, authenticated;

-- A fridge sheet page checked on the phone (payload 'checked': date, note,
-- lines [{employee_id, employee_name, item_id, item_name, qty}]) -- as in
-- capture_direct.sql -- or a fridge count (payload kind 'count').
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
  if not found then
    return false;
  end if;
  if v_entry.payload ->> 'kind' = 'count' then
    return _capture_apply_fridge_count(p_id);
  end if;
  if v_entry.payload -> 'checked' is null then
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

-- Counts sent before this was run go in now.
do $$
declare
  v_id uuid;
begin
  for v_id in select id from capture_entries where module = 'fridge_sheet' and status = 'pending' and payload ->> 'kind' = 'count' order by captured_at loop
    perform _capture_apply_fridge_count(v_id);
  end loop;
end $$;

select 'tuckshop_counts ready: ' || count(*) || ' counts' as result from tuckshop_counts;
