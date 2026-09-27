-- ============================================================================
-- Nanini App — lockdown STEP 2 of 2: only logged-in Nanini users get data
-- ============================================================================
-- Run this ONLY after:
--   1. lockdown_1_accounts.sql has been run,
--   2. every hub phone has the new Nanini app and has logged in with it
--      (older app versions stop working the moment this runs), and
--   3. the office PC's sales importer has the secret key set up
--      (see scripts/README.md) -- otherwise its daily import fails.
-- Safe to re-run.
--
-- After this, the app key built into the apps opens nothing by itself:
--  * every table needs a logged-in, active Nanini user (app_users);
--  * Nanini Capture phones only get the capture_* functions from step 1;
--  * the diesel price forecast (public fuel-price data) stays writable by
--    the office PC's daily fetch script without a secret key.
-- ============================================================================

do $$
declare
  t record;
  p record;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t.tablename);
    for p in select policyname from pg_policies where schemaname = 'public' and tablename = t.tablename loop
      execute format('drop policy %I on public.%I', p.policyname, t.tablename);
    end loop;
    -- app_users gets no policy at all: it's only reachable through the
    -- functions in step 1.
    if t.tablename <> 'app_users' then
      execute format(
        'create policy "Nanini users" on public.%I for all to authenticated using (public.is_app_user()) with check (public.is_app_user())',
        t.tablename
      );
    end if;
  end loop;
end $$;

-- Public fuel-price data, written daily by scripts/fetch_diesel_price_forecast.py.
create policy "Fuel price script read" on diesel_price_forecast for select to anon using (true);
create policy "Fuel price script insert" on diesel_price_forecast for insert to anon with check (id = 1);
create policy "Fuel price script update" on diesel_price_forecast for update to anon using (id = 1) with check (id = 1);

-- The old PIN-checking functions (used by app versions before the lockdown).
drop function if exists login(text, text);
drop function if exists create_app_user(text, text, text, text, text, text, text[]);
drop function if exists list_app_users(text, text);
drop function if exists set_app_user_active(text, text, uuid, boolean);
drop function if exists update_app_user_access(text, text, uuid, text, text[]);
drop function if exists change_own_pin(text, text, text);
