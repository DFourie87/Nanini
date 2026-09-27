@echo off
REM Runs the sales report importer unattended (e.g. via Windows Task Scheduler)
REM against the client folder's BTW subfolders (where the market-agent account
REM sales are kept, one per year), so new invoices dropped in any year's BTW
REM folder get picked up automatically. PDFs already dealt with are skipped
REM (see scripts\import_seen.json), so this is cheap to run repeatedly.

cd /d C:\Claude
echo. >> scripts\import_log.txt
echo ===== Run at %date% %time% ===== >> scripts\import_log.txt
python scripts\import_sales_report.py "D:\Kliente\Nanini 121 BK" --yes --only-folder BTW >> scripts\import_log.txt 2>&1

REM Fetches the latest CEF daily fuel price bulletin and updates the diesel
REM price forecast shown in the app's Reports tab.
echo. >> scripts\diesel_price_log.txt
echo ===== Run at %date% %time% ===== >> scripts\diesel_price_log.txt
python scripts\fetch_diesel_price_forecast.py >> scripts\diesel_price_log.txt 2>&1
