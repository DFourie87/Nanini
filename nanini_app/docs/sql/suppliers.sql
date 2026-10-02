-- Hub > Suppliers (run once in the Supabase SQL editor; safe to re-run).
-- Suppliers, their invoices / credit notes / statements (PDFs in the private
-- "supplier-docs" storage bucket) and payments typed in by hand. What's due
-- = opening balance + invoices - credit notes - payments; each statement's
-- closing balance is checked against that on its date.

create table if not exists suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  account_no text,
  contact text,
  phone text,
  email text,
  opening_balance numeric not null default 0,
  opening_date date,
  created_at timestamptz not null default now()
);

create table if not exists supplier_docs (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references suppliers(id) on delete cascade,
  kind text not null check (kind in ('invoice', 'credit_note', 'statement')),
  doc_date date not null,
  reference text,
  amount numeric not null,
  file_path text,
  file_name text,
  notes text,
  created_at timestamptz not null default now()
);
create index if not exists supplier_docs_supplier_idx on supplier_docs (supplier_id, doc_date);

create table if not exists supplier_payments (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references suppliers(id) on delete cascade,
  pay_date date not null,
  amount numeric not null check (amount > 0),
  reference text,
  notes text,
  created_at timestamptz not null default now()
);
create index if not exists supplier_payments_supplier_idx on supplier_payments (supplier_id, pay_date);

-- Same rule as every other table: logged-in Nanini users only.
do $$
declare
  t text;
begin
  foreach t in array array['suppliers', 'supplier_docs', 'supplier_payments'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists "Nanini users" on %I', t);
    execute format('create policy "Nanini users" on %I for all to authenticated using (public.is_app_user()) with check (public.is_app_user())', t);
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = t) then
      execute format('alter publication supabase_realtime add table %I', t);
    end if;
  end loop;
end $$;

-- The PDFs: a private bucket, only for logged-in Nanini users.
insert into storage.buckets (id, name, public)
values ('supplier-docs', 'supplier-docs', false)
on conflict (id) do nothing;

drop policy if exists "Nanini users read supplier docs" on storage.objects;
create policy "Nanini users read supplier docs" on storage.objects for select to authenticated
  using (bucket_id = 'supplier-docs' and public.is_app_user());
drop policy if exists "Nanini users add supplier docs" on storage.objects;
create policy "Nanini users add supplier docs" on storage.objects for insert to authenticated
  with check (bucket_id = 'supplier-docs' and public.is_app_user());
drop policy if exists "Nanini users remove supplier docs" on storage.objects;
create policy "Nanini users remove supplier docs" on storage.objects for delete to authenticated
  using (bucket_id = 'supplier-docs' and public.is_app_user());

notify pgrst, 'reload schema';
