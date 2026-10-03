-- Suppliers: the purchases report and contra (GL) accounts.
-- Run once in the Supabase SQL editor after the other suppliers*.sql files;
-- safe to re-run.

-- What the office PC reads from each PDF: the VAT, a bill's purchases incl.
-- VAT (Eskom), and a few words on what was bought.
alter table public.supplier_docs add column if not exists overdue_amount numeric;
alter table public.supplier_docs add column if not exists vat_amount numeric;
alter table public.supplier_docs add column if not exists purchases_amount numeric;
alter table public.supplier_docs add column if not exists description text;

-- A supplier's contra for invoice lines with VAT on them (Omnia: the
-- transport; its zero-rated fertilizer goes to the category's account).
alter table public.suppliers add column if not exists vat_gl_account text;

-- The chart of accounts the purchases are allocated to (contra accounts).
create table if not exists public.gl_accounts (
  code text primary key,
  name text not null,
  created_at timestamptz not null default now()
);

-- The lines of an invoice / credit note / bill, each against a contra
-- account (null: the remembered one for the item, else the supplier's).
create table if not exists public.supplier_doc_lines (
  id uuid primary key default gen_random_uuid(),
  doc_id uuid not null references public.supplier_docs(id) on delete cascade,
  line_no int not null,
  description text,
  quantity numeric,
  excl_amount numeric not null,
  vat_amount numeric,
  gl_account text,
  created_at timestamptz not null default now(),
  unique (doc_id, line_no)
);
create index if not exists supplier_doc_lines_doc_idx on public.supplier_doc_lines (doc_id);

-- Remembered allocations: this supplier's item goes to this account.
create table if not exists public.supplier_gl_rules (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references public.suppliers(id) on delete cascade,
  item text not null,
  gl_account text not null,
  created_at timestamptz not null default now(),
  unique (supplier_id, item)
);

do $$
declare
  t text;
begin
  foreach t in array array['gl_accounts', 'supplier_doc_lines', 'supplier_gl_rules'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists "Nanini users" on public.%I', t);
    execute format('create policy "Nanini users" on public.%I for all to authenticated using (public.is_app_user()) with check (public.is_app_user())', t);
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = t) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;

-- Start the chart of accounts from the suppliers' categories
-- ("3650 - Electricity & Water" -> 3650 Electricity & Water).
insert into public.gl_accounts (code, name)
select distinct on (m[1]) m[1], trim(m[2])
  from public.suppliers s, regexp_match(s.category, '^\s*(\d+)\s*-\s*(.+)$') m
 where m is not null
 order by m[1]
on conflict (code) do nothing;

notify pgrst, 'reload schema';

select code, name from public.gl_accounts order by code;
