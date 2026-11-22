-- Petty cash slips: Nanini Capture > CASH SLIP (a photo of the till slip
-- with its shop, total, VAT, what it was for and date, from a phone with
-- the Suppliers task) waits in Hub > Financials > Petty cash until someone
-- checks it and puts it against an account; it is then kept in cash_slips
-- (the photo in cash_slip_photos) and sent to Xero as spend money from the
-- Petty Cash bank account, with the photo attached. Slips can also be added
-- in the hub. Needs suppliers_capture.sql and fridge_sheet_photos.sql.
-- Safe to re-run.

alter table capture_entries drop constraint if exists capture_entries_module_check;
alter table capture_entries add constraint capture_entries_module_check
  check (module in ('diesel_usage', 'diesel_purchase', 'hours', 'kg', 'tuckshop', 'delivery', 'employee', 'pay_check',
                    'work_groups', 'supplier_doc', 'timesheet', 'fridge_sheet', 'cash_slip'));

create table if not exists cash_slips (
  id uuid primary key default gen_random_uuid(),
  slip_date date not null,
  shop text not null,
  description text,
  -- The total paid (with VAT), and the VAT on it (0: none, or not a tax invoice).
  amount numeric not null check (amount > 0),
  vat numeric not null default 0 check (vat >= 0),
  gl_account text,
  source text,
  xero_id text,
  xero_sent_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists cash_slips_date on cash_slips (slip_date);
-- A slip of the same amount as a bank or card payment around its date is
-- held back as "paid by bank already"; ticked when it was the petty cash after all.
alter table cash_slips add column if not exists cash_confirmed boolean not null default false;

create table if not exists cash_slip_photos (
  slip_id uuid primary key references cash_slips(id) on delete cascade,
  data text not null -- JPEG, base64
);

alter table cash_slips enable row level security;
alter table cash_slip_photos enable row level security;
drop policy if exists "Nanini users" on cash_slips;
drop policy if exists "Nanini users" on cash_slip_photos;
create policy "Nanini users" on cash_slips for all to authenticated using (public.is_app_user()) with check (public.is_app_user());
create policy "Nanini users" on cash_slip_photos for all to authenticated using (public.is_app_user()) with check (public.is_app_user());

-- So the API (the hub) sees the new tables straight away.
notify pgrst, 'reload schema';

select 'cash slips ready' as result, (select count(*) from cash_slips) as slips;
