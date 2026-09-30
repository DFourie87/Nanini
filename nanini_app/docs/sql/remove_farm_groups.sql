-- Work groups: Doornbult and Haaskraal clock hours for everyone at the farm
-- (no groups); Limpopodraai keeps its groups except "Members". The workers
-- stay, they are only taken out of these groups (as the hub's delete does).

update employees set current_group_id = null
 where current_group_id in (
   select g.id from employee_groups g join farms f on f.id = g.farm_id
    where f.name ilike '%doornbult%' or f.name ilike '%haaskraal%'
       or (f.name ilike '%limpopodraai%' and trim(g.name) ilike 'members'));

delete from employee_groups g using farms f
 where f.id = g.farm_id
   and (f.name ilike '%doornbult%' or f.name ilike '%haaskraal%'
        or (f.name ilike '%limpopodraai%' and trim(g.name) ilike 'members'));

-- What's left:
select f.name farm, g.name "group" from employee_groups g left join farms f on f.id = g.farm_id order by 1, 2;
