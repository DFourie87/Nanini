-- Hours captured on the phones (Hours task) don't wait for approval: when a
-- phone sends them, they go straight into the hours (as approving them in the
-- hub did -- the worker's tariff, the overtime threshold from the settings)
-- and the entry is marked approved ("Automatic"). If one can't be added
-- (e.g. the worker was removed), it stays in the inbox for the office.
-- Picking (kg, needs the rate) and payslip checks still go to the inbox.

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
      -- Hours need no approval.
      if v_e ->> 'module' = 'hours' then
        perform _capture_apply_hours(v_id);
      end if;
    end if;
  end loop;
  return v_count;
end;
$$;
grant execute on function capture_submit(uuid, jsonb) to anon, authenticated;

-- Hours already waiting in the inbox go in now too.
select count(*) filter (where _capture_apply_hours(id)) as hours_entries_added_now
from capture_entries where module = 'hours' and status = 'pending';
