-- After potato_group_tariff.sql (safe to re-run): the group tariff counts
-- from a start date -- the potato harvest from 19 Oct 2026. Hours of the
-- potato field and packhouse workers at Limpopodraai from that day get
-- R28.50 (also those already clocked, not yet on a payslip); days before it
-- stay at the old tariff, also when clocked late.

alter table employee_groups add column if not exists rate_from date;

update employee_groups g set rate_from = '2026-10-19'
from farms f
where f.id = g.farm_id and f.name ilike '%limpopodraai%' and g.name in ('Potatoes - field', 'Potatoes - packhouse');

-- The group tariff of the worker's work group, when the hours are on that
-- group's farm and from its start date; else none (the worker's own tariff).
create or replace function _hours_group_rate() returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if tg_op = 'INSERT' and new.special_rate is not null then
    return new;
  end if;
  if tg_op = 'UPDATE' and new.farm_id is not distinct from old.farm_id and new.employee_id = old.employee_id
     and new.entry_date = old.entry_date then
    return new;
  end if;
  new.special_rate := (select g.rate_per_hour from employees e join employee_groups g on g.id = e.current_group_id
                       where e.id = new.employee_id and g.farm_id = new.farm_id and g.rate_per_hour is not null
                         and new.entry_date >= coalesce(g.rate_from, new.entry_date));
  return new;
end;
$$;
drop trigger if exists hours_group_rate on hours_entries;
create trigger hours_group_rate before insert or update of farm_id, employee_id, entry_date on hours_entries
  for each row execute function _hours_group_rate();

-- Not yet paid: after the worker's last payslip (never paid: their farm's
-- last pay run), as Payslips works it out. Paid hours are never changed.
drop table if exists _unpaid;
create temp table _unpaid as
select h.id, h.employee_id, h.farm_id, h.entry_date, h.special_rate
from hours_entries h join employees e on e.id = h.employee_id
where h.entry_date > coalesce((select max(p.period_end) from payslips p where p.employee_id = e.id),
                              (select max(p.period_end) from payslips p where p.farm_id = e.farm_id),
                              '1900-01-01');

-- Before the start date: back to the old tariff.
update hours_entries h set special_rate = null
from _unpaid u
join employees e on e.id = u.employee_id
join employee_groups g on g.id = e.current_group_id and g.rate_from is not null
where h.id = u.id and u.special_rate is not null and u.farm_id = g.farm_id and u.entry_date < g.rate_from;

-- From the start date: the group tariff.
update hours_entries h set special_rate = g.rate_per_hour
from _unpaid u
join employees e on e.id = u.employee_id
join employee_groups g on g.id = e.current_group_id and g.rate_per_hour is not null
where h.id = u.id and u.special_rate is null and u.farm_id = g.farm_id and u.entry_date >= coalesce(g.rate_from, u.entry_date);

-- Per group, hours at Limpopodraai not yet paid: from 19 Oct at R28.50,
-- before it at the old tariff.
select g.name as work_group, g.rate_per_hour as group_tariff, g.rate_from as tariff_from,
       coalesce(sum(h.hours) filter (where h.special_rate is not null), 0) as hours_at_group_tariff,
       coalesce(sum(h.hours) filter (where h.special_rate is null), 0) as hours_at_old_tariff
from employee_groups g
left join employees e on e.current_group_id = g.id
left join _unpaid u on u.employee_id = e.id and u.farm_id = g.farm_id
left join hours_entries h on h.id = u.id
where g.rate_per_hour is not null
group by g.name, g.rate_per_hour, g.rate_from
order by g.name;
