# Scripts

## import_sales_report.py

Imports market agent account-sales PDFs straight into the Sales tables,
instead of typing them into the app by hand.

### Setup (once)

```
pip install pdfplumber requests
```

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
