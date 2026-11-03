-- Members of Nanini 121 CC: their residential address and the Eskom account
-- at it, for their proof of address letters (Employees > List > Members >
-- Proof of address: the account's latest bill, not older than 3 months, is
-- attached). Run once in the Supabase SQL editor; safe to re-run. Members'
-- rows are admins only (members_private.sql).
alter table employees add column if not exists residential_address text;
alter table employees add column if not exists utility_account text;

select 'employees.residential_address and utility_account ready' as result;
