-- On EMP201 (run once in the Supabase SQL editor; safe to re-run).
--
-- Each employee: declared to SARS on the monthly EMP201 or not. Only those
-- ticked count in the EMP201 (Employees > Reports); the EMP201 summary
-- splits everyone paid into: on EMP201, not on it with an ID/passport on
-- file, and not on it without. Admins tick it in Employees > List (edit).
-- To start: everyone in the old salary summary (emp201_history) is on it.

alter table employees add column if not exists on_emp201 boolean not null default false;

do $$
begin
  if to_regclass('public.emp201_history') is not null then
    update employees set on_emp201 = true
    where id in (select employee_id from emp201_history where employee_id is not null);
  end if;
end $$;

notify pgrst, 'reload schema';

-- Check: how many on and off the EMP201, with and without an ID/passport.
select case when on_emp201 then 'On EMP201'
            when coalesce(trim(id_or_passport), '') <> '' then 'Not on EMP201 -- ID/passport on file'
            else 'Not on EMP201 -- no ID/passport' end as grp,
       count(*) as employees
from employees where coalesce(on_payroll, true)
group by 1 order by 1;
