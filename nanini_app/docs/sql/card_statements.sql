-- ABSA's credit card and fleet card, from their PDF statements: Hub >
-- Financials > Credit card / Fleet card. scripts/import_card_statements.py
-- reads each statement (the client folder's <year>\Bank\Credit card and
-- Fleet Card) into card_statements and its lines into card_lines; lines
-- added in the hub are manual. Amounts as in Xero's bank account: plus is
-- money into the card (a payment, credit interest), minus spent or charged;
-- a balance in credit is plus, one owed to ABSA minus. card_opening: the
-- balance at the start of each financial year (1 March), as in the
-- financial statements. Safe to re-run.
create table if not exists card_statements (
  id uuid primary key default gen_random_uuid(),
  card text not null check (card in ('credit', 'fleet')),
  account_no text,
  statement_date date not null,
  period_from date,
  period_to date,
  statement_no int,
  opening numeric not null,
  closing numeric not null,
  file_name text,
  created_at timestamptz not null default now(),
  unique (card, statement_date)
);

create table if not exists card_lines (
  id uuid primary key default gen_random_uuid(),
  statement_id uuid not null references card_statements(id) on delete cascade,
  line_date date not null,
  description text not null,
  reference text,
  amount numeric not null,
  manual boolean not null default false,
  xero_sent_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists card_lines_statement on card_lines (statement_id);

create table if not exists card_opening (
  card text not null,
  year_start date not null,
  balance numeric not null,
  primary key (card, year_start)
);

alter table card_statements enable row level security;
alter table card_lines enable row level security;
alter table card_opening enable row level security;
drop policy if exists "Nanini users" on card_statements;
drop policy if exists "Nanini users" on card_lines;
drop policy if exists "Nanini users" on card_opening;
create policy "Nanini users" on card_statements for all to authenticated using (public.is_app_user()) with check (public.is_app_user());
create policy "Nanini users" on card_lines for all to authenticated using (public.is_app_user()) with check (public.is_app_user());
create policy "Nanini users" on card_opening for all to authenticated using (public.is_app_user()) with check (public.is_app_user());

-- So the API (the hub) sees the new tables straight away.
notify pgrst, 'reload schema';

select 'cards ready' as result,
       (select count(*) from card_statements where card = 'credit') as credit_card_statements,
       (select count(*) from card_statements where card = 'fleet') as fleet_card_statements;
