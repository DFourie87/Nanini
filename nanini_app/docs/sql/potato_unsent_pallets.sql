-- Sales > Summary, potatoes (run once in the Supabase SQL editor; safe to re-run).
-- Pallets packed from a field but not sent to market (no market for the
-- size, or the week's last truck was full). They count in the bags
-- harvested per field only, never in sales or average prices.

create table if not exists potato_unsent_pallets (
  id uuid primary key default gen_random_uuid(),
  packed_date date not null,
  field text not null,
  -- Pallet size key (as on a delivery note, e.g. "med7") -> full pallets.
  pallets jsonb not null default '{}',
  -- Pallet size key -> loose bags (a part pallet).
  bags jsonb not null default '{}',
  reason text,
  note text,
  created_at timestamptz not null default now()
);
create index if not exists potato_unsent_pallets_date_idx on potato_unsent_pallets (packed_date);

-- Same rule as every other table: logged-in Nanini users only.
alter table potato_unsent_pallets enable row level security;
drop policy if exists "Nanini users" on potato_unsent_pallets;
create policy "Nanini users" on potato_unsent_pallets for all to authenticated using (public.is_app_user()) with check (public.is_app_user());

-- How many potato account sales can be put on a field: through the
-- delivery note on the agent's payment summary.
select count(*) as potato_account_sales,
       count(*) filter (where n.field is not null) as on_a_field,
       count(*) filter (where pl.report_number is null) as not_paid_yet
from sales_reports r
left join customers c on c.agent = r.agent
left join lateral (
  select l.report_number, l.delivery_note
  from customer_payment_lines l join customer_payments p on p.id = l.payment_id
  where p.customer_id = c.id and l.report_number = regexp_replace(r.report_number, '\s*\(.*\)$', '')
  limit 1
) pl on true
left join delivery_notes n on pl.delivery_note ~ '^\s*\d+\s*$' and n.note_number = btrim(pl.delivery_note)::int
  and n.produce_type = 'potato' and n.status = 'approved'
where r.category = 'potatoes' and r.report_date >= '2026-01-01';
