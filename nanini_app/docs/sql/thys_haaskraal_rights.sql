-- Thys Fourie: manage the Haaskraal tuck shop and run the Haaskraal payroll
-- (plus the Tuck Shop and Employees tiles he needs for that). The same can
-- be ticked in the hub: Manage users > Thys > Extra rights.
update app_users
   set modules = array(select distinct unnest(modules || array['tuckshop', 'hours', 'tuckshop:haaskraal', 'payroll:haaskraal']))
 where role <> 'admin' and (display_name ilike '%thys%' or username ilike '%thys%');

select username, display_name, role, modules from app_users where display_name ilike '%thys%' or username ilike '%thys%';
