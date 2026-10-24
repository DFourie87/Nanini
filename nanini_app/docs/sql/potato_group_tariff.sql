-- Potato harvest tariff (run once in the Supabase SQL editor; safe to re-run).
--
-- A work group can have its own tariff. Hours clocked on the group's farm
-- for its members are paid at it (shown on the payslip as a line of their
-- own); hours on any other farm stay at the worker's own tariff. Set when
-- the hours go in (from a phone or the hub), so changing a group later
-- doesn't change hours already clocked.
-- Here: R28.50 for "Potatoes - field" and "Potatoes - packhouse" at
-- Limpopodraai. The phones get it too (capture_reference: as in
-- employee_left.sql, plus each day's group tariff).

alter table employee_groups add column if not exists rate_per_hour numeric;
alter table hours_entries add column if not exists special_rate numeric;

-- The group tariff of the worker's work group, when the hours are on that
-- group's farm; else none (the worker's own tariff).
create or replace function _hours_group_rate() returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if tg_op = 'INSERT' and new.special_rate is not null then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.farm_id is not distinct from old.farm_id and new.employee_id = old.employee_id then
    return new;
  end if;
  new.special_rate := (select g.rate_per_hour from employees e join employee_groups g on g.id = e.current_group_id
                       where e.id = new.employee_id and g.farm_id = new.farm_id and g.rate_per_hour is not null);
  return new;
end;
$$;
drop trigger if exists hours_group_rate on hours_entries;
create trigger hours_group_rate before insert or update of farm_id, employee_id on hours_entries
  for each row execute function _hours_group_rate();

update employee_groups g set rate_per_hour = 28.50
from farms f
where f.id = g.farm_id and f.name ilike '%limpopodraai%' and g.name in ('Potatoes - field', 'Potatoes - packhouse');

create or replace function capture_reference(p_device_id uuid)
returns json
language plpgsql stable security definer set search_path = public
as $$
declare
  v_ids boolean;
  v_pay boolean;
  v_extras json := '[]';
  v_paydata json;
