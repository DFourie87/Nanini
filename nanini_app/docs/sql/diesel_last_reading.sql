-- Diesel on the capture phone: the kilometre / hour meter step starts from
-- the vehicle's last reading. Same capture_reference as hours_moved.sql,
-- with last_reading / last_reading_at added to each vehicle.

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
                      'loan_deduction', to_jsonb(e) -> 'loan_deduction')), '[]') from employees e
                    where not e.is_member and e.on_payroll),
      'hours', (select coalesce(json_agg(json_build_object(
                  'id', h.id, 'employee_id', h.employee_id, 'entry_date', h.entry_date, 'hours', h.hours, 'rate', to_jsonb(h) -> 'rate',
                  'farm_id', to_jsonb(h) ->> 'farm_id')), '[]')
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
      'extras', v_extras
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
                  'id_or_passport', case when v_ids then nullif(trim(to_jsonb(e) ->> 'id_or_passport'), '') end
                ) order by to_jsonb(e) ->> 'first_name'), '[]') from employees e where not e.is_member),
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
                      'price', round(coalesce(
                                 (select b.cost_price from tuckshop_batches b where b.item_id = i.id
                                  order by to_jsonb(b) ->> 'batch_date' desc nulls last limit 1),
                                 (to_jsonb(i) ->> 'last_cost_price')::numeric, 0)
                               * (1 + coalesce((to_jsonb(i) ->> 'profit_pct')::numeric, 35) / 100)),
                      'stock', coalesce((select sum(b.qty) from tuckshop_batches b where b.item_id = i.id), 0)
                    ) order by i.name), '[]')
                  from tuckshop_items i where not coalesce((to_jsonb(i) ->> 'archived')::boolean, false)),
    'pay', v_paydata,
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
