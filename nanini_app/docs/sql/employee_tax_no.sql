-- Income tax number per employee (run once in the Supabase SQL editor; safe
-- to re-run). SARS income tax reference (10 digits), typed in Employees >
-- List (edit) -- on the EMP501 / IRP5 report.

alter table employees add column if not exists income_tax_no text;

notify pgrst, 'reload schema';
