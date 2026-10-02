-- Suppliers: banking details and payment terms (run once in the Supabase
-- SQL editor after suppliers.sql; safe to re-run).
alter table suppliers add column if not exists bank_name text;
alter table suppliers add column if not exists bank_account_holder text;
alter table suppliers add column if not exists bank_account_no text;
alter table suppliers add column if not exists bank_branch_code text;
alter table suppliers add column if not exists payment_reference text;
-- Invoices fall due terms_days after the invoice ('invoice') or after the
-- end of the invoice's month ('statement').
alter table suppliers add column if not exists terms_kind text not null default 'invoice';
alter table suppliers add column if not exists terms_days integer not null default 30;
notify pgrst, 'reload schema';
