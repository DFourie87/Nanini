-- Diesel purchases with their invoice: scripts/fetch_supplier_docs.py puts
-- the supplier's invoice (from Gmail, with the delivery note as a page after
-- it) on the diesel purchase captured for it -- the same delivery note
-- number, else the same litres within 3 days -- for the SARS diesel rebate
-- report (invoice no. and cost). invoice_file is the PDF in the
-- "supplier-docs" storage. Safe to re-run.

alter table diesel_purchases add column if not exists cost numeric;
alter table diesel_purchases add column if not exists invoice_no text;
alter table diesel_purchases add column if not exists invoice_file text;
create index if not exists diesel_purchases_invoice_file on diesel_purchases (invoice_file);

-- So the API sees the columns straight away.
notify pgrst, 'reload schema';

select 'diesel invoices ready' as result,
       (select count(*) from diesel_purchases) as purchases,
       (select count(*) from diesel_purchases where invoice_file is not null) as with_invoice;
