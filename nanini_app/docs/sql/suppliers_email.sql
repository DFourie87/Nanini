-- Suppliers: invoices and statements that arrive by email (run once in the
-- Supabase SQL editor after suppliers.sql; safe to re-run).
--
-- scripts/fetch_supplier_docs.py on the office PC reads new Gmail from the
-- suppliers' email addresses (read-only), uploads the PDF attachments and
-- adds them here as 'to_check', with what it could read filled in. They
-- don't count in the account until someone confirms them in the app.

alter table supplier_docs add column if not exists status text not null default 'confirmed';
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'supplier_docs_status_check') then
    alter table supplier_docs add constraint supplier_docs_status_check check (status in ('confirmed', 'to_check'));
  end if;
end $$;
alter table supplier_docs add column if not exists email_from text;
alter table supplier_docs add column if not exists email_subject text;
alter table supplier_docs add column if not exists email_date date;
-- Gmail message + attachment: the same PDF is never added twice.
alter table supplier_docs add column if not exists email_key text;
create unique index if not exists supplier_docs_email_key on supplier_docs (email_key) where email_key is not null;

notify pgrst, 'reload schema';
