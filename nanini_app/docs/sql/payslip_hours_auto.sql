-- Hours typed on the first page of Payslips in the capture app (hours since
-- the last pay) don't wait for approval either: when the phone sends the
-- Payslips check, the difference goes straight into the hours (one entry on
-- that day, no overtime split -- it's a total), so it shows in the hub's
-- Summary and payslips at once. The rest of the check (tariff, rent, loan,
-- UIF, tuck shop debt, extra pay) still goes to "To be approved"; if there's
-- nothing else in it, it's marked approved.
-- Needs hours_auto_approve.sql (or later) run first.

create or replace function _capture_apply_paycheck_hours(p_id uuid) returns boolean
language plpgsql security definer set search_path = public
as $$
declare
  v_entry capture_entries%rowtype;
  v_threshold numeric := 9;
  v_ot numeric := 1.5;
  v_c jsonb;
  v_diff numeric;
  v_rate numeric;
  v_rest boolean := false;
begin
  select * into v_entry from capture_entries
   where id = p_id and module = 'pay_check' and status = 'pending'
     and coalesce((payload ->> 'hours_applied')::boolean, false) = false
   for update;
  if not found then
    return false;
  end if;
  select coalesce(daily_threshold, 9), coalesce(ot_multiplier, 1.5) into v_threshold, v_ot from hours_settings where id = 1;
  v_threshold := coalesce(v_threshold, 9);
  v_ot := coalesce(v_ot, 1.5);
  begin
    for v_c in select * from jsonb_array_elements(coalesce(v_entry.payload -> 'changes', '[]'::jsonb)) loop
      if v_c ? 'rate_per_hour' or v_c ? 'rent_deduction' or v_c ? 'loan_deduction'
         or v_c ? 'uif_deduct' or v_c ? 'tuckshop_debt' then
        v_rest := true;
      end if;
      if v_c ->> 'hours_since_last_pay' is null then
        continue;
      end if;
      v_diff := (v_c ->> 'hours_since_last_pay')::numeric - coalesce((v_c ->> 'hours_was')::numeric, 0);
      if abs(v_diff) < 0.001 then
        continue;
      end if;
      -- The new tariff, if this check changes it too.
      select coalesce((v_c ->> 'rate_per_hour')::numeric, e.rate_per_hour, 0) into v_rate from employees e where e.id = (v_c ->> 'employee_id')::uuid;
      if not found then
        raise exception 'worker % is no longer in the employee list', v_c ->> 'employee_name';
      end if;
      insert into hours_entries (employee_id, entry_date, hours, rate, daily_threshold, ot_multiplier,
                                 normal_hours, ot_hours, gross, via, group_name, farm_id)
      values ((v_c ->> 'employee_id')::uuid,
              coalesce(nullif(v_c ->> 'hours_up_to', '')::date, v_entry.captured_at::date),
              v_diff, v_rate, greatest(v_threshold, abs(v_diff)), v_ot,
              v_diff, 0, v_diff * v_rate, 'individual', null,
              nullif(v_entry.payload ->> 'farm_id', '')::uuid);
    end loop;
  exception when others then
    -- Nothing of it is kept; the office approves it as before.
    return false;
  end;
  if not v_rest and jsonb_array_length(coalesce(v_entry.payload -> 'extras', '[]'::jsonb)) = 0 then
    update capture_entries
       set payload = payload || '{"hours_applied": true}'::jsonb,
           status = 'approved', reviewed_at = now(), reviewed_by = 'Automatic (hours from phone)'
     where id = p_id;
  else
    update capture_entries set payload = payload || '{"hours_applied": true}'::jsonb where id = p_id;
  end if;
  return true;
end;
$$;
revoke all on function _capture_apply_paycheck_hours(uuid) from public, anon, authenticated;

create or replace function capture_submit(p_device_id uuid, p_entries jsonb)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  v_name text;
  v_count integer := 0;
  v_e jsonb;
  v_id uuid;
begin
  if not _capture_device_ok(p_device_id) then
    raise exception 'This phone is not approved';
  end if;
  select name into v_name from capture_devices where id = p_device_id;
  for v_e in select * from jsonb_array_elements(p_entries) loop
    v_id := null;
    insert into capture_entries (id, device_id, device_name, module, payload, summary, captured_at, status)
    values ((v_e ->> 'id')::uuid, p_device_id, v_name, v_e ->> 'module', v_e -> 'payload', left(v_e ->> 'summary', 300),
            (v_e ->> 'captured_at')::timestamptz, 'pending')
    on conflict (id) do nothing
    returning id into v_id;
    if v_id is not null then
      v_count := v_count + 1;
      -- Hours need no approval (Hours task, and hours on Payslips).
      if v_e ->> 'module' = 'hours' then
        perform _capture_apply_hours(v_id);
      elsif v_e ->> 'module' = 'pay_check' then
        perform _capture_apply_paycheck_hours(v_id);
      end if;
    end if;
  end loop;
  return v_count;
end;
$$;
grant execute on function capture_submit(uuid, jsonb) to anon, authenticated;

-- Payslips checks already waiting in the inbox: their hours go in now.
select count(*) filter (where _capture_apply_paycheck_hours(id)) as payslip_checks_with_hours_added
from capture_entries where module = 'pay_check' and status = 'pending';