begin
  if not _capture_device_ok(p_device_id) then
    raise exception 'This phone is not approved';
  end if;
  select coalesce('employees' = any(modules), false), coalesce('payslips' = any(modules), false)
    into v_ids, v_pay from capture_devices where id = p_device_id;

  -- Payslips task only: what the farm managers check before pay -- each
  -- worker's tariff, rent and loan, hours and picking of the last 120 days,
  -- when they were last paid, tuck shop debt and extra pay not yet paid.
  -- The phone works out "since the last pay" itself, the same as the hub.
  if v_pay then
    if to_regclass('public.pay_extras') is not null then
      execute 'select coalesce(json_agg(json_build_object(''id'', x.id, ''employee_id'', x.employee_id, ''farm_id'', x.farm_id,
                 ''entry_date'', x.entry_date, ''description'', x.description, ''hours'', x.hours, ''rate'', x.rate, ''amount'', x.amount)), ''[]'')
               from pay_extras x where x.payslip_id is null and not _nanini_is_member(x.employee_id)' into v_extras;
    end if;
    v_paydata := json_build_object(
      'employees', (select coalesce(json_agg(json_build_object(
                      'id', e.id, 'first_name', to_jsonb(e) ->> 'first_name', 'last_name', to_jsonb(e) ->> 'last_name',
                      'farm_id', to_jsonb(e) ->> 'farm_id',
                      'rate_per_hour', to_jsonb(e) -> 'rate_per_hour',
                      'rent_deduction', to_jsonb(e) -> 'rent_deduction',
                      'loan_deduction', to_jsonb(e) -> 'loan_deduction',
                      -- On the EMP201: UIF always. Else as chosen; until chosen, when an ID/passport is on file.
                      'on_emp201', to_jsonb(e) -> 'on_emp201',
                      'uif_deduct', coalesce((to_jsonb(e) ->> 'on_emp201')::boolean, false)
                                    or coalesce((to_jsonb(e) ->> 'uif_deduct')::boolean,
                                                coalesce(trim(to_jsonb(e) ->> 'id_or_passport'), '') <> ''))), '[]') from employees e
                    where not e.is_member and e.on_payroll
                      and (to_jsonb(e) ->> 'left_on' is null or (to_jsonb(e) ->> 'left_on')::date > current_date)),
      'hours', (select coalesce(json_agg(json_build_object(
                  'id', h.id, 'employee_id', h.employee_id, 'entry_date', h.entry_date, 'hours', h.hours, 'rate', to_jsonb(h) -> 'rate',
                  'farm_id', to_jsonb(h) ->> 'farm_id', 'special_rate', to_jsonb(h) -> 'special_rate',
                  'group_name', to_jsonb(h) ->> 'group_name')), '[]')
                from hours_entries h where h.entry_date >= current_date - 120 and not _nanini_is_member(h.employee_id)),
      'kg', (select coalesce(json_agg(json_build_object(
               'id', k.id, 'employee_id', k.employee_id, 'entry_date', k.entry_date, 'kg', k.kg,
               'rate_per_kg', to_jsonb(k) -> 'rate_per_kg', 'gross', to_jsonb(k) -> 'gross')), '[]')
             from kg_entries k where k.entry_date >= current_date - 120 and not _nanini_is_member(k.employee_id)),
      'tuck', (select coalesce(json_agg(json_build_object(
                 'id', p.id, 'employee_id', p.employee_id, 'sale_date', p.sale_date, 'revenue', p.revenue,
                 'item_id', to_jsonb(p) ->> 'item_id', 'qty', to_jsonb(p) -> 'qty', 'note', to_jsonb(p) ->> 'note',
                 'farm_id', to_jsonb(p) ->> 'farm_id')), '[]')
               from tuckshop_purchases p where p.payslip_id is null and not _nanini_is_member(p.employee_id)),
      'paid', (select coalesce(json_agg(json_build_object(
                 'id', s.employee_id, 'employee_id', s.employee_id, 'farm_id', s.farm_id,
                 'period_start', s.period_start, 'period_end', s.period_end, 'paid_date', s.paid_date)), '[]')
               from (select employee_id, farm_id, min(period_start) period_start, max(period_end) period_end, max(paid_date) paid_date
                     from payslips where not _nanini_is_member(employee_id) group by employee_id, farm_id) s),
      'extras', v_extras,
      -- Sent from any phone and not yet approved: hours, picking, tuck shop
      -- sales and payslip checks. Payslips works them in, so it shows what
      -- the office will pay once they're approved.
      'pending', (select coalesce(json_agg(json_build_object(
                    'id', c.id, 'module', c.module, 'payload', c.payload, 'captured_at', c.captured_at) order by c.captured_at), '[]')
                  from capture_entries c
                  where c.status in ('pending', 'approving') and c.module in ('hours', 'kg', 'tuckshop', 'pay_check'))
    );
  end if;
  -- Columns are read through to_jsonb(row) so a database that's missing an
  -- optional column (added by a later migration) still returns the lists,
  -- just without that detail, instead of failing outright.
  return json_build_object(
    'farms', (select coalesce(json_agg(json_build_object('id', f.id, 'name', f.name) order by f.name), '[]') from farms f),
    'people', (select coalesce(json_agg(json_build_object(
                  'id', e.id,
                  'name', trim(coalesce(to_jsonb(e) ->> 'first_name', '') || ' ' || coalesce(to_jsonb(e) ->> 'last_name', '')),
                  'farm_id', to_jsonb(e) ->> 'farm_id',
                  'group_id', to_jsonb(e) ->> 'current_group_id',
                  -- For the phone's "Employee details" task: names as on
                  -- the ID and whether an ID/passport is on file; the
                  -- number itself only for phones with that task ticked.
                  'full_names', to_jsonb(e) ->> 'full_names',
                  'surname', to_jsonb(e) ->> 'surname',
                  'has_id', coalesce(nullif(trim(to_jsonb(e) ->> 'id_or_passport'), ''), '') <> '',
                  'id_or_passport', case when v_ids then nullif(trim(to_jsonb(e) ->> 'id_or_passport'), '') end,
                  -- How they're paid and the details, for Employee details
                  -- (like the ID number, only to phones with that task).
                  'payment_method', case when v_ids then coalesce(to_jsonb(e) ->> 'payment_method', 'cash') end,
                  'bank_name', case when v_ids then nullif(trim(to_jsonb(e) ->> 'bank_name'), '') end,
                  'bank_account_no', case when v_ids then nullif(trim(to_jsonb(e) ->> 'bank_account_no'), '') end,
                  'phone_number', case when v_ids then nullif(trim(to_jsonb(e) ->> 'phone_number'), '') end
                ) order by to_jsonb(e) ->> 'first_name'), '[]') from employees e where not e.is_member
                    and (to_jsonb(e) ->> 'left_on' is null or (to_jsonb(e) ->> 'left_on')::date > current_date)),
    -- Members: names only (diesel "who filled", on every farm's list).
    'members', (select coalesce(json_agg(json_build_object(
                  'id', e.id,
                  'name', trim(coalesce(to_jsonb(e) ->> 'first_name', '') || ' ' || coalesce(to_jsonb(e) ->> 'last_name', '')),
                  'surname', to_jsonb(e) ->> 'surname'
                ) order by to_jsonb(e) ->> 'first_name'), '[]') from employees e where e.is_member),
    'groups', (select coalesce(json_agg(json_build_object('id', g.id, 'name', g.name, 'farm_id', to_jsonb(g) ->> 'farm_id') order by g.name), '[]')
               from employee_groups g),
    'tanks', (select coalesce(json_agg(json_build_object('id', t.id, 'name', t.name) order by t.name), '[]') from diesel_tanks t),
    -- Each vehicle's latest meter reading (approved, or captured and still
    -- waiting in the inbox): the phone starts from it and wants a new one.
    'vehicles', (select coalesce(json_agg(json_build_object('id', v.id, 'name', v.name, 'unit', coalesce(to_jsonb(v) ->> 'unit', 'hours'),
                   'last_reading', r.reading, 'last_reading_at', r.at) order by v.name), '[]')
                 from diesel_vehicles v
                 left join lateral (
                   select x.reading, x.at from (
                     select trim(u.hours) reading, u.created_at at from diesel_usage u
                      where u.equipment = v.name and coalesce(trim(u.hours), '') <> ''
                     union all
                     select trim(c.payload ->> 'reading'), c.captured_at from capture_entries c
                      where c.module = 'diesel_usage' and c.status in ('pending', 'approving')
                        and c.payload ->> 'vehicle_id' = v.id::text and coalesce(trim(c.payload ->> 'reading'), '') <> ''
                   ) x order by x.at desc nulls last limit 1
                 ) r on true),
    'activities', (select coalesce(json_agg(json_build_object('id', a.id, 'name', a.name)
                     order by coalesce((to_jsonb(a) ->> 'sort_order')::numeric, 0), a.name), '[]') from diesel_activities a),
    -- Sell price = latest batch's cost (or last cost) + profit %, rounded,
    -- the same as the Tuck Shop app.
    'shop_items', (select coalesce(json_agg(json_build_object(
                      'id', i.id, 'name', i.name, 'farm_id', to_jsonb(i) ->> 'farm_id',
                      -- A fixed selling price when one is set, else cost + margin.
                      'price', coalesce((to_jsonb(i) ->> 'fixed_sell_price')::numeric, round(coalesce(
                                 (select b.cost_price from tuckshop_batches b where b.item_id = i.id
                                  order by to_jsonb(b) ->> 'batch_date' desc nulls last limit 1),
                                 (to_jsonb(i) ->> 'last_cost_price')::numeric, 0)
                               * (1 + coalesce((to_jsonb(i) ->> 'profit_pct')::numeric, 35) / 100))),
                      'stock', coalesce((select sum(b.qty) from tuckshop_batches b where b.item_id = i.id), 0)
                    ) order by i.name), '[]')
                  from tuckshop_items i where not coalesce((to_jsonb(i) ->> 'archived')::boolean, false)),
    'pay', v_paydata,
    -- Hours already there per worker per day (the last 5 weeks, and any
    -- still on their way): the phone warns before clocking someone twice.
    -- And which farm(s) clocked them ("clocked by Limpopodraai").
    'clocked', (select coalesce(json_agg(json_build_object('employee_id', x.employee_id, 'date', x.d, 'hours', x.h, 'farms', x.farms)), '[]')
                from (select employee_id, d, sum(h) h, string_agg(distinct farm, ', ') farms from (
                        select h.employee_id::text employee_id, h.entry_date::text d, h.hours h, f.name farm
                          from hours_entries h left join farms f on f.id = h.farm_id
                         where h.entry_date >= current_date - 35 and not _nanini_is_member(h.employee_id)
                        union all
                        select l ->> 'employee_id', c.payload ->> 'date', (l ->> 'hours')::numeric, c.payload ->> 'farm_name'
                          from capture_entries c, jsonb_array_elements(coalesce(c.payload -> 'entries', '[]'::jsonb)) l
                         where c.module = 'hours' and c.status in ('pending', 'approving')
                           and (c.payload ->> 'date')::date >= current_date - 35
                      ) u group by employee_id, d) x),
    -- Group members clocked as "worked on other farm" in the last week: the
    -- phone of the farm they went to is told to clock them there.
    'moved', (select coalesce(json_agg(json_build_object(
                 'employee_id', m ->> 'employee_id', 'employee_name', m ->> 'employee_name',
                 'farm_id', m ->> 'farm_id', 'from_farm_name', e.payload ->> 'farm_name',
                 'date', e.payload ->> 'date')), '[]')
               from capture_entries e, jsonb_array_elements(coalesce(e.payload -> 'moved', '[]'::jsonb)) m
               where e.module = 'hours' and e.status <> 'rejected'
                 and e.captured_at > now() - interval '7 days')
  );
end;
$$;
grant execute on function capture_reference(uuid) to anon, authenticated;

notify pgrst, 'reload schema';

-- The groups at Limpopodraai, their tariff, and the hours their members
-- already have there since their last payslip (still at their own tariff).
select g.name as work_group, g.rate_per_hour as group_tariff,
       count(distinct e.id) as members,
       count(h.id) as days_already_clocked_here,
       coalesce(sum(h.hours), 0) as hours_already_clocked_here
from employee_groups g
join farms f on f.id = g.farm_id and f.name ilike '%limpopodraai%'
left join employees e on e.current_group_id = g.id
left join hours_entries h on h.employee_id = e.id and h.farm_id = g.farm_id and h.special_rate is null
  and h.entry_date > coalesce((select max(p.period_end) from payslips p where p.employee_id = e.id), '1900-01-01')
group by g.name, g.rate_per_hour
order by g.name;
