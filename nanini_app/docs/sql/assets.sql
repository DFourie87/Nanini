-- The asset register: Hub > Financials > Asset register. Each asset with
-- its cost, purchase date and rate (straight line on cost, % a year, by the
-- month from the month bought); the register brought in with its figures at
-- the start of a financial year (opening_year, opening_accum: accumulated
-- depreciation then); assets bought since are added from the supplier
-- invoices on a fixed asset account (source_key: that line, once only).
-- asset_dep_overrides: a year's depreciation set by hand. asset_journals:
-- the months whose depreciation journal is in Xero. Safe to re-run.
create table if not exists assets (
  id uuid primary key default gen_random_uuid(),
  category text not null check (category in ('land', 'improvements', 'vehicles', 'implements', 'computers', 'linen', 'software')),
  number int,
  description text not null,
  purchase_date date,
  cost numeric not null,
  rate numeric not null default 20,
  dep_from date,
  opening_year date,
  opening_accum numeric not null default 0,
  disposed_date date,
  disposal_proceeds numeric,
  source_key text unique,
  source text,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists asset_dep_overrides (
  asset_id uuid not null references assets(id) on delete cascade,
  year_start date not null,
  amount numeric not null,
  primary key (asset_id, year_start)
);

create table if not exists asset_journals (
  month date primary key,
  amount numeric not null,
  sent_at timestamptz not null default now()
);

alter table assets enable row level security;
alter table asset_dep_overrides enable row level security;
alter table asset_journals enable row level security;
drop policy if exists "Nanini users" on assets;
drop policy if exists "Nanini users" on asset_dep_overrides;
drop policy if exists "Nanini users" on asset_journals;
create policy "Nanini users" on assets for all to authenticated using (public.is_app_user()) with check (public.is_app_user());
create policy "Nanini users" on asset_dep_overrides for all to authenticated using (public.is_app_user()) with check (public.is_app_user());
create policy "Nanini users" on asset_journals for all to authenticated using (public.is_app_user()) with check (public.is_app_user());

-- So the API (the hub) sees the new tables straight away.
notify pgrst, 'reload schema';

select 'asset register ready' as result, (select count(*) from assets) as assets;
