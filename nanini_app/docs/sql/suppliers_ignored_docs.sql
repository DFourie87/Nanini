-- A document from email removed in the app stays removed: its email is
-- remembered here and the office PC's import (fetch_supplier_docs.py)
-- never brings it in again, also with --rescan. Not when a supplier is
-- deleted (its documents go with it -- an import may bring them back).
-- Safe to re-run.

create table if not exists supplier_doc_ignored (
  email_key text primary key,
  file_name text,
  supplier_id uuid,
  ignored_at timestamptz not null default now()
);
alter table supplier_doc_ignored enable row level security;
drop policy if exists "Nanini users" on supplier_doc_ignored;
create policy "Nanini users" on supplier_doc_ignored for all to authenticated
  using (public.is_app_user()) with check (public.is_app_user());

create or replace function supplier_doc_remember_removed()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  -- Removed by hand (its supplier is still there), not with its supplier.
  if old.email_key is not null and exists (select 1 from suppliers where id = old.supplier_id) then
    insert into supplier_doc_ignored (email_key, file_name, supplier_id)
    values (old.email_key, old.file_name, old.supplier_id)
    on conflict (email_key) do nothing;
  end if;
  return old;
end;
$$;

drop trigger if exists supplier_doc_remember_removed on supplier_docs;
create trigger supplier_doc_remember_removed before delete on supplier_docs
  for each row execute function supplier_doc_remember_removed();
