-- ============================================================================
-- Nanini App — "Nanini Capture" offline capturing app
-- ============================================================================
-- Run this ONCE in the Supabase SQL editor. Safe to re-run.
--
-- The capture app (a separate APK for farm workers' phones) saves entries on
-- the phone while offline and uploads them here when it's on Wi-Fi. Nothing
-- it sends touches the real Diesel / Packaging / Hours / Tuck shop tables
-- directly: every entry waits in capture_entries as 'pending' until a
-- manager approves it from the matching hub app, which then writes it into
-- the real tables exactly as if it had been captured in the hub.
-- ============================================================================

-- One row per phone. The phone itself is the "capturer" -- it's named once
-- at setup (e.g. "Diesel pump phone"). Admins can rename it, limit which
-- tasks it shows, or switch it off from the hub (profile menu > Capture
-- phones).
create table if not exists capture_devices (
  id uuid primary key,
  name text not null,
  modules text[] not null default '{diesel,packaging,hours,tuckshop}',
  active boolean not null default true,
  app_version text,
  last_seen_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists capture_entries (
  -- Generated on the phone, so re-sending the same entry after a dropped
  -- connection can never create a duplicate.
  id uuid primary key,
  device_id uuid not null references capture_devices(id) on delete cascade,
  device_name text,
  module text not null check (module in ('diesel_usage', 'diesel_purchase', 'hours', 'kg', 'tuckshop', 'delivery')),
  payload jsonb not null,
  summary text,
  captured_at timestamptz not null,
  synced_at timestamptz not null default now(),
  status text not null default 'pending' check (status in ('pending', 'approving', 'approved', 'rejected')),
  reviewed_at timestamptz,
  reviewed_by text,
  reject_reason text
);

create index if not exists capture_entries_status_module_idx on capture_entries (status, module);
create index if not exists capture_entries_device_idx on capture_entries (device_id, captured_at desc);

-- Live updates for the "Captured -- to approve" badge in the hub apps.
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'capture_entries'
  ) then
    alter publication supabase_realtime add table capture_entries;
  end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and tablename = 'capture_devices'
  ) then
    alter publication supabase_realtime add table capture_devices;
  end if;
end $$;

-- Same open-to-the-app-key access as the other tables the app uses.
alter table capture_devices enable row level security;
drop policy if exists "Allow read" on capture_devices;
create policy "Allow read" on capture_devices for select using (true);
drop policy if exists "Allow insert" on capture_devices;
create policy "Allow insert" on capture_devices for insert with check (true);
drop policy if exists "Allow update" on capture_devices;
create policy "Allow update" on capture_devices for update using (true);
drop policy if exists "Allow delete" on capture_devices;
create policy "Allow delete" on capture_devices for delete using (true);

alter table capture_entries enable row level security;
drop policy if exists "Allow read" on capture_entries;
create policy "Allow read" on capture_entries for select using (true);
drop policy if exists "Allow insert" on capture_entries;
create policy "Allow insert" on capture_entries for insert with check (true);
drop policy if exists "Allow update" on capture_entries;
create policy "Allow update" on capture_entries for update using (true);
