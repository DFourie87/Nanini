-- ============================================================================
-- Nanini App — lockdown STEP 1 of 2: real logins + capture-phone functions
-- ============================================================================
-- Run this in the Supabase SQL editor. Safe to re-run. It only ADDS things:
-- the current apps keep working after it. Run STEP 2
-- (lockdown_2_policies.sql) only once everyone has the new hub app and has
-- logged in with it.
--
-- What this does:
--  * Gives every Nanini user (app_users) a real Supabase Auth account, so the
--    database itself knows who is asking. Existing PINs carry over unchanged
--    (same bcrypt hash); the app asks anyone with a PIN shorter than 6 digits
--    to choose a 6-digit one at their next login.
--  * Replaces the PIN-checking admin functions with ones that check the
--    logged-in user instead.
--  * Adds the only doors the Nanini Capture phones get: register, download
--    the pick-lists (no ID numbers, bank details or pay), send entries, and
--    read back their own entries' status. New phones must be approved in the
--    hub (Capture phones) before they can do anything.
-- ============================================================================

create extension if not exists pgcrypto with schema extensions;

-- Which hub apps a staff account can see (missing on databases set up with
-- an early version of app_users_auth.sql).
alter table app_users add column if not exists modules text[] not null default '{}';
alter table app_users add column if not exists auth_id uuid unique references auth.users (id) on delete set null;

-- The login email behind each username. Never shown to anyone; the app
-- still asks for a username + PIN.
create or replace function app_user_email(p_username text) returns text
language sql immutable as $$ select lower(trim(p_username)) || '@users.nanini.app' $$;

-- Creates (or finds) the Auth account for an email, with an already-hashed
-- password. Internal only -- not callable from the apps.
create or replace function _nanini_auth_account(p_email text, p_hash text) returns uuid
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_id uuid;
begin
  select id into v_id from auth.users where email = p_email;
  if v_id is not null then
    return v_id;
  end if;
  v_id := gen_random_uuid();
  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    email_change_token_current, phone_change, phone_change_token, reauthentication_token
  ) values (
    '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated', p_email, p_hash, now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now(),
    '', '', '', '', '', '', '', ''
  );
  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  values (
    gen_random_uuid(), v_id, v_id::text,
    jsonb_build_object('sub', v_id::text, 'email', p_email, 'email_verified', true),
    'email', now(), now(), now()
  );
  return v_id;
end;
$$;
revoke all on function _nanini_auth_account(text, text) from public, anon, authenticated;

-- Existing users: create their Auth accounts with their current PIN.
do $$
declare
  u record;
begin
  for u in select id, username, pin_hash from app_users where auth_id is null loop
    update app_users set auth_id = _nanini_auth_account(app_user_email(u.username), u.pin_hash) where id = u.id;
  end loop;
end $$;

-- Who is asking? (used by every table policy in step 2)
create or replace function is_app_user() returns boolean
language sql stable security definer set search_path = public
as $$ select exists (select 1 from app_users where auth_id = auth.uid() and active) $$;

create or replace function is_app_admin() returns boolean
language sql stable security definer set search_path = public
as $$ select exists (select 1 from app_users where auth_id = auth.uid() and active and role = 'admin') $$;

grant execute on function is_app_user() to authenticated;
grant execute on function is_app_admin() to authenticated;

-- The logged-in user's own profile.
drop function if exists my_app_user();
create or replace function my_app_user()
returns table (id uuid, username text, display_name text, role text, modules text[])
language sql stable security definer set search_path = public
as $$
  select u.id, u.username, u.display_name, u.role, u.modules
  from app_users u where u.auth_id = auth.uid() and u.active;
$$;
revoke all on function my_app_user() from public, anon;
grant execute on function my_app_user() to authenticated;

-- ---------------------------------------------------------------------------
-- Admin functions (Manage users). Each checks the caller is an active admin.
-- ---------------------------------------------------------------------------
create or replace function _nanini_require_admin() returns void
language plpgsql stable security definer set search_path = public
as $$
begin
  if not is_app_admin() then
    raise exception 'Only an admin can do this';
  end if;
end;
$$;

create or replace function _nanini_check_pin(p_pin text) returns void
language plpgsql immutable
as $$
begin
  if p_pin is null or p_pin !~ '^[0-9]{6,}$' then
    raise exception 'The PIN must be at least 6 digits';
  end if;
end;
$$;

