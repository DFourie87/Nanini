-- Each account sale's deductions line by line (run once in the Supabase SQL
-- editor; safe to re-run): the agent's commission, market fees, levies, bank
-- charges... each with its VAT, as on the account sale -- and pallets the
-- buyer paid for (Green Network's pallet invoice) as a minus deduction. The
-- sales importer (scripts/import_sales_report.py) fills it; its totals are
-- the report's commission_before_vat and vat (pallets aside). Used for the
-- Xero invoices: gross less these = what the agent pays.
create table if not exists sales_deductions (
  id uuid primary key default gen_random_uuid(),
  report_id uuid not null references sales_reports(id) on delete cascade,
  ord integer not null default 1,
  -- As on the account sale ("AGENT COMMISSION", "Market Commission",
  -- "BANK CHARGES"), or "Pallets: 31 PALLET @ R65 INCL".
  label text not null,
  -- Before VAT; minus for money back (pallets paid for).
  amount numeric not null,
  vat numeric not null default 0,
  -- 'pallets' for pallets paid for; null for a deduction.
  kind text,
  created_at timestamptz not null default now()
);
create index if not exists sales_deductions_report_idx on sales_deductions (report_id, ord);

alter table sales_deductions enable row level security;
drop policy if exists "Nanini users" on sales_deductions;
create policy "Nanini users" on sales_deductions for all to authenticated
  using (public.is_app_user()) with check (public.is_app_user());

select 'sales_deductions ready' as result;
