-- Sales > Customers (run once in the Supabase SQL editor; safe to re-run).
-- The market agents the farm sells through, and their payment summaries
-- (afrekeningstate): which account sales each payment paid. What an agent
-- owes = the nett of its account sales in Sales (sales_reports, by agent)
-- not yet on a payment summary.

create table if not exists customers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  -- The agent as on its account sales in Sales (sales_reports.agent).
  agent text not null unique,
  -- Nanini's account number with the agent.
  account_no text,
  -- Where its documents come from: email addresses or @domains, or a note.
  emails text,
  opening_balance numeric not null default 0,
  opening_date date,
  notes text,
  created_at timestamptz not null default now()
);
create unique index if not exists customers_name_unique on customers (lower(btrim(name)));

-- A payment summary: one payment, on its date.
create table if not exists customer_payments (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references customers(id) on delete cascade,
  pay_date date not null,
  amount numeric not null,
  -- Transfer / cheque, as on the summary.
  method text,
  file_name text,
  -- The receipt in the bank (from the ABSA CSVs), once found.
  bank_date date,
  bank_reference text,
  notes text,
  created_at timestamptz not null default now(),
  unique (customer_id, pay_date, amount)
);
create index if not exists customer_payments_customer_idx on customer_payments (customer_id, pay_date);

-- Each account sale a payment paid.
create table if not exists customer_payment_lines (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references customer_payments(id) on delete cascade,
  line_no int not null,
  -- The account sale's number (sales_reports.report_number).
  report_number text not null,
  delivery_note text,
  received date,
  sales numeric,
  deductions numeric,
  loans numeric not null default 0,
  nett numeric not null,
  qty numeric,
  unique (payment_id, line_no)
);
create index if not exists customer_payment_lines_report_idx on customer_payment_lines (report_number);

-- Same rule as every other table: logged-in Nanini users only.
do $$
declare
  t text;
begin
  foreach t in array array['customers', 'customer_payments', 'customer_payment_lines'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists "Nanini users" on %I', t);
    execute format('create policy "Nanini users" on %I for all to authenticated using (public.is_app_user()) with check (public.is_app_user())', t);
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = t) then
      execute format('alter publication supabase_realtime add table %I', t);
    end if;
  end loop;
end $$;

-- The market agents (Nanini Boerdery is producer 92220 at every market).
-- customer@joburgmarket.co.za sends for several Joburg agents: its documents
-- go to the agent named in them.
insert into customers (name, agent, account_no, emails) values
  ('Wenpro Markagente', 'Wenpro Markagente', '0278929', 'admin@wenpro.co.za, customer@joburgmarket.co.za'),
  ('Dapper Agencies', 'Dapper Agencies', '0333427', 'dapper@dmv.co.za, customer@joburgmarket.co.za'),
  ('CL de Villiers Markagente', 'CL de Villiers Markagente', '0346890', 'cldevilliers@dataperfect.co.za, customer@joburgmarket.co.za'),
  ('Botha Roodt Johannesburg', 'Botha Roodt Johannesburg', '0416339', 'elmarie@botharoodt.com, customer@joburgmarket.co.za'),
  ('RSA Markagente', 'RSA Markagente Pretoria', '12683', 'Not emailed: downloaded from Technofresh into the BTW folder'),
  ('Universal Leaf South Africa', 'Universal Leaf South Africa', null, '@universalleaf.com')
on conflict (agent) do nothing;

notify pgrst, 'reload schema';

select name, agent, account_no, emails from customers order by name;
