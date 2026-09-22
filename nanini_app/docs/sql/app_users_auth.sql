-- ============================================================================
-- Nanini App — login gateway (username + PIN)
-- ============================================================================
-- Run this ONCE in the Supabase SQL editor (Dashboard → SQL Editor → New query
-- → paste this whole file → Run). It is safe to re-run (uses IF NOT EXISTS /
-- CREATE OR REPLACE throughout).
--
-- Design: PINs are never stored in plain text and never leave the database.
-- The `app_users` table itself is locked down (RLS denies all direct access
-- from the app's client key) — every operation goes through a SECURITY
-- DEFINER function below that hashes/verifies server-side and returns only
-- the fields the app actually needs (never the pin hash). This is safe to
-- call with the same publishable/anon key the rest of the app already uses.
-- ============================================================================

-- Supabase installs extensions into the `extensions` schema by default, not
-- `public` — so every SECURITY DEFINER function below sets its search_path
-- to include both, or `crypt`/`gen_salt` won't resolve.
create extension if not exists pgcrypto with schema extensions;

create table if not exists app_users (
  id uuid primary key default gen_random_uuid(),
  username text not null unique,
  display_name text not null,
  pin_hash text not null,
  role text not null default 'staff' check (role in ('admin', 'staff')),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Which hub tiles ('diesel', 'sales', ...) a staff account can see -- an
-- admin account always sees everything regardless of this list, so it's
-- only meaningful for 'staff'. See lib/core/auth/app_modules.dart for the
-- key list the app matches this against.
alter table app_users add column if not exists modules text[] not null default '{}';

alter table app_users enable row level security;

-- No policies are created for anon/authenticated roles on purpose — this
-- blocks ALL direct select/insert/update/delete from the app. Everything
-- below goes through SECURITY DEFINER functions instead, which run with the
-- table owner's privileges regardless of RLS.

-- ---------------------------------------------------------------------------
-- login(username, pin) -> the user's id/display_name/role/modules if the PIN
-- matches an active account, otherwise no rows.
-- ---------------------------------------------------------------------------
-- Return columns changed (added modules) -- CREATE OR REPLACE can't change
-- a function's return shape, so drop first. Safe to re-run.
drop function if exists login(text, text);

create or replace function login(p_username text, p_pin text)
returns table (id uuid, username text, display_name text, role text, modules text[])
language sql
security definer
set search_path = public, extensions
as $$
  select u.id, u.username, u.display_name, u.role, u.modules
  from app_users u
  where u.username = lower(trim(p_username))
    and u.active
    and u.pin_hash = crypt(p_pin, u.pin_hash);
$$;

-- ---------------------------------------------------------------------------
-- create_app_user(...) — only succeeds if the calling admin's own
-- username+pin check out and their role is 'admin'. Returns the new user's
-- id, or raises an exception (visible to the app as an error) otherwise.
-- ---------------------------------------------------------------------------
-- Parameter list changed (added p_modules) -- that's a different signature
-- as far as Postgres is concerned, so CREATE OR REPLACE would add a second
-- overload instead of replacing this one. Drop the old signature first.
-- Safe to re-run.
drop function if exists create_app_user(text, text, text, text, text, text);

create or replace function create_app_user(
  p_admin_username text,
  p_admin_pin text,
  p_new_username text,
  p_display_name text,
  p_new_pin text,
  p_role text default 'staff',
  p_modules text[] default '{}'
)
returns uuid
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin_ok boolean;
  v_new_id uuid;
begin
  select exists(
    select 1 from app_users
    where username = lower(trim(p_admin_username))
      and active
      and role = 'admin'
      and pin_hash = crypt(p_admin_pin, pin_hash)
  ) into v_admin_ok;

  if not v_admin_ok then
    raise exception 'Not authorized';
  end if;

  if p_role not in ('admin', 'staff') then
    raise exception 'Invalid role';
  end if;

  insert into app_users (username, display_name, pin_hash, role, modules)
  values (lower(trim(p_new_username)), trim(p_display_name), crypt(p_new_pin, gen_salt('bf')), p_role, p_modules)
  returning id into v_new_id;

  return v_new_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- list_app_users(...) — admin-only directory (no pin hashes returned).
-- ---------------------------------------------------------------------------
-- Return columns changed (added modules) -- drop first, see login() above.
drop function if exists list_app_users(text, text);

create or replace function list_app_users(p_admin_username text, p_admin_pin text)
returns table (id uuid, username text, display_name text, role text, modules text[], active boolean, created_at timestamptz)
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin_ok boolean;
begin
  select exists(
    select 1 from app_users
    where username = lower(trim(p_admin_username))
      and active and role = 'admin'
      and pin_hash = crypt(p_admin_pin, pin_hash)
  ) into v_admin_ok;

  if not v_admin_ok then
    raise exception 'Not authorized';
  end if;

  return query
    select u.id, u.username, u.display_name, u.role, u.modules, u.active, u.created_at
    from app_users u
    order by u.display_name;
end;
$$;

-- ---------------------------------------------------------------------------
-- update_app_user_access(...) — admin-only: change an existing user's role
-- and/or which hub tiles ('modules') a staff account can see.
-- ---------------------------------------------------------------------------
create or replace function update_app_user_access(
  p_admin_username text, p_admin_pin text, p_target_id uuid, p_role text, p_modules text[]
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin_ok boolean;
begin
  select exists(
    select 1 from app_users
    where username = lower(trim(p_admin_username))
      and active and role = 'admin'
      and pin_hash = crypt(p_admin_pin, pin_hash)
  ) into v_admin_ok;

  if not v_admin_ok then
    raise exception 'Not authorized';
  end if;

  if p_role not in ('admin', 'staff') then
    raise exception 'Invalid role';
  end if;

  update app_users set role = p_role, modules = p_modules where id = p_target_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- set_app_user_active(...) — admin-only enable/disable a login.
-- ---------------------------------------------------------------------------
create or replace function set_app_user_active(
  p_admin_username text, p_admin_pin text, p_target_id uuid, p_active boolean
)
returns void
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_admin_ok boolean;
begin
  select exists(
    select 1 from app_users
    where username = lower(trim(p_admin_username))
      and active and role = 'admin'
      and pin_hash = crypt(p_admin_pin, pin_hash)
  ) into v_admin_ok;

  if not v_admin_ok then
    raise exception 'Not authorized';
  end if;

  update app_users set active = p_active where id = p_target_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- change_own_pin(...) — any logged-in user can change their own PIN.
-- ---------------------------------------------------------------------------
create or replace function change_own_pin(p_username text, p_old_pin text, p_new_pin text)
returns boolean
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_ok boolean;
begin
  select exists(
    select 1 from app_users
    where username = lower(trim(p_username))
      and active
      and pin_hash = crypt(p_old_pin, pin_hash)
  ) into v_ok;

  if not v_ok then
    return false;
  end if;

  update app_users
  set pin_hash = crypt(p_new_pin, gen_salt('bf'))
  where username = lower(trim(p_username));

  return true;
end;
$$;

-- Let the app's client key (anon/authenticated) call these functions —
-- the functions themselves enforce who's allowed to do what.
grant execute on function login(text, text) to anon, authenticated;
grant execute on function create_app_user(text, text, text, text, text, text, text[]) to anon, authenticated;
grant execute on function list_app_users(text, text) to anon, authenticated;
grant execute on function set_app_user_active(text, text, uuid, boolean) to anon, authenticated;
grant execute on function update_app_user_access(text, text, uuid, text, text[]) to anon, authenticated;
grant execute on function change_own_pin(text, text, text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Seed one initial admin so you can log in and create everyone else.
-- Username: admin   PIN: 1234
-- CHANGE THIS PIN IMMEDIATELY after your first login (Hub → Manage users, or
-- ask the app for a "change my PIN" option) — everyone reading this file
-- knows the starting PIN.
-- ---------------------------------------------------------------------------
insert into app_users (username, display_name, pin_hash, role)
values ('admin', 'Admin', crypt('1234', gen_salt('bf')), 'admin')
on conflict (username) do nothing;
