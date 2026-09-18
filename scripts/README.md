# Scripts

## import_sales_report.py

Imports a market agent's account-sales PDF straight into the Sales tables,
instead of typing it into the app by hand.

### Setup (once)

```
pip install pdfplumber requests
```

### Usage

```
python3 scripts/import_sales_report.py path/to/invoice.pdf
```

It prints what it parsed (including a box-count / average-price breakdown
by size, for peppers) and asks for confirmation before saving. Pass `--yes`
to skip the confirmation prompt. Run it from your own computer — it won't
work from a sandboxed environment that blocks outbound network access to
Supabase.

### Currently supported market agents

- RSA Markagente (Interaction Market Services Tshwane)

### Adding another agent (e.g. Wenpro)

Send Claude a sample PDF from that agent, and ask it to add a
`parse_<agent>()` function plus a detection rule in `detect_and_parse()`,
following the same pattern as `parse_rsa()`.

### Unknown product codes

If an invoice uses a product code that isn't in `PRODUCT_CODE_MAP` yet
(e.g. a potato size code, tobacco grade, or butternut size on an RSA
invoice), the script stops with a clear error naming the code rather than
guessing — extend the map with the correct (category, subcategory) pair.
