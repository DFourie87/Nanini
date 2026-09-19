-- ============================================================================
-- Nanini App — diesel price forecast (CEF daily bulletin)
-- ============================================================================
-- Run this ONCE in the Supabase SQL editor (Dashboard → SQL Editor → New query
-- → paste this whole file → Run). Safe to re-run.
--
-- Holds a single row: the latest CEF "Daily Basic Fuel Price" bulletin's
-- diesel 0.05% sulphur under/over-recovery, converted to the Rand amount
-- and date it's expected to hit the pump at the next price adjustment
-- (South Africa's fuel prices change on the first Wednesday of each month).
-- Written by scripts/fetch_diesel_price_forecast.py (run daily, same
-- schedule as the sales importer), read live by the app's diesel Reports
-- tab.
-- ============================================================================

create table if not exists diesel_price_forecast (
  id smallint primary key default 1,
  fuel_type text not null default 'diesel_0_05',
  bulletin_date date not null,
  next_adjustment_date date not null,
  expected_change_rand numeric not null,
  updated_at timestamptz not null default now(),
  constraint diesel_price_forecast_singleton check (id = 1)
);

alter table diesel_price_forecast enable row level security;

drop policy if exists "Allow read" on diesel_price_forecast;
create policy "Allow read" on diesel_price_forecast for select using (true);

drop policy if exists "Allow upsert" on diesel_price_forecast;
create policy "Allow upsert" on diesel_price_forecast for insert with check (true);

drop policy if exists "Allow update" on diesel_price_forecast;
create policy "Allow update" on diesel_price_forecast for update using (true);
