-- Packaging > Records: approving a delivery note (run once in the Supabase
-- SQL editor; safe to re-run). Adds the columns the approve window saves
-- that the table may not have yet, and makes the truck registration and
-- transport company optional.

alter table delivery_notes add column if not exists reg text;
alter table delivery_notes add column if not exists transport_company text;
-- Own truck (FAW): no transport company to bill.
alter table delivery_notes add column if not exists is_self_transport boolean not null default false;
alter table delivery_notes add column if not exists agent_name text;
alter table delivery_notes add column if not exists agent_attention text;
alter table delivery_notes add column if not exists agent_market text;
alter table delivery_notes add column if not exists field text;
alter table delivery_notes add column if not exists farm text;

-- Optional on the note: no "not null" on either.
alter table delivery_notes alter column reg drop not null;
alter table delivery_notes alter column transport_company drop not null;

notify pgrst, 'reload schema';

-- Check: should list is_self_transport, reg and transport_company.
select column_name, data_type, is_nullable
  from information_schema.columns
 where table_name = 'delivery_notes'
   and column_name in ('reg', 'transport_company', 'is_self_transport', 'agent_name', 'agent_attention', 'agent_market', 'field', 'farm')
 order by column_name;
