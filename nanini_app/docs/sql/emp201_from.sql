-- On EMP201 from a day (run once in the Supabase SQL editor; safe to re-run;
-- after emp201_declared.sql).
--
-- An employee registered (e.g. for UIF) part-way through the tax year moves
-- to the "On EMP201" group, but only pay from that day is declared: the
-- months before show their salary only. Set in Employees > List (edit),
-- under "On EMP201". Empty: on it from the start (everyone already on it).

alter table employees add column if not exists emp201_from date;

notify pgrst, 'reload schema';
