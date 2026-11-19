-- Account sales: our delivery note (the agent's REFNO / Green Network's "Your
-- Reference"), so import_sales_report.py can match a Grow Boland account sale
-- with Green Network's own invoice for the same load. Safe to re-run.
alter table sales_reports add column if not exists delivery_note text;
