-- Sales: boxes/bags/kg on imported market reports (run once in the Supabase
-- SQL editor; safe to re-run).
--
-- The office PC's importer used to write each line's quantity only into its
-- description ("5kg: 120 boxes @ R85.00/boxes"), so the Sales summary had no
-- box counts for imported reports. From now on it saves qty (and a pepper's
-- 5kg/4kg as its class); this fills both in for reports already imported,
-- read from those descriptions. Lines typed in the app are left alone.

alter table sales_line_items add column if not exists qty numeric;

update sales_line_items
set qty = replace(substring(description from '([0-9][0-9,]*(?:\.[0-9]+)?) (?:boxes|bags|kg|units) @'), ',', '')::numeric
where qty is null
  and description ~ '[0-9][0-9,]*(\.[0-9]+)? (boxes|bags|kg|units) @';

-- Pepper box size: "5kg: ..." (RSA) or "L: ..." / "M: ..." (Wenpro & co).
update sales_line_items
set class = case substring(description from '^(5kg|4kg|L|M): ')
              when 'L' then '5kg' when 'M' then '4kg'
              else substring(description from '^(5kg|4kg): ') end
where category = 'peppers'
  and class is null
  and description ~ '^(5kg|4kg|L|M): ';
