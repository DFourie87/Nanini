-- The ABSA term loan (FlexiReserve), from its PDF statements: Hub >
-- Financials > Term loan. scripts/import_term_loan.py reads each statement
-- (the client folder's <year>\Bank\Term Loan) into term_loan_statements and
-- its transactions into term_loan_lines; lines added in the hub (a
-- transaction the statement left out) are manual. The loan's balance is the
-- prepaid amount (Arrear/Advance) less the outstanding capital: plus when
-- more has been paid in than is owed. term_loan_opening: the balance at the
-- start of each financial year (1 March), as in the financial statements.
-- Safe to re-run.
create table if not exists term_loan_statements (
  id uuid primary key default gen_random_uuid(),
  account_no text not null,
  statement_date date not null,
  period_from date,
  period_to date,
  capital numeric not null,
  advance numeric not null,
  interest_rate numeric,
  amount_payable numeric,
  payable_date date,
  file_name text,
  -- The month's interest and charges (net) as sent to Xero, and when.
  xero_sent_at timestamptz,
  xero_interest_sent numeric,
  created_at timestamptz not null default now(),
  unique (account_no, statement_date)
);
alter table term_loan_statements add column if not exists xero_sent_at timestamptz;
alter table term_loan_statements add column if not exists xero_interest_sent numeric;
-- The month's interest on the capital ("Interest Portion") and the interest
-- benefit on the prepaid amount, as on the statement.
alter table term_loan_statements add column if not exists interest_portion numeric;
alter table term_loan_statements add column if not exists interest_benefit numeric;

create table if not exists term_loan_lines (
  id uuid primary key default gen_random_uuid(),
  statement_id uuid not null references term_loan_statements(id) on delete cascade,
  line_date date not null,
  description text not null,
  -- As on the statement: plus paid into the loan, minus drawn from it.
  amount numeric not null,
  manual boolean not null default false,
  xero_sent_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists term_loan_lines_statement on term_loan_lines (statement_id);

create table if not exists term_loan_opening (
  account_no text not null,
  year_start date not null,
  balance numeric not null,
  primary key (account_no, year_start)
);

alter table term_loan_statements enable row level security;
alter table term_loan_lines enable row level security;
alter table term_loan_opening enable row level security;
drop policy if exists "Nanini users" on term_loan_statements;
drop policy if exists "Nanini users" on term_loan_lines;
drop policy if exists "Nanini users" on term_loan_opening;
create policy "Nanini users" on term_loan_statements for all to authenticated using (public.is_app_user()) with check (public.is_app_user());
create policy "Nanini users" on term_loan_lines for all to authenticated using (public.is_app_user()) with check (public.is_app_user());
create policy "Nanini users" on term_loan_opening for all to authenticated using (public.is_app_user()) with check (public.is_app_user());

-- So the API (the hub) sees the new tables straight away.
notify pgrst, 'reload schema';

select 'term loan ready' as result,
       (select count(*) from term_loan_statements) as statements,
       (select count(*) from term_loan_lines) as lines;
