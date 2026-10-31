-- Packaging bags and boxes bought (run once in the Supabase SQL editor; safe
-- to re-run).
--
-- Packaging > Bags/Boxes: how many potato bags, pepper boxes and butternut
-- bags are on the floor to pack -- bought (here), less 1% for losses, less
-- what went out on the delivery notes.
--   * Potato bags (Crown Bag's invoices, from email): added by
--     scripts/fetch_crown_bags.py, one row per bag on an invoice; each
--     invoice line only once (source_key).
--   * Pepper boxes and butternut bags (and any bags not emailed): typed in
--     on the hub.
-- item: the size as the phones count it -- a potato pallet size ('large10',
-- 'smallmed7', ...), a pepper box ('5kgRed') or a butternut bag ('10kg').
-- kind: 'bought' (qty below 0: returned / credited), 'adjust' (by hand,
-- plus or minus: opening stock, losses, damage -- description says why) or
-- 'count' (counted on the floor: from the end of that day the number starts
-- from it; qty 0 or more).

create table if not exists bag_purchases (
  id uuid primary key default gen_random_uuid(),
  purchase_date date not null,
  produce text not null check (produce in ('potato', 'pepper', 'butternut')),
  item text not null,
  qty integer not null,
  kind text not null default 'bought',
  reference text,
  description text,
  source_key text unique,
  created_at timestamptz not null default now()
);
-- Adjustments and floor counts (also on a table made before they were added).
alter table bag_purchases add column if not exists kind text not null default 'bought';
alter table bag_purchases drop constraint if exists bag_purchases_qty_check;
alter table bag_purchases drop constraint if exists bag_purchases_kind_check;
alter table bag_purchases add constraint bag_purchases_kind_check check (
  kind in ('bought', 'adjust', 'count') and (case when kind = 'count' then qty >= 0 else qty <> 0 end));
create index if not exists bag_purchases_date_idx on bag_purchases (produce, purchase_date);

-- Same rule as every other table: logged-in Nanini users only (the office
-- PC script uses the secret key).
alter table bag_purchases enable row level security;
drop policy if exists "Nanini users" on bag_purchases;
create policy "Nanini users" on bag_purchases for all to authenticated
  using (public.is_app_user()) with check (public.is_app_user());

-- Live updates in the hub.
do $$
begin
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'bag_purchases') then
    alter publication supabase_realtime add table bag_purchases;
  end if;
end $$;

select 'bag_purchases ready: ' || count(*) || ' rows' as result from bag_purchases;
