# Scripts

## fetch_diesel_price_forecast.py

Fetches CEF Group's daily "Basic Fuel Price" bulletin PDF and writes the
diesel 0.05% sulphur expected price change -- for the next 1st-Wednesday
price adjustment -- into Supabase, for the diesel module's Reports tab to
show live.

```
pip install pdfplumber requests
python3 scripts/fetch_diesel_price_forecast.py
```

Requires the `diesel_price_forecast` table (`nanini_app/docs/sql/diesel_price_forecast.sql`,
run once in the Supabase SQL editor). Runs automatically as part of
`run_import_task.bat`'s daily schedule; logs to `scripts/diesel_price_log.txt`.

## import_sales_report.py

Imports market agent account-sales PDFs straight into the Sales tables,
instead of typing them into the app by hand.

### Setup (once)

```
pip install pdfplumber requests
```

Since the database lockdown, the Sales tables only open with the project's
**secret key**, which must stay on this PC:

1. Supabase dashboard → Project Settings → API Keys → **Secret keys** →
   copy the key (starts with `sb_secret_`; on older projects use the
   `service_role` key instead).
2. Save it as a plain text file named `supabase_secret_key.txt` in this
   `scripts` folder (e.g. `C:\Claude\scripts\supabase_secret_key.txt`),
   containing only the key. Alternatively set the `SUPABASE_SECRET_KEY`
   environment variable.

That file is in `.gitignore` -- never commit it or send it to anyone: it
opens the whole database. The diesel price script above doesn't need it.

### Usage

```
python3 scripts/import_sales_report.py path/to/invoice.pdf
```

A single PDF can bundle several invoices (one per page) — each one found is
parsed and shown separately. For each report it prints what it parsed
(including a box-count/kg and average-price breakdown by size or grade) and
asks for confirmation before saving. Pass `--yes` to skip the confirmation
prompt for every report in the file.

Run it from your own computer — it won't work from a sandboxed environment
that blocks outbound network access to Supabase.

Delete a report by number (e.g. to fix one saved before a parser bug was
corrected, then re-import it):

```
python3 scripts/import_sales_report.py --delete-report 56186011
```

### Running it automatically (Windows Scheduled Task)

`run_import_task.bat` scans the whole client folder (not just the current
year) and logs to `scripts/import_log.txt`, so it can be dropped into
Windows Task Scheduler to pick up newly saved invoices with no manual
step. One-time setup, from an elevated Command Prompt:

```
schtasks /create /tn "Nanini Sales Import" /tr "C:\Claude\scripts\run_import_task.bat" /sc daily /st 07:00
```

This requires: the PC to be on and you logged in at that time, and the
external drive holding the client folder (`D:\Kliente\...`) to be
connected. Check `scripts\import_log.txt` any time to see what the last
few runs found.

### Currently supported market agents / layouts

- **RSA Markagente** (Interaction Market Services Tshwane) — peppers
- **Wenpro Markagente, CL de Villiers Markagente, Botha Roodt Johannesburg,
  Dapper Agencies** — these four share one underlying invoice template (in
  Afrikaans or English) — peppers, butternut, potatoes (size + Class 1/2)
- **Universal Leaf South Africa** (tobacco) — sub-grades like F2F/F2P/F4P
  are rolled up into their base grade (F1-F6, S1-S4), since that's all the
  app tracks. The kg delivered per grade is recorded in each line item's
  `description` field (the app doesn't have a dedicated quantity column).

Produce the app doesn't have a Sales category for (e.g. melons on a Dapper
invoice) is skipped with a warning rather than guessed at.

### Adding another agent

Send Claude a sample PDF from that agent, and ask it to add a parser
function plus a detection rule in `detect_and_parse()`, following the
existing patterns (`parse_rsa`, `parse_wenfam_page`, `parse_tobacco_ulsa`).

### Unknown product/grade codes

If an invoice uses a product code or tobacco grade the script doesn't
recognise, it stops with a clear error naming the code rather than
guessing — extend the relevant map (`RSA_PRODUCT_CODE_MAP`,
`POTATO_SIZE_MAP`, `BUTTERNUT_PACK_MAP`, `TOBACCO_BASE_GRADES`, etc.) with
the correct mapping.

### Safety check

Each parser cross-checks its parsed line-item total against the invoice's
own printed total; if they don't match (e.g. a row the regex didn't catch),
it refuses to import that report rather than saving a wrong total.

### Daily runs only read new PDFs

The importer remembers every PDF it has fully dealt with (saved, already in
the database, a crop no longer tracked, or simply not a market-agent invoice)
in `scripts/import_seen.json`, so the scheduled run only reads new or changed
files. Invoices it couldn't read are tried again each run and listed under
**NEEDS A LOOK** at the end of `import_log.txt`. To read everything again
(e.g. after a parser fix), add `--rescan`:

```
python scripts\import_sales_report.py "D:\Kliente\Nanini 121 BK" --yes --rescan
```

## fetch_gmail_invoices.py

Downloads market-agent account sales that arrive by **email** into the
client folder (`<tax year>\BTW\Gmail\<YYYYMM>\`), where the daily import
picks them up. It reads every PDF attachment from recent emails and keeps
only the ones the importer recognises as an account sale -- statements,
quotes and newsletters are ignored. Gmail itself is opened read-only.
Runs automatically as the first step of `run_import_task.bat`.

### Setup (once)

1. Your Google account needs **2-Step Verification** switched on
   (myaccount.google.com -> Security).
2. Create an **app password**: go to https://myaccount.google.com/apppasswords,
   name it e.g. `Nanini PC`, click Create and copy the 16 letters.
3. In Notepad, create `scripts\gmail_account.txt` with two lines -- the
   Gmail address, then the app password -- and save it next to this script
   (Save as type: All files).

`gmail_account.txt` is in `.gitignore` -- keep it only on the office PC. To
stop the script's access at any time, delete the app password on the same
Google page.

By default it looks back 60 days; the first time you can look further:

```
python scripts\fetch_gmail_invoices.py "D:\Kliente\Nanini 121 BK" --days 365
```

