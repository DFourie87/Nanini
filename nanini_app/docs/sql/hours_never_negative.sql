-- Hours can be taken off on the phone (a negative number, per person or for
-- a whole group) to fix a mistake or a double entry. Safety: a worker's
-- hours for a day may never end up below 0. If an entry would do that, none
-- of it goes in and it stays in the inbox for the office.
-- (Same as hours_already_submitted.sql, plus the check at the end.)

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
  v_date date;
  v_short text;
begin
  select * into v_entry from capture_entries where id = p_id and module = 'hours' and status = 'pending' for update;
  if not found then
    return false;
  end if;
  v_date := (v_entry.payload ->> 'date')::date;
  select coalesce(daily_threshold, 9), coalesce(ot_multiplier, 1.5) into v_threshold, v_ot from hours_settings where id = 1;
  v_threshold := coalesce(v_threshold, 9);
  v_ot := coalesce(v_ot, 1.5);
  -- A total since the last pay isn't one day's hours: no overtime split.
  if (v_entry.payload ->> 'since_last_pay')::boolean is true then
    select greatest(v_threshold, coalesce(max((l ->> 'hours')::numeric), 0)) into v_threshold
      from jsonb_array_elements(coalesce(v_entry.payload -> 'entries', '[]'::jsonb)) l;
  end if;
  begin
    -- Changed on the phone: these workers' hours for that day are replaced.
    delete from hours_entries
     where entry_date = v_date
       and employee_id::text in (select jsonb_array_elements_text(coalesce(v_entry.payload -> 'replace', '[]'::jsonb)));
    for v_line in select * from jsonb_array_elements(coalesce(v_entry.payload -> 'entries', '[]'::jsonb)) loop
      v_hours := (v_line ->> 'hours')::numeric;
      select coalesce(e.rate_per_hour, 0) into v_rate from employees e where e.id = (v_line ->> 'employee_id')::uuid;
      if not found then
        raise exception 'worker % is no longer in the employee list', v_line ->> 'employee_name';
      end if;
      insert into hours_entries (employee_id, entry_date, hours, rate, daily_threshold, ot_multiplier,
                                 normal_hours, ot_hours, gross, via, group_name, farm_id)
      values ((v_line ->> 'employee_id')::uuid, v_date, v_hours, v_rate, v_threshold, v_ot,
              least(v_hours, v_threshold), greatest(v_hours - v_threshold, 0), v_hours * v_rate,
              case when v_entry.payload ->> 'mode' = 'group' then 'group' else 'individual' end,
              case when v_entry.payload ->> 'mode' = 'group' then coalesce(v_entry.payload ->> 'group_name', '') end,
              nullif(v_entry.payload ->> 'farm_id', '')::uuid);
    end loop;
    -- Safety: nobody's hours for that day below 0.
    select string_agg(coalesce(l ->> 'employee_name', 'a worker'), ', ') into v_short
      from jsonb_array_elements(coalesce(v_entry.payload -> 'entries', '[]'::jsonb)) l
     where (select coalesce(sum(h.hours), 0) from hours_entries h
             where h.entry_date = v_date and h.employee_id = (l ->> 'employee_id')::uuid) < -0.001;
    if v_short is not null then
      raise exception 'hours below 0 for %', v_short;
    end if;
  exception when others then
    -- Nothing of this entry is kept; it stays pending for the office.
    return false;
  end;
  update capture_entries set status = 'approved', reviewed_at = now(), reviewed_by = 'Automatic (hours from phone)' where id = p_id;
  return true;
end;
$$;
revoke all on function _capture_apply_hours(uuid) from public, anon, authenticated;
