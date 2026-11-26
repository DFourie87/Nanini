-- A payroll run saves all payslips in one go: a worker without an extra
-- deduction, extra pay or bank fee then comes in with that field empty when
-- another worker in the run has one. Empty amounts become 0 (no lines: []).
-- Safe to re-run.
create or replace function _payslip_blanks() returns trigger language plpgsql as $$
declare j jsonb := to_jsonb(new);
begin
  if j ? 'extra_deductions' and jsonb_typeof(j->'extra_deductions') = 'null' then j := j || '{"extra_deductions": 0}'; end if;
  if j ? 'deduction_lines'  and jsonb_typeof(j->'deduction_lines')  = 'null' then j := j || '{"deduction_lines": []}'; end if;
  if j ? 'extra_pay'        and jsonb_typeof(j->'extra_pay')        = 'null' then j := j || '{"extra_pay": 0}'; end if;
  if j ? 'bank_fee'         and jsonb_typeof(j->'bank_fee')         = 'null' then j := j || '{"bank_fee": 0}'; end if;
  new := jsonb_populate_record(new, j);
  return new;
end $$;

drop trigger if exists payslip_blanks on payslips;
create trigger payslip_blanks before insert on payslips for each row execute function _payslip_blanks();

select 'payslip_blanks trigger on' as done,
       (select string_agg(column_name || case when is_nullable = 'NO' then ' (required)' else '' end, ', ' order by column_name)
          from information_schema.columns where table_name = 'payslips' and table_schema = 'public'
           and column_name in ('extra_deductions', 'deduction_lines', 'extra_pay', 'bank_fee')) as columns;
