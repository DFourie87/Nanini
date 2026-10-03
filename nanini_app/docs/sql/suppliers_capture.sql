-- Nanini Capture > SUPPLIERS: a supplier's invoice, credit note or
-- statement photographed on a phone, with its total, VAT, number and date.
-- It waits in the hub's Suppliers inbox until an admin checks it and
-- allocates its lines to GL accounts; then it's saved to the supplier with
-- the photo as a PDF. Tick "Suppliers" for a phone in Capture phones.
-- Needs suppliers.sql, suppliers_purchases.sql and lockdown_1_accounts.sql.
-- Safe to re-run.

alter table capture_entries drop constraint if exists capture_entries_module_check;
alter table capture_entries add constraint capture_entries_module_check
  check (module in ('diesel_usage', 'diesel_purchase', 'hours', 'kg', 'tuckshop', 'delivery', 'employee', 'pay_check',
                    'work_groups', 'supplier_doc'));

-- The photos, kept apart from capture_entries so the inbox stays light.
-- Deleted once approved (the PDF is then in the supplier's documents).
create table if not exists capture_photos (
  entry_id uuid primary key,
  device_id uuid not null references capture_devices(id) on delete cascade,
  data text not null, -- JPEG, base64
  created_at timestamptz not null default now()
);
alter table capture_photos enable row level security;
drop policy if exists "Nanini users" on capture_photos;
create policy "Nanini users" on capture_photos for all to authenticated
  using (public.is_app_user()) with check (public.is_app_user());

-- A phone sends a photo before the entry it belongs to.
create or replace function capture_submit_photo(p_device_id uuid, p_entry_id uuid, p_data text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
  if not _capture_device_ok(p_device_id) then
    raise exception 'This phone is not approved';
  end if;
  if length(p_data) > 8000000 then
    raise exception 'The photo is too big';
  end if;
  insert into capture_photos (entry_id, device_id, data) values (p_entry_id, p_device_id, p_data)
  on conflict (entry_id) do nothing;
end;
$$;
grant execute on function capture_submit_photo(uuid, uuid, text) to anon, authenticated;

-- The suppliers to pick from -- only for phones with the Suppliers task.
create or replace function capture_suppliers(p_device_id uuid)
returns json
language plpgsql stable security definer set search_path = public
as $$
begin
  if not _capture_device_ok(p_device_id) then
    raise exception 'This phone is not approved';
  end if;
  if not exists (select 1 from capture_devices where id = p_device_id and 'suppliers' = any (modules)) then
    return '[]'::json;
  end if;
  return (select coalesce(json_agg(json_build_object('id', s.id, 'name', s.name) order by s.name), '[]') from suppliers s);
end;
$$;
grant execute on function capture_suppliers(uuid) to anon, authenticated;
