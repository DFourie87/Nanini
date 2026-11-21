@echo off
REM Runs the sales report importer unattended (e.g. via Windows Task Scheduler)
REM against the client folder's BTW subfolders (where the market-agent account
REM sales are kept, one per year), so new invoices dropped in any year's BTW
REM folder get picked up automatically. PDFs already dealt with are skipped
REM (see scripts\import_seen.json), so this is cheap to run repeatedly.

cd /d C:\Claude
REM The office PC runs Python with "py" (the "python" command may only open the Store).
set PY=python
where py >nul 2>&1 && set PY=py
echo. >> scripts\import_log.txt
echo ===== Run at %date% %time% ===== >> scripts\import_log.txt
REM First fetch account sales that arrived by email (Gmail) into the BTW
REM folders, so the import below picks them up the same day.
%PY% scripts\fetch_gmail_invoices.py "D:\Kliente\Nanini 121 BK" >> scripts\import_log.txt 2>&1
%PY% scripts\import_sales_report.py "D:\Kliente\Nanini 121 BK" --yes --only-folder BTW >> scripts\import_log.txt 2>&1
REM The agents' payment summaries (afrekeningstate) go on their customer
REM accounts in Sales: which account sales each payment paid.
%PY% scripts\import_market_payments.py "D:\Kliente\Nanini 121 BK" >> scripts\import_log.txt 2>&1

REM Supplier invoices and statements that arrived by email go to the hub's
REM Suppliers app as "From email -- to check" (Gmail is only read).
echo. >> scripts\supplier_docs_log.txt
echo ===== Run at %date% %time% ===== >> scripts\supplier_docs_log.txt
%PY% scripts\fetch_supplier_docs.py >> scripts\supplier_docs_log.txt 2>&1

REM Payments to suppliers from the ABSA bank CSVs saved in the client folder
REM (any year's folder) go to the Suppliers app; ones already there are skipped.
echo. >> scripts\bank_payments_log.txt
echo ===== Run at %date% %time% ===== >> scripts\bank_payments_log.txt
%PY% scripts\import_bank_payments.py "D:\Kliente\Nanini 121 BK" >> scripts\bank_payments_log.txt 2>&1

REM ABSA's term loan statements (PDF) saved in any year's Bank\Term Loan
REM folder go to the hub's Financials > Term loan; ones already there are skipped.
echo. >> scripts\term_loan_log.txt
echo ===== Run at %date% %time% ===== >> scripts\term_loan_log.txt
%PY% scripts\import_term_loan.py "D:\Kliente\Nanini 121 BK" >> scripts\term_loan_log.txt 2>&1

REM ABSA's credit card and fleet card statements (PDF) saved in any year's
REM Bank\Credit card and Bank\Fleet Card folders go to the hub's Financials.
echo. >> scripts\cards_log.txt
echo ===== Run at %date% %time% ===== >> scripts\cards_log.txt
%PY% scripts\import_card_statements.py "D:\Kliente\Nanini 121 BK" >> scripts\cards_log.txt 2>&1

REM Fetches the latest CEF daily fuel price bulletin and updates the diesel
REM price forecast shown in the app's Reports tab.
echo. >> scripts\diesel_price_log.txt
echo ===== Run at %date% %time% ===== >> scripts\diesel_price_log.txt
%PY% scripts\fetch_diesel_price_forecast.py >> scripts\diesel_price_log.txt 2>&1