drop function if exists admin_list_users();
create or replace function admin_list_users()
returns table (id uuid, username text, display_name text, role text, modules text[], active boolean, created_at timestamptz)
language plpgsql security definer set search_path = public
as $$
begin
  perform _nanini_require_admin();
  return query
    select u.id, u.username, u.display_name, u.role, u.modules, u.active, u.created_at
    from app_users u order by u.display_name;
end;
$$;

create or replace function admin_create_user(
  p_username text, p_display_name text, p_pin text, p_role text default 'staff', p_modules text[] default '{}'
) returns uuid
language plpgsql security definer set search_path = public, extensions
as $$
declare
  v_username text := lower(trim(p_username));
  v_hash text;
  v_id uuid;
begin
  perform _nanini_require_admin();
  perform _nanini_check_pin(p_pin);
  if v_username = '' or trim(p_display_name) = '' then
    raise exception 'Enter a username and display name';
  end if;
  if p_role not in ('admin', 'staff') then
    raise exception 'Invalid role';
  end if;
  if exists (select 1 from app_users where username = v_username) then
    raise exception 'That username is already taken';
  end if;
  v_hash := crypt(p_pin, gen_salt('bf', 10));
  insert into app_users (username, display_name, pin_hash, role, modules, auth_id)
  values (v_username, trim(p_display_name), v_hash, p_role, p_modules, _nanini_auth_account(app_user_email(v_username), v_hash))
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function admin_update_user_access(p_target_id uuid, p_role text, p_modules text[]) returns void
language plpgsql security definer set search_path = public
as $$
begin
  perform _nanini_require_admin();
  if p_role not in ('admin', 'staff') then
    raise exception 'Invalid role';
  end if;
  update app_users set role = p_role, modules = p_modules where id = p_target_id;
end;
$$;

create or replace function admin_set_user_active(p_target_id uuid, p_active boolean) returns void
language plpgsql security definer set search_path = public, auth
as $$
declare
  v_auth uuid;
begin
  perform _nanini_require_admin();
  update app_users set active = p_active where id = p_target_id returning auth_id into v_auth;
  -- A switched-off user can't even sign in.
  update auth.users set banned_until = case when p_active then null else 'infinity'::timestamptz end where id = v_auth;
end;
$$;

create or replace function admin_reset_pin(p_target_id uuid, p_pin text) returns void
language plpgsql security definer set search_path = public, auth, extensions
as $$
declare
  v_hash text;
  v_auth uuid;
begin
  perform _nanini_require_admin();
  perform _nanini_check_pin(p_pin);
  v_hash := crypt(p_pin, gen_salt('bf', 10));
  update app_users set pin_hash = v_hash where id = p_target_id returning auth_id into v_auth;
  update auth.users set encrypted_password = v_hash, updated_at = now() where id = v_auth;
end;
$$;

revoke all on function admin_list_users() from public, anon;
revoke all on function admin_create_user(text, text, text, text, text[]) from public, anon;
revoke all on function admin_update_user_access(uuid, text, text[]) from public, anon;
revoke all on function admin_set_user_active(uuid, boolean) from public, anon;
revoke all on function admin_reset_pin(uuid, text) from public, anon;
grant execute on function admin_list_users() to authenticated;
grant execute on function admin_create_user(text, text, text, text, text[]) to authenticated;
grant execute on function admin_update_user_access(uuid, text, text[]) to authenticated;
grant execute on function admin_set_user_active(uuid, boolean) to authenticated;
grant execute on function admin_reset_pin(uuid, text) to authenticated;

-- ---------------------------------------------------------------------------
-- Nanini Capture phones. A phone identifies itself by the random id it made
-- at setup. New phones wait for an admin to approve them in the hub.
-- ---------------------------------------------------------------------------
alter table capture_devices add column if not exists approved boolean not null default false;

create or replace function _capture_device_ok(p_device_id uuid) returns boolean
language sql stable security definer set search_path = public
as $$ select exists (select 1 from capture_devices where id = p_device_id and approved and active) $$;
revoke all on function _capture_device_ok(uuid) from public, anon, authenticated;

create or replace function capture_register(p_device_id uuid, p_name text, p_app_version text)
returns json
language plpgsql security definer set search_path = public
as $$
declare
  d capture_devices;
begin
  insert into capture_devices (id, name, approved)
  values (p_device_id, left(coalesce(nullif(trim(p_name), ''), 'Phone'), 80), false)
  on conflict (id) do nothing;
  update capture_devices set last_seen_at = now(), app_version = left(p_app_version, 40)
  where id = p_device_id returning * into d;
  return json_build_object('name', d.name, 'modules', d.modules, 'active', d.active, 'approved', d.approved);
