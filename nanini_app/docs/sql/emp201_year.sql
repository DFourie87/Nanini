-- EMP201 tax year (run once in the Supabase SQL editor; safe to re-run).
--
-- Employees > Reports > EMP201 tax year: every month's EMP201 worked out,
-- against what was actually submitted to SARS on eFiling ("Ingedien").
-- emp201_history: the months from before the app's payroll, per employee
-- (loaded once from the old salary summary workbook). Admins only.

create table if not exists emp201_history (
  id uuid primary key default gen_random_uuid(),
  month date not null,                 -- the 1st of the month
  employee_name text not null,         -- as in the old workbook
  employee_id uuid references employees(id) on delete set null,
  salary numeric not null default 0,
  uif numeric not null default 0,      -- employee and employer together
  sdl numeric not null default 0,
  paye numeric not null default 0,
  unique (month, employee_name)
);

create table if not exists emp201_submissions (
  month date primary key,              -- the 1st of the month
  uif numeric not null default 0,
  sdl numeric not null default 0,
  paye numeric not null default 0,
  submitted_on date,
  reference text,
  created_at timestamptz not null default now()
);

alter table emp201_history enable row level security;
alter table emp201_submissions enable row level security;
drop policy if exists "Admins only" on emp201_history;
create policy "Admins only" on emp201_history for all to authenticated
  using (public.is_app_admin()) with check (public.is_app_admin());
drop policy if exists "Admins only" on emp201_submissions;
create policy "Admins only" on emp201_submissions for all to authenticated
  using (public.is_app_admin()) with check (public.is_app_admin());

notify pgrst, 'reload schema';
