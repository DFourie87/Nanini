-- Pallets collected at an agent that Nanini paid for (run once in the
-- Supabase SQL editor; safe to re-run). Packaging > Pallets > Add collected
-- can say how many of the pallets collected Nanini paid the agent for, and
-- the amount: bought, not Nanini's own coming back, so they don't take the
-- agent's balance down. Shown in the agent's pallet reconciliation.
alter table delivery_pallet_purchases add column if not exists paid_qty integer not null default 0;
alter table delivery_pallet_purchases add column if not exists paid_amount numeric;

notify pgrst, 'reload schema';

select 'pallets paid by Nanini ready' as result;