end;
$$;

create or replace function capture_reference(p_device_id uuid)
returns json
language plpgsql stable security definer set search_path = public
as $$
begin
  if not _capture_device_ok(p_device_id) then
    raise exception 'This phone is not approved';
  end if;
  -- Columns are read through to_jsonb(row) so a database that's missing an
  -- optional column (added by a later migration) still returns the lists,
  -- just without that detail, instead of failing outright.
  return json_build_object(
    'farms', (select coalesce(json_agg(json_build_object('id', f.id, 'name', f.name) order by f.name), '[]') from farms f),
    'people', (select coalesce(json_agg(json_build_object(
                  'id', e.id,
                  'name', trim(coalesce(to_jsonb(e) ->> 'first_name', '') || ' ' || coalesce(to_jsonb(e) ->> 'last_name', '')),
                  'farm_id', to_jsonb(e) ->> 'farm_id',
                  'group_id', to_jsonb(e) ->> 'current_group_id') order by to_jsonb(e) ->> 'first_name'), '[]') from employees e),
    'groups', (select coalesce(json_agg(json_build_object('id', g.id, 'name', g.name, 'farm_id', to_jsonb(g) ->> 'farm_id') order by g.name), '[]')
               from employee_groups g),
    'tanks', (select coalesce(json_agg(json_build_object('id', t.id, 'name', t.name) order by t.name), '[]') from diesel_tanks t),
    'vehicles', (select coalesce(json_agg(json_build_object('id', v.id, 'name', v.name, 'unit', coalesce(to_jsonb(v) ->> 'unit', 'hours')) order by v.name), '[]')
                 from diesel_vehicles v),
    'activities', (select coalesce(json_agg(json_build_object('id', a.id, 'name', a.name)
                     order by coalesce((to_jsonb(a) ->> 'sort_order')::numeric, 0), a.name), '[]') from diesel_activities a),
    -- Sell price = latest batch's cost (or last cost) + profit %, rounded,
    -- the same as the Tuck Shop app.
    'shop_items', (select coalesce(json_agg(json_build_object(
                      'id', i.id, 'name', i.name, 'farm_id', to_jsonb(i) ->> 'farm_id',
                      'price', round(coalesce(
                                 (select b.cost_price from tuckshop_batches b where b.item_id = i.id
                                  order by to_jsonb(b) ->> 'batch_date' desc nulls last limit 1),
                                 (to_jsonb(i) ->> 'last_cost_price')::numeric, 0)
                               * (1 + coalesce((to_jsonb(i) ->> 'profit_pct')::numeric, 35) / 100)),
                      'stock', coalesce((select sum(b.qty) from tuckshop_batches b where b.item_id = i.id), 0)
                    ) order by i.name), '[]')
                  from tuckshop_items i where not coalesce((to_jsonb(i) ->> 'archived')::boolean, false))
  );
end;
$$;

-- p_entries: [{id, module, payload, summary, captured_at}, ...]. Already-sent
-- ids are ignored, so re-sending after a dropped connection is harmless.
create or replace function capture_submit(p_device_id uuid, p_entries jsonb)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  v_name text;
  v_count integer;
begin
  if not _capture_device_ok(p_device_id) then
    raise exception 'This phone is not approved';
  end if;
  select name into v_name from capture_devices where id = p_device_id;
  insert into capture_entries (id, device_id, device_name, module, payload, summary, captured_at, status)
  select (e ->> 'id')::uuid, p_device_id, v_name, e ->> 'module', e -> 'payload', left(e ->> 'summary', 300),
         (e ->> 'captured_at')::timestamptz, 'pending'
  from jsonb_array_elements(p_entries) e
  on conflict (id) do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function capture_statuses(p_device_id uuid, p_ids uuid[])
returns table (id uuid, status text, reject_reason text)
language sql stable security definer set search_path = public
as $$
  select c.id, c.status, c.reject_reason from capture_entries c
  where c.device_id = p_device_id and c.id = any (p_ids);
$$;

grant execute on function capture_register(uuid, text, text) to anon, authenticated;
grant execute on function capture_reference(uuid) to anon, authenticated;
grant execute on function capture_submit(uuid, jsonb) to anon, authenticated;
grant execute on function capture_statuses(uuid, uuid[]) to anon, authenticated;
