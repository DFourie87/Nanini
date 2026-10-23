-- Grow Botha Roodt and Botha Roodt Johannesburg are the same market agent:
-- one name, "Grow Botha Roodt Johannesburg", everywhere (run once; safe to
-- re-run). The account sales still match: customers.agent is not changed.
do $$
declare
  v_new constant text := 'Grow Botha Roodt Johannesburg';
  v_keep uuid; v_other uuid;
begin
  -- Delivery notes and pallets bought: under the one name.
  update delivery_notes set agent_name = v_new where agent_name in ('Grow Botha Roodt', 'Botha Roodt Johannesburg');
  update delivery_pallet_purchases set agent_name = v_new where agent_name in ('Grow Botha Roodt', 'Botha Roodt Johannesburg');

  -- Sales > Customers: the name shown (the agent on its account sales stays).
  update customers set name = v_new where name in ('Botha Roodt Johannesburg', 'Grow Botha Roodt');

  -- Delivery contacts: one entry, keeping the contact person and market.
  select id into v_keep from delivery_market_agents where name in (v_new, 'Grow Botha Roodt') order by (name = v_new) desc limit 1;
  for v_other in select id from delivery_market_agents
                  where name in (v_new, 'Grow Botha Roodt', 'Botha Roodt Johannesburg') and id is distinct from v_keep loop
    update delivery_market_agents k
       set attention = coalesce(nullif(k.attention, ''), o.attention), market = coalesce(nullif(k.market, ''), o.market)
      from delivery_market_agents o where k.id = v_keep and o.id = v_other;
    delete from delivery_market_agents where id = v_other;
  end loop;
  update delivery_market_agents set name = v_new where id = v_keep;
end $$;

-- Check: the one name now, and how many notes / pallet purchases carry it.
select 'customer' what, name, agent detail from customers where name ilike '%botha%'
union all select 'delivery contact', name, coalesce(attention, '') || ' / ' || coalesce(market, '') from delivery_market_agents where name ilike '%botha%'
union all select 'delivery notes', agent_name, count(*)::text from delivery_notes where agent_name ilike '%botha%' group by agent_name
union all select 'pallets bought', agent_name, sum(qty)::text from delivery_pallet_purchases where agent_name ilike '%botha%' group by agent_name;
