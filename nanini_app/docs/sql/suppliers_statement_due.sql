-- Suppliers: what part of a statement is already due (e.g. VKB's
-- "REEDS BETAALBAAR" -- 30, 60-90, 120+ days). The rest (current) is due
-- by the statement's due_date. Safe to run more than once.
alter table public.supplier_docs add column if not exists overdue_amount numeric;
