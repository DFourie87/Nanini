@echo off
REM Runs the sales report importer unattended (e.g. via Windows Task Scheduler)
REM against the whole client folder, so new invoices dropped in any year's
REM subfolder get picked up automatically. Already-imported reports are
REM skipped instantly, so this is cheap to run repeatedly.

cd /d C:\Claude
echo. >> scripts\import_log.txt
echo ===== Run at %date% %time% ===== >> scripts\import_log.txt
python scripts\import_sales_report.py "D:\Kliente\Nanini 121 BK" --yes >> scripts\import_log.txt 2>&1
