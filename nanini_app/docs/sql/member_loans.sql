-- Members' loans (run once in the Supabase SQL editor; safe to re-run).
--
-- Employees > Summary > Members: what Nanini 121 CC owes a member on their
-- members loan, and the repayments made to them (e.g. JM Fourie, not on
-- payroll, repaid a monthly amount). Kept apart from payroll: never on a
-- payslip or in a payroll run. Admins only -- staff logins get nothing.

create table if not exists member_loan_entries (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  entry_date date not null default current_date,
  -- 'loan': lent to the CC (the balance goes up); 'repayment': paid back.
  kind text not null default 'repayment' check (kind in ('loan', 'repayment')),
  amount numeric not null check (amount > 0),
  note text,
  created_at timestamptz not null default now()
);
create index if not exists member_loan_entries_employee_idx on member_loan_entries (employee_id, entry_date);

alter table member_loan_entries enable row level security;
drop policy if exists "Admins only" on member_loan_entries;
create policy "Admins only" on member_loan_entries for all to authenticated
  using (public.is_app_admin()) with check (public.is_app_admin());

notify pgrst, 'reload schema';
