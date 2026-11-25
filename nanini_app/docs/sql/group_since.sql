-- The day each worker joined their work group: a group's tariff only for
-- hours from that day on -- hours from before (put in later) stay at the
-- worker's own tariff. Set to today whenever a worker's group changes (in
-- the hub, or a phone's Work Groups), unless a day is given (Employees >
-- the worker > "In this group since"). Workers already in a group have no
-- day yet: the group's tariff on all their hours on its farm, as before,
-- until one is set. Needs potato_group_tariff.sql. Safe to re-run.

alter table employees add column if not exists current_group_since date;

create or replace function _employee_group_since() returns trigger
language plpgsql
as $$
begin
  if new.current_group_id is null then
    new.current_group_since := null;
  elsif tg_op = 'INSERT' then
    new.current_group_since := coalesce(new.current_group_since, current_date);
  elsif new.current_group_id is distinct from old.current_group_id
        and new.current_group_since is not distinct from old.current_group_since then
    new.current_group_since := current_date;
  end if;
  return new;
end;
$$;
drop trigger if exists employee_group_since on employees;
create trigger employee_group_since before insert or update of current_group_id, current_group_since on employees
  for each row execute function _employee_group_since();

-- The group tariff of the worker's work group, when the hours are on that
-- group's farm and from the day they joined it; else none (their own tariff).
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
                       where e.id = new.employee_id and g.farm_id = new.farm_id and g.rate_per_hour is not null
                         and (e.current_group_since is null or new.entry_date >= e.current_group_since));
  return new;
end;
$$;

notify pgrst, 'reload schema';

select 'group join dates ready' as result,
       (select count(*) from employees where current_group_id is not null) as in_a_group,
       (select count(*) from employees where current_group_id is not null and current_group_since is null) as no_day_yet;
