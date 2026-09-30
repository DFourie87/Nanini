-- Work groups from the capture phones (run once in the Supabase SQL editor;
-- safe to re-run). Hours > WORK GROUPS on a phone sends who is in which
-- work group (capture_entries.module 'work_groups'), approved in the hub's
-- Employees inbox.
alter table capture_entries drop constraint if exists capture_entries_module_check;
alter table capture_entries add constraint capture_entries_module_check
  check (module in ('diesel_usage', 'diesel_purchase', 'hours', 'kg', 'tuckshop', 'delivery', 'employee', 'pay_check', 'work_groups'));
