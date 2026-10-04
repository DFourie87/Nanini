-- One supplier per name. A supplier added twice (Save tapped twice while
-- loading) is merged into the first one: anything already added to the
-- second (documents, payments, allocation rules) moves to the first, then
-- the second is removed. After that the database refuses a second supplier
-- with the same name (capitals and spaces at the ends ignored).
-- Safe to re-run.

drop table if exists supplier_dupes;
create temporary table supplier_dupes as
select s.id as dupe_id, k.id as keep_id
from suppliers s
join lateral (
  select k.id from suppliers k
  where lower(btrim(k.name)) = lower(btrim(s.name))
  order by k.created_at, k.id
  limit 1
) k on k.id <> s.id;

update supplier_docs d set supplier_id = x.keep_id from supplier_dupes x where d.supplier_id = x.dupe_id;
update supplier_payments p set supplier_id = x.keep_id from supplier_dupes x where p.supplier_id = x.dupe_id;
delete from supplier_gl_rules r using supplier_dupes x
  where r.supplier_id = x.dupe_id
    and exists (select 1 from supplier_gl_rules k where k.supplier_id = x.keep_id and k.item = r.item);
update supplier_gl_rules r set supplier_id = x.keep_id from supplier_dupes x where r.supplier_id = x.dupe_id;

delete from suppliers s using supplier_dupes x where s.id = x.dupe_id;

create unique index if not exists suppliers_name_unique on suppliers (lower(btrim(name)));
drop table if exists supplier_dupes;

-- The Agrico left (one line).
select name, created_at from suppliers where name ilike 'agrico%';
