-- Suppliers: address, VAT number, "supplier of", proof-of-payment email, and
-- a due date per document (run once in the Supabase SQL editor; safe to
-- re-run).
alter table suppliers add column if not exists address text;
alter table suppliers add column if not exists vat_no text;
alter table suppliers add column if not exists category text;
alter table suppliers add column if not exists pop_email text;
-- The due date printed on an invoice / statement (e.g. Eskom's).
alter table supplier_docs add column if not exists due_date date;
notify pgrst, 'reload schema';
