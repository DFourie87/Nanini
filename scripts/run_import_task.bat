@echo off
REM Runs the sales report importer unattended (e.g. via Windows Task Scheduler)
REM against the client folder's BTW subfolders (where the market-agent account
REM sales are kept, one per year), so new invoices dropped in any year's BTW
REM folder get picked up automatically. PDFs already dealt with are skipped
REM (see scripts\import_seen.json), so this is cheap to run repeatedly.

cd /d C:\Claude
echo. >> scripts\import_log.txt
echo ===== Run at %date% %time% ===== >> scripts\import_log.txt
REM First fetch account sales that arrived by email (Gmail) into the BTW
REM folders, so the import below picks them up the same day.
python scripts\fetch_gmail_invoices.py "D:\Kliente\Nanini 121 BK" >> scripts\import_log.txt 2>&1
python scripts\import_sales_report.py "D:\Kliente\Nanini 121 BK" --yes --only-folder BTW >> scripts\import_log.txt 2>&1

REM Fetches the latest CEF daily fuel price bulletin and updates the diesel
REM price forecast shown in the app's Reports tab.
echo. >> scripts\diesel_price_log.txt
echo ===== Run at %date% %time% ===== >> scripts\diesel_price_log.txt
python scripts\fetch_diesel_price_forecast.py >> scripts\diesel_price_log.txt 2>&1
