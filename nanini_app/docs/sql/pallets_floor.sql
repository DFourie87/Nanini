-- Packaging > Pallets: the pallets on the floor per market agent, as
-- Bags/Boxes (run once in the Supabase SQL editor; safe to re-run).
--
--   * kind: 'collected' (empty pallets collected at the agent, loaded and
--     returned to it on the potato delivery notes -- every entry so far),
--     'adjust' (plus or minus, with why) or 'count' (on the floor: from the
--     end of that day the number starts from it).
--   * The 400 pallets collected from Grow Green Network were logged under
--     Grow Boland Kaapstad: moved to Grow Green Network.
--   * No pallets on the floor before the 400 came in: a count of 0 for
--     every agent the day before (only if never counted).

alter table delivery_pallet_purchases add column if not exists kind text not null default 'collected';
alter table delivery_pallet_purchases add column if not exists description text;
alter table delivery_pallet_purchases drop constraint if exists delivery_pallet_purchases_qty_check;
alter table delivery_pallet_purchases drop constraint if exists delivery_pallet_purchases_kind_check;
alter table delivery_pallet_purchases add constraint delivery_pallet_purchases_kind_check check (
  kind in ('collected', 'adjust', 'count') and (case when kind = 'count' then qty >= 0 else qty <> 0 end));

do $$
declare
  v_from date;
begin
  -- The 400 under Grow Green Network.
  update delivery_pallet_purchases set agent_name = 'Grow Green Network' where agent_name = 'Grow Boland Kaapstad';

  -- Nothing on the floor before the 400: 0 for every agent the day before.
  select min(purchase_date) into v_from from delivery_pallet_purchases
   where agent_name = 'Grow Green Network' and kind = 'collected' and qty >= 400;
  if v_from is null then
    select min(purchase_date) into v_from from delivery_pallet_purchases where agent_name = 'Grow Green Network' and kind = 'collected';
  end if;
  if v_from is not null and not exists (select 1 from delivery_pallet_purchases where kind = 'count') then
    insert into delivery_pallet_purchases (agent_name, qty, purchase_date, kind, description)
    select a.name, 0, v_from - 1, 'count', 'None on the floor before the 400 from Grow Green Network'
      from (select agent_name as name from delivery_pallet_purchases
            union select agent_name from delivery_notes where produce_type = 'potato' and agent_name is not null) a;
  end if;
end $$;

-- Check: per agent, the pallets collected, the start count and the delivery
-- notes still under Grow Boland Kaapstad (should be none).
select agent_name as agent,
       sum(qty) filter (where kind = 'collected') as collected,
       string_agg(qty || ' collected ' || to_char(purchase_date, 'DD/MM/YYYY'), ', ' order by purchase_date) filter (where kind = 'collected') as entries,
       max(to_char(purchase_date, 'DD/MM/YYYY')) filter (where kind = 'count') as counted_zero_on,
       (select count(*) from delivery_notes n where n.agent_name = 'Grow Boland Kaapstad') as boland_notes_left
from delivery_pallet_purchases
group by agent_name
order by agent_name;
