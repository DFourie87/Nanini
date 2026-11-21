-- The VAT control (Hub > Financials > VAT control): per two-month period,
-- what the hub doesn't have (other standard-rated and zero-rated supplies:
-- hunting, game sales, rent, insurance claims; capital supplies), the diesel
-- refund and the VAT201 as submitted. vat_years: the sales per the
-- financial statements, to agree the declared sales to. Safe to re-run.
create table if not exists vat_periods (
  period_start date primary key,
  other_standard numeric not null default 0,
  other_zero numeric not null default 0,
  capital_supplies numeric not null default 0,
  diesel_refund numeric not null default 0,
  vat201_output numeric,
  vat201_input numeric,
  vat201_diesel numeric,
  notes text,
  updated_at timestamptz not null default now()
);

create table if not exists vat_years (
  year_start date primary key,
  fs_sales numeric not null
);

-- The game register (Hub > Financials > Game register): the game counted on
-- each farm at the year end (28 February) and its value per head.
create table if not exists game_register (
  id uuid primary key default gen_random_uuid(),
  year_start date not null,
  farm text not null,
  species text not null,
  head int not null default 0,
  value numeric not null default 0,
  ord int not null default 0,
  unique (year_start, farm, species)
);

alter table vat_periods enable row level security;
alter table vat_years enable row level security;
alter table game_register enable row level security;
drop policy if exists "Nanini users" on vat_periods;
drop policy if exists "Nanini users" on vat_years;
drop policy if exists "Nanini users" on game_register;
create policy "Nanini users" on vat_periods for all to authenticated using (public.is_app_user()) with check (public.is_app_user());
create policy "Nanini users" on vat_years for all to authenticated using (public.is_app_user()) with check (public.is_app_user());
create policy "Nanini users" on game_register for all to authenticated using (public.is_app_user()) with check (public.is_app_user());

-- So the API (the hub) sees the new tables straight away.
notify pgrst, 'reload schema';

select 'VAT control and game register ready' as result,
       (select count(*) from vat_periods) as vat_periods,
       (select count(*) from game_register) as game_rows;
