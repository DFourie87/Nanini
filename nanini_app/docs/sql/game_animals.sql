-- Buffalo app > Bloodline: the herd register and the mating guide (run once
-- in the Supabase SQL editor; safe to re-run).
--
-- game_animals: one row per animal -- on the farm (ours, or kept here for
-- someone else) or an ancestor known only from the pedigrees -- with its
-- parents by tag, so the family tree walks back past animals never born here.
-- game_matings: per cow and bull, the calf's inbreeding (Wright's F, %) and
-- whether that mating is best, acceptable or to be avoided.

create table if not exists game_animals (
  id uuid primary key default gen_random_uuid(),
  species text not null default 'Buffalo',
  tag text not null,
  name text,
  -- 'F', 'M', or null (not known yet, e.g. a young calf).
  sex text check (sex in ('F', 'M')),
  -- A year ("2019") or a date ("2026-12-14").
  born text,
  -- Whose it is: 'Nanini', or the owner of an animal kept here (e.g. 'Eljuro').
  owner text,
  -- False: an ancestor from the pedigrees, never on the farm.
  on_farm boolean not null default true,
  -- 'alive', 'dead' or 'sold'.
  status text not null default 'alive' check (status in ('alive', 'dead', 'sold')),
  sire text,
  dam text,
  horns text,
  microchip text,
  notes text,
  created_at timestamptz not null default now(),
  unique (species, tag)
);

-- From the buffalo register: camp, measurements, breeding and records.
alter table game_animals add column if not exists camp text;
-- 'African', 'East African' or a cross.
alter table game_animals add column if not exists subspecies text;
alter table game_animals add column if not exists bloodline text;
-- "75.75 (61.75 + 7 + 7)": tip to tip + boss L + boss R.
alter table game_animals add column if not exists sci text;
-- When the horns were last measured (yyyy-MM-dd).
alter table game_animals add column if not exists measured text;
alter table game_animals add column if not exists in_calf_to text;
-- Where it came from (auction, lot) or "Bred on farm".
alter table game_animals add column if not exists source text;
alter table game_animals add column if not exists dna text;

create table if not exists game_matings (
  species text not null default 'Buffalo',
  cow_tag text not null,
  bull_tag text not null,
  -- The calf's inbreeding coefficient, %.
  calf_inbreeding numeric not null,
  advice text not null check (advice in ('best', 'acceptable', 'avoid')),
  -- Ancestors the cow and bull share.
  shared text,
  note text,
  primary key (species, cow_tag, bull_tag)
);

-- Same rule as every other table: logged-in Nanini users only.
do $$
declare
  t text;
begin
  foreach t in array array['game_animals', 'game_matings'] loop
    execute format('alter table %I enable row level security', t);
    execute format('drop policy if exists "Nanini users" on %I', t);
    execute format('create policy "Nanini users" on %I for all to authenticated using (public.is_app_user()) with check (public.is_app_user())', t);
    if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = t) then
      execute format('alter publication supabase_realtime add table %I', t);
    end if;
  end loop;
end $$;
