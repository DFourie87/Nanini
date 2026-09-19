-- ============================================================================
-- Nanini App — diesel vehicle unit (hours vs kilometers)
-- ============================================================================
-- Run this ONCE in the Supabase SQL editor. Safe to re-run.
--
-- Each vehicle/equipment now records whether it's logged in hours (tractors,
-- pumps, other equipment) or kilometers (trucks, bakkies, other road
-- vehicles), set once when the vehicle is added or edited. Usage entries
-- copy the unit that was current for the vehicle at the time, so historical
-- entries keep their original unit even if it's changed later. Both the web
-- app (Nanini App/diesel/index.html) and the Flutter app read/write this.
-- ============================================================================

alter table diesel_vehicles
  add column if not exists unit text not null default 'hours' check (unit in ('hours', 'km'));

alter table diesel_usage
  add column if not exists hour_km_unit text not null default 'hours' check (hour_km_unit in ('hours', 'km'));
