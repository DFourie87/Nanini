-- ATM access code on payslips (run once in the Supabase SQL editor; safe to
-- re-run). Employees paid by ATM card get a 6-digit access code per payday
-- -- the same for everyone paid by ATM that day, new every payday -- made
-- at Run payroll and printed on their payslips.
alter table payslips add column if not exists atm_access_code text;
