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
run once in the Supabase SQL editor). Runs automatically twice every weekday
from GitHub Actions (`.github/workflows/diesel-price.yml` -- also "Run
workflow" by hand from the Actions tab), and as part of
`run_import_task.bat`'s daily schedule on the office PC (logs to
`scripts/diesel_price_log.txt`).

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

### Setup (once): Gmail access

Both Gmail scripts (this one and `fetch_supplier_docs.py`) read Gmail through
`scripts\gmail_access.py`, **read-only**. The Google sign-in below needs no
2-Step Verification. (An app password in `scripts\gmail_account.txt` still
works too, but only while 2-Step Verification is on.)

On the office PC, signed in to Chrome/Edge with the Gmail account:

1. Open https://console.cloud.google.com -- accept the terms if asked.
2. Project picker (top left) -> **New project** -> name `Nanini office PC`
   -> **Create**, then make sure it's the selected project.
3. Open https://console.cloud.google.com/apis/library/gmail.googleapis.com
   -> **Enable**.
4. Open https://console.cloud.google.com/auth/overview -> **Get started**:
   app name `Nanini office PC`, support email = your Gmail; Audience
   **External**; contact email = your Gmail; agree -> **Create**.
5. **Audience** (left) -> Publishing status -> **Publish app** -> Confirm.
   (Left on "Testing", Google ends the sign-in after 7 days.)
6. **Clients** (left) -> **Create client** -> Application type **Desktop
   app**, name `Nanini office PC` -> **Create** -> **Download JSON** (saved
   in Downloads as `client_secret_....json`).
7. In the command window:

   ```
   cd /d C:\Claude
   py -m pip install google-auth-oauthlib
   py scripts\gmail_access.py
   ```

   It finds the downloaded file, and the browser opens: choose the Gmail
   account. Google warns "Google hasn't verified this app" -- it's your own
   app: **Advanced** -> **Go to Nanini office PC**. Allow **View your email
   messages and settings** (read-only) -> **Continue**. The command window
   then says `OK: signed in to ... (read-only)`.

`gmail_oauth_client.json` and `gmail_token.json` (the sign-in) are in
`.gitignore` -- they stay on the office PC only. To take the access away:
Google Account -> Security -> Your connections to third-party apps &
services -> Nanini office PC -> Delete all connections. If a run says the
sign-in has run out, run `py scripts\gmail_access.py` again.

By default it looks back 60 days; the first time you can look further:

```
python scripts\fetch_gmail_invoices.py "D:\Kliente\Nanini 121 BK" --days 365
```


## fetch_supplier_docs.py

Brings supplier **invoices, credit notes and statements** that arrive by
email into the hub's **Suppliers** app, as **"From email -- to check"** on
that supplier's Recon tab. Someone checks each one against its PDF in the
app and presses **Confirm** -- only then does it count in the account.
Runs automatically in `run_import_task.bat`, after the sales import (log:
`scripts\supplier_docs_log.txt`).

What it does:

* Reads the suppliers from the app. A supplier's **Email** field lists the
  address(es) their documents come from, separated by commas; an entry like
  `@agri.co.za` matches anyone at that domain. Suppliers without an email
  are left out.
* Reads Gmail the same way as `fetch_gmail_invoices.py` (the Google sign-in
  -- see its setup above). Access is **read-only**: nothing is changed,
  moved, deleted, labelled, sent or marked as read.
* Only emails **from a supplier's address** with a PDF are looked at; all
  other mail is skipped and nothing about it is kept.
* Uploads each PDF to the app's private `supplier-docs` storage and fills in
  what it could read: invoice / credit note / statement, the date, the
  number and the total (a statement's closing balance). Scanned PDFs it
  can't read come in with the amount empty, to type in.
* Remembers handled emails in `scripts\supplier_gmail_seen.json` (Gmail
  message numbers only) and never adds the same attachment twice.

Needs (once): `docs/sql/suppliers.sql`, `suppliers_banking.sql` and
`suppliers_email.sql` run in Supabase, and the secret key in
`scripts\supabase_secret_key.txt` (as for the sales import).

```
python scripts\fetch_supplier_docs.py --dry-run      # show what it would add, change nothing
python scripts\fetch_supplier_docs.py --days 120     # the first time: look further back
```

**Purchases report:** it also reads the VAT and the invoice lines (VKB's
items; an Eskom bill's charges; otherwise the whole invoice as one line),
for the app's Purchases tab, where each line goes against a contra (GL)
account. Needs `docs/sql/suppliers_purchases.sql` run once. For documents
brought in before that, read them again from their PDFs (no Gmail needed):

```
py scripts\fetch_supplier_docs.py --fill-details --dry-run
py scripts\fetch_supplier_docs.py --fill-details
```

Tests (no Gmail or app needed): `python -m unittest scripts/test_fetch_supplier_docs.py`


## import_bank_payments.py

Adds **payments to suppliers** from ABSA bank statement CSVs to the hub's
Suppliers app, so they don't have to be typed in.

1. In Absa online banking, export the account's transaction history for a
   period as **CSV** (columns Date, Description, Amount, Balance) and save it
   in the client folder, e.g. `D:\Kliente\Nanini 121 BK\2027\BTW`.
2. Run (the daily `run_import_task.bat` does this for the whole client
   folder):

   ```
   py scripts\import_bank_payments.py "D:\Kliente\Nanini 121 BK\2027\BTW" --dry-run
   py scripts\import_bank_payments.py "D:\Kliente\Nanini 121 BK\2027\BTW"
   ```

Only payments to a beneficiary ("ABSA BANK <name>") are looked at. The name
is matched to a supplier by its account number ("Eskom 8441635490") or by
the supplier's name / bank account holder at the start ("VKB Augustus 2026",
"NTB"). A name that fits several suppliers (just "Eskom") is listed, not
added. Wages, cash, card purchases and other payees are left alone. A
payment already in the app for that supplier on the same day with the same
amount isn't added again, so overlapping CSVs and re-runs are safe.

The bank CSVs stay on the office PC -- never commit or share them.

Tests: `python -m unittest scripts/test_import_bank_payments.py`
