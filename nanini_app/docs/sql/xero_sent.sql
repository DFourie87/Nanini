-- What the hub has already sent to Xero (run once in the Supabase SQL
-- editor; safe to re-run). Financials > Xero export saves only the account
-- sales and supplier invoices not sent yet, and marks them sent once the
-- CSV is saved -- so the same invoice never goes to Xero twice. The total
-- sent is kept too: a document changed afterwards is listed as "changed
-- since sent" (to fix in Xero by hand) instead of going again.
alter table sales_reports add column if not exists xero_sent_at timestamptz;
alter table sales_reports add column if not exists xero_sent_total numeric;
alter table supplier_docs add column if not exists xero_sent_at timestamptz;
alter table supplier_docs add column if not exists xero_sent_total numeric;

-- So the API (the hub) sees the new columns straight away.
notify pgrst, 'reload schema';

select 'xero_sent ready' as result;
