-- Delivery notes: an extra line under the agent's name on the printed note
-- (optional, typed in the Approve window). Run once in the Supabase SQL
-- editor; safe to re-run.
alter table delivery_notes add column if not exists agent_extra text;

select 'delivery_notes.agent_extra ready' as result;
