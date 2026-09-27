-- ============================================================================
-- Nanini App — tuck shop "remove item" (archived flag)
-- ============================================================================
-- Run once in the Supabase SQL editor. Safe to re-run.
--
-- Removing an item in Tuck Shop > Stock hides it (archived) instead of
-- deleting it, so sales already logged against it keep their item. Also used
-- by the capture app's pick-list (capture_reference) to leave removed items
-- out. Some databases were set up before this column existed.
-- ============================================================================

alter table tuckshop_items add column if not exists archived boolean not null default false;
