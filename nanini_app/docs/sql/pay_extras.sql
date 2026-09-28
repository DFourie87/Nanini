-- Extra pay (run once in the Supabase SQL editor; safe to re-run).
--
-- Hours > Work > Extra pay: amounts added to a worker's gross pay on top of
-- their hours -- a set amount (bonus, allowance) or hours at a different
-- rate (e.g. Sunday work). Like tuck shop debt, each stays open until a
-- payroll run pays it (payslip_id), then it's on that payslip.

create table if not exists pay_extras (
  id uuid primary key default gen_random_uuid(),
  employee_id uuid not null references employees(id) on delete cascade,
  farm_id uuid,
  entry_date date not null default current_date,
  description text not null,
  hours numeric,
  rate numeric,
  amount numeric not null,
  payslip_id uuid,
  created_at timestamptz not null default now()
);
create index if not exists pay_extras_open_idx on pay_extras (employee_id) where payslip_id is null;

-- Same rule as every other table: logged-in Nanini users only.
alter table pay_extras enable row level security;
drop policy if exists "Nanini users" on pay_extras;
create policy "Nanini users" on pay_extras for all to authenticated
  using (public.is_app_user()) with check (public.is_app_user());

-- Live updates in the hub.
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'pay_extras') then
    alter publication supabase_realtime add table pay_extras;
  end if;
end $$;

-- What each payslip paid as extras (total, and the lines for printing).
alter table payslips add column if not exists extra_pay numeric not null default 0;
alter table payslips add column if not exists extras jsonb;
