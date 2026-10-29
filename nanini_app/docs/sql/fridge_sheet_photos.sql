-- Nanini Capture > FRIDGE SHEET: a photo of each page of a filled-in fridge
-- sheet (wors, chicken pieces), read on the phone (its QR code and the marks)
-- and sent from a phone with the Tuck shop task. Someone checks the counts in
-- the hub (Tuck shop > Captured) before approving: only then do they go on
-- the workers' tuck shop accounts (and off the stock).
-- Needs timesheet_photos.sql. Safe to re-run.

alter table capture_entries drop constraint if exists capture_entries_module_check;
alter table capture_entries add constraint capture_entries_module_check
  check (module in ('diesel_usage', 'diesel_purchase', 'hours', 'kg', 'tuckshop', 'delivery', 'employee', 'pay_check',
                    'work_groups', 'supplier_doc', 'timesheet', 'fridge_sheet'));
