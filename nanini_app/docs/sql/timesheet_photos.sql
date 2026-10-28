-- Nanini Capture > TIMESHEET: a photo of each page of a filled-in printed
-- timesheet, sent from a phone with the Hours task. The office PC
-- (scripts/read_timesheets.py) reads the handwriting into the entry, and
-- someone checks it in the hub (Employees > Captured) before approving: only
-- then do the hours go in (calendar, Summary, payroll).
-- Needs suppliers_capture.sql (capture_photos). Safe to re-run.

alter table capture_entries drop constraint if exists capture_entries_module_check;
alter table capture_entries add constraint capture_entries_module_check
  check (module in ('diesel_usage', 'diesel_purchase', 'hours', 'kg', 'tuckshop', 'delivery', 'employee', 'pay_check',
                    'work_groups', 'supplier_doc', 'timesheet'));
