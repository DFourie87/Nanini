-- Optional, after potato_group_tariff.sql: hours the potato field and
-- packhouse workers already have at Limpopodraai that are not yet on a
-- payslip are paid at the group tariff (R28.50) too. Hours already paid
-- stay as they were. Safe to re-run (only changes hours not yet at it).

update hours_entries h
set special_rate = g.rate_per_hour
from employees e
join employee_groups g on g.id = e.current_group_id and g.rate_per_hour is not null
where h.employee_id = e.id
  and h.farm_id = g.farm_id
  and h.special_rate is null
  -- Not yet paid: after the worker's last payslip (never paid: their farm's last pay run), as Payslips works it out.
  and h.entry_date > coalesce((select max(p.period_end) from payslips p where p.employee_id = e.id),
                              (select max(p.period_end) from payslips p where p.farm_id = e.farm_id),
                              '1900-01-01');

-- Per group: the hours now at the group tariff, not yet paid.
select g.name as work_group, g.rate_per_hour as group_tariff,
       count(h.id) as days_at_group_tariff, coalesce(sum(h.hours), 0) as hours_at_group_tariff
from employee_groups g
left join employees e on e.current_group_id = g.id
left join hours_entries h on h.employee_id = e.id and h.farm_id = g.farm_id and h.special_rate is not null
  and h.entry_date > coalesce((select max(p.period_end) from payslips p where p.employee_id = e.id),
                              (select max(p.period_end) from payslips p where p.farm_id = e.farm_id),
                              '1900-01-01')
where g.rate_per_hour is not null
group by g.name, g.rate_per_hour
order by g.name;
