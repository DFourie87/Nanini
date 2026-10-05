-- Sales > Customers: buyers who pay straight into the bank (run once in the
-- Supabase SQL editor after customers.sql; safe to re-run).
-- bank_match: the name on their deposits in the ABSA bank statements -- each
-- deposit with it becomes a payment on their account (import_bank_payments.py).

alter table customers add column if not exists bank_match text;

insert into customers (name, agent, bank_match, notes) values
  ('Peppadew', 'Peppadew', 'Peppadew', 'Buyer -- pays straight into the bank (ACB CREDIT ... PEPPADEW).')
on conflict (agent) do update set bank_match = excluded.bank_match;

notify pgrst, 'reload schema';

select name, agent, bank_match from customers order by name;
