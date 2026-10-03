-- The last day the bank statements imported into the Suppliers app cover
-- (written by scripts/import_bank_payments.py): what's due is shown as at
-- that day. One row. Safe to re-run.
create table if not exists bank_import (
  id int primary key default 1 check (id = 1),
  last_date date not null,
  imported_at timestamptz not null default now()
);
alter table bank_import enable row level security;
drop policy if exists "Nanini users" on bank_import;
create policy "Nanini users" on bank_import for all to authenticated using (public.is_app_user()) with check (public.is_app_user());
-- Until the next bank import: the bank CSV runs to 30 Sep 2026.
insert into bank_import (id, last_date) values (1, '2026-09-30') on conflict (id) do nothing;
