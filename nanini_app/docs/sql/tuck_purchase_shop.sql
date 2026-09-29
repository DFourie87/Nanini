-- Tuck shop purchases: which shop they were bought at (run once in the
-- Supabase SQL editor; safe to re-run).
--
-- Items sold per item (the Limpopodraai shop) were saved without their shop,
-- so Payslips on the phones counted them at the worker's own farm -- a
-- Haaskraal worker's Limpopodraai purchases looked like Haaskraal debt. New
-- sales now save it; this fills it in for the ones already saved: the item's
-- shop, else Limpopodraai (Haaskraal's shop is a money total, always saved
-- with its farm).
alter table tuckshop_purchases add column if not exists farm_id uuid;

update tuckshop_purchases p
set farm_id = coalesce(
  (select (to_jsonb(i) ->> 'farm_id')::uuid from tuckshop_items i where i.id = p.item_id),
  (select f.id from farms f where f.name ilike '%limpopodraai%' limit 1))
where p.farm_id is null
  and p.item_id is not null;
