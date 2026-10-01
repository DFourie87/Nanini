-- Capture phones > Hours: warns when a worker already has hours for that
-- day and asks whether to change them. Changed hours replace that worker's
-- hours for the day. Needs hours_auto_approve.sql run first.

create or replace function _capture_apply_hours(p_id uuid) returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  v_entry capture_entries%rowtype;
  v_threshold numeric := 9;
  v_ot numeric := 1.5;
  v_line jsonb;
  v_hours numeric;
  v_rate numeric;
begin
  select * into v_entry from capture_entries where id = p_id and module = 'hours' and status = 'pending' for update;
  if not found then
    return false;
  end if;
  select coalesce(daily_threshold, 9), coalesce(ot_multiplier, 1.5) into v_threshold, v_ot from hours_settings where id = 1;
  v_threshold := coalesce(v_threshold, 9);
  v_ot := coalesce(v_ot, 1.5);
  -- A total since the last pay isn't one day's hours: no overtime split.
  if (v_entry.payload ->> 'since_last_pay')::boolean is true then
    select greatest(v_threshold, coalesce(max((l ->> 'hours')::numeric), 0)) into v_threshold
      from jsonb_array_elements(coalesce(v_entry.payload -> 'entries', '[]'::jsonb)) l;
  end if;
  begin
    -- Changed on the phone ("already submitted -- change it"): these
    -- workers' hours for that day are replaced by the new ones.
    delete from hours_entries
     where entry_date = (v_entry.payload ->> 'date')::date
       and employee_id::text in (select jsonb_array_elements_text(coalesce(v_entry.payload -> 'replace', '[]'::jsonb)));
    for v_line in select * from jsonb_array_elements(coalesce(v_entry.payload -> 'entries', '[]'::jsonb)) loop
      v_hours := (v_line ->> 'hours')::numeric;
      select coalesce(e.rate_per_hour, 0) into v_rate from employees e where e.id = (v_line ->> 'employee_id')::uuid;
      if not found then
        raise exception 'worker % is no longer in the employee list', v_line ->> 'employee_name';
      end if;
      insert into hours_entries (employee_id, entry_date, hours, rate, daily_threshold, ot_multiplier,
                                 normal_hours, ot_hours, gross, via, group_name, farm_id)
      values ((v_line ->> 'employee_id')::uuid, (v_entry.payload ->> 'date')::date, v_hours, v_rate, v_threshold, v_ot,
              least(v_hours, v_threshold), greatest(v_hours - v_threshold, 0), v_hours * v_rate,
              case when v_entry.payload ->> 'mode' = 'group' then 'group' else 'individual' end,
              case when v_entry.payload ->> 'mode' = 'group' then coalesce(v_entry.payload ->> 'group_name', '') end,
              nullif(v_entry.payload ->> 'farm_id', '')::uuid);
    end loop;
  exception when others then
    -- Nothing of this entry is kept; it stays pending for the office.
    return false;
  end;
  update capture_entries set status = 'approved', reviewed_at = now(), reviewed_by = 'Automatic (hours from phone)' where id = p_id;
  return true;
end;
$$;
revoke all on function _capture_apply_hours(uuid) from public, anon, authenticated;


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
                      -- UIF as chosen; until chosen, when an ID/passport is on file.
                      'uif_deduct', coalesce((to_jsonb(e) ->> 'uif_deduct')::boolean,
                                             coalesce(trim(to_jsonb(e) ->> 'id_or_passport'), '') <> ''))), '[]') from employees e
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
    'clocked', (select coalesce(json_agg(json_build_object('employee_id', x.employee_id, 'date', x.d, 'hours', x.h)), '[]')
                from (select employee_id, d, sum(h) h from (
                        select h.employee_id::text employee_id, h.entry_date::text d, h.hours h
                          from hours_entries h
                         where h.entry_date >= current_date - 35 and not _nanini_is_member(h.employee_id)
                        union all
                        select l ->> 'employee_id', c.payload ->> 'date', (l ->> 'hours')::numeric
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
