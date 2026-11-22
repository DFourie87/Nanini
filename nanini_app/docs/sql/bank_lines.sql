-- The money out of the ABSA current account (card purchases, cash drawn,
-- payments), kept by scripts/import_bank_payments.py from the bank CSVs on
-- the office PC: Hub > Financials > Petty cash checks each cash slip against
-- them (and the credit and fleet card statements) -- a slip of the same
-- amount paid by bank or card a few days around its date was not paid from
-- the petty cash. Only what's needed for that: day, card purchase date,
-- description, amount and balance. Safe to re-run.
create table if not exists bank_lines (
  id uuid primary key default gen_random_uuid(),
  line_date date not null,
  spent_on date,
  description text not null,
  amount numeric not null,
  balance numeric,
  created_at timestamptz not null default now(),
  unique (line_date, description, amount, balance)
);
create index if not exists bank_lines_amount on bank_lines (amount);

alter table bank_lines enable row level security;
drop policy if exists "Nanini users" on bank_lines;
create policy "Nanini users" on bank_lines for all to authenticated using (public.is_app_user()) with check (public.is_app_user());

-- So the API (the hub) sees the new table straight away.
notify pgrst, 'reload schema';

select 'bank lines ready' as result, (select count(*) from bank_lines) as lines;
