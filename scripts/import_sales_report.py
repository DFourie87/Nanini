#!/usr/bin/env python3
"""
Import a market agent's account-sales PDF straight into the Nanini Sales
tables, instead of typing it into the app by hand.

Usage:
    pip install pdfplumber requests
    python3 scripts/import_sales_report.py path/to/invoice.pdf
    python3 scripts/import_sales_report.py path/to/invoice.pdf --yes   # skip confirmation

This talks to the same Supabase project the app uses (same URL + publishable
anon key as nanini_app/lib/core/supabase_client.dart), so an insert here
shows up in the app immediately.

Run this from your own computer/network — Supabase isn't reachable from
some sandboxed environments (e.g. Claude's own containers), which is why
this exists as a script you run yourself rather than something Claude runs
for you directly.

Adding support for another market agent (e.g. Wenpro):
  1. Send Claude a sample PDF from that agent.
  2. Claude adds a new parse_<agent>() function below plus a detection rule
     in detect_and_parse(), following the same pattern as parse_rsa().
Unknown product codes for a category Claude hasn't mapped yet (e.g. potato
size codes, tobacco grades, butternut sizes on an RSA invoice) will raise a
clear error naming the code — extend PRODUCT_CODE_MAP rather than guessing.
"""
import argparse
import re
import sys

SUPABASE_URL = "https://nwyizwccmyanbdjmmdds.supabase.co"
SUPABASE_ANON_KEY = "sb_publishable_rJTMVGBh4FleAEBrDPWQzw_QC7c2dxV"

# Market-agent product code -> (sales category key, subcategory label).
# Extend this as new codes turn up on new invoices. Peppers only track
# colour in the app (not packaging size), so different size codes for the
# same colour (e.g. PPRE L and PPRE M) intentionally map to the same entry
# and get summed together.
PRODUCT_CODE_MAP = {
    "PPRE": ("peppers", "Red"),
    "PPYE": ("peppers", "Yellow"),
    "PPGR": ("peppers", "Green"),
}

# Market-agent size code -> human label, for the box-count/avg-price
# breakdown printed alongside each import (informational only — the app's
# sales_line_items table doesn't store box size, only colour, for peppers).
SIZE_LABEL_MAP = {
    "L": "5kg",
    "M": "4kg",
}

# Columns that actually exist on sales_reports — everything else on the
# parsed report dict (line_items, size_breakdown) is for display only.
REPORT_DB_FIELDS = [
    "category", "agent", "report_number", "report_date",
    "gross_total", "commission_before_vat", "vat", "vat_on_sales", "nett_amount",
]


class ParseError(Exception):
    pass


def extract_text(pdf_path):
    import pdfplumber

    with pdfplumber.open(pdf_path) as pdf:
        return "\n".join(page.extract_text() or "" for page in pdf.pages)


def parse_rsa(text):
    """RSA Market Agents (Interaction Market Services Tshwane) account-sales layout."""
    report_number_m = re.search(r"ACCOUNT SALES NO\s*:\s*(\d+)", text)
    date_m = re.search(r"\bDATE\s*:\s*(\d{2})/(\d{2})/(\d{4})", text)
    gross_m = re.search(r"GROSS AMOUNT\s+([\d.]+)", text)
    nett_m = re.search(r"NETT AMOUNT\s+([\d.]+)", text)
    if not (report_number_m and date_m and gross_m and nett_m):
        raise ParseError("Could not find report number / date / gross / nett amount in RSA invoice text.")

    report_date = f"{date_m.group(3)}-{date_m.group(2)}-{date_m.group(1)}"

    # Deductions table: MARKET FEES / COLDSTORAGE / AGENT COMMISSION / BANK CHARGES,
    # each "<label>  <amount>  <vat>  <total>". Sum amount + vat across all of them.
    commission_before_vat = 0.0
    vat = 0.0
    for label in ("MARKET FEES", "COLDSTORAGE", "AGENT COMMISSION", "BANK CHARGES"):
        m = re.search(rf"{label}\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)", text)
        if not m:
            raise ParseError(f"Could not find deduction line for {label!r}.")
        commission_before_vat += float(m.group(1))
        vat += float(m.group(2))

    # Each product block: "PRODUCT : <code> <size> <pack> <description...> SMAN"
    # followed later (same block) by "... SOLD : <count> ... VALUE : <amount>".
    line_totals = {}  # (category, subcategory) -> summed gross, for the DB
    size_breakdown = {}  # (category, subcategory, size_code) -> {sold, value}, display only
    blocks = text.split("---")
    for block in blocks:
        prod_m = re.search(r"PRODUCT\s*:\s*(\S+)\s+(\S+)\s+\S+\s+.+?SMAN", block)
        sold_m = re.search(r"SOLD\s*:\s*(\d+)", block)
        value_m = re.search(r"VALUE\s*:\s*([\d.]+)", block)
        if not prod_m or not value_m:
            continue
        code = prod_m.group(1).upper()
        size_code = prod_m.group(2).upper()
        if code not in PRODUCT_CODE_MAP:
            raise ParseError(
                f"Unknown product code {code!r} — add it to PRODUCT_CODE_MAP in this script "
                f"(category, subcategory) before importing this invoice."
            )
        category, subcategory = PRODUCT_CODE_MAP[code]
        value = float(value_m.group(1))
        sold = int(sold_m.group(1)) if sold_m else None

        key = (category, subcategory)
        line_totals[key] = line_totals.get(key, 0.0) + value

        size_key = (category, subcategory, size_code)
        entry = size_breakdown.setdefault(size_key, {"sold": 0, "value": 0.0})
        entry["sold"] += sold or 0
        entry["value"] += value

    if not line_totals:
        raise ParseError("Found no product lines in this invoice.")

    categories = {k[0] for k in line_totals}
    if len(categories) != 1:
        raise ParseError(f"Invoice mixes multiple sales categories ({categories}) — not supported yet.")
    category = categories.pop()

    return {
        "category": category,
        "agent": "RSA Markagente Pretoria",
        "report_number": report_number_m.group(1),
        "report_date": report_date,
        "gross_total": float(gross_m.group(1)),
        "commission_before_vat": round(commission_before_vat, 2),
        "vat": round(vat, 2),
        "vat_on_sales": None,
        "nett_amount": float(nett_m.group(1)),
        "line_items": [
            {"category": cat, "subcategory": subcat, "class": None, "gross_amount": round(amount, 2)}
            for (cat, subcat), amount in line_totals.items()
        ],
        "size_breakdown": [
            {
                "category": cat,
                "subcategory": subcat,
                "size_code": size_code,
                "size_label": SIZE_LABEL_MAP.get(size_code, size_code),
                "sold": info["sold"],
                "value": round(info["value"], 2),
                "avg_price": round(info["value"] / info["sold"], 2) if info["sold"] else None,
            }
            for (cat, subcat, size_code), info in size_breakdown.items()
        ],
    }


def detect_and_parse(text):
    if "RSA MARKAGENTE" in text or "INTERACTION MARKET SERVICES" in text:
        return parse_rsa(text)
    raise ParseError(
        "Don't recognise this invoice's layout. Currently supported: RSA Markagente.\n"
        "Send this PDF to Claude to add a parser for whichever agent issued it."
    )


def report_exists(report_number):
    import requests

    resp = requests.get(
        f"{SUPABASE_URL}/rest/v1/sales_reports",
        params={"report_number": f"eq.{report_number}", "select": "id"},
        headers={"apikey": SUPABASE_ANON_KEY, "Authorization": f"Bearer {SUPABASE_ANON_KEY}"},
        timeout=30,
    )
    resp.raise_for_status()
    return len(resp.json()) > 0


def save_report(report):
    import requests

    headers = {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
        "Content-Type": "application/json",
        "Prefer": "return=representation",
    }
    report_body = {k: report[k] for k in REPORT_DB_FIELDS}
    resp = requests.post(f"{SUPABASE_URL}/rest/v1/sales_reports", json=report_body, headers=headers, timeout=30)
    resp.raise_for_status()
    report_id = resp.json()[0]["id"]

    line_items = [{**li, "report_id": report_id} for li in report["line_items"]]
    resp = requests.post(f"{SUPABASE_URL}/rest/v1/sales_line_items", json=line_items, headers=headers, timeout=30)
    resp.raise_for_status()
    return report_id


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("pdf_path")
    parser.add_argument("--yes", action="store_true", help="Skip the confirmation prompt.")
    args = parser.parse_args()

    text = extract_text(args.pdf_path)
    try:
        report = detect_and_parse(text)
    except ParseError as e:
        print(f"Could not parse this invoice: {e}", file=sys.stderr)
        sys.exit(1)

    print("Parsed report:")
    print(f"  Category:      {report['category']}")
    print(f"  Agent:         {report['agent']}")
    print(f"  Report number: {report['report_number']}")
    print(f"  Report date:   {report['report_date']}")
    print(f"  Gross total:   R {report['gross_total']:.2f}")
    print(f"  Commission:    R {report['commission_before_vat']:.2f}")
    print(f"  VAT:           R {report['vat']:.2f}")
    print(f"  Nett amount:   R {report['nett_amount']:.2f}")
    print("  Line items (saved to the app):")
    for li in report["line_items"]:
        print(f"    {li['subcategory']:<10} R {li['gross_amount']:.2f}")

    breakdown = report.get("size_breakdown")
    if breakdown:
        print("  Box counts by size (not stored by the app — shown here only):")
        for b in breakdown:
            avg = f"R {b['avg_price']:.2f}" if b["avg_price"] is not None else "n/a"
            print(f"    {b['subcategory']:<8} {b['size_label']:<5} {b['sold']:>5} boxes  R {b['value']:>10,.2f}  avg {avg}/box")
        by_size = {}
        for b in breakdown:
            s = by_size.setdefault(b["size_label"], {"sold": 0, "value": 0.0})
            s["sold"] += b["sold"]
            s["value"] += b["value"]
        for size_label, s in by_size.items():
            avg = f"R {s['value'] / s['sold']:.2f}" if s["sold"] else "n/a"
            print(f"    {'All':<8} {size_label:<5} {s['sold']:>5} boxes  R {s['value']:>10,.2f}  avg {avg}/box")

    if report_exists(report["report_number"]):
        print(f"\nReport number {report['report_number']} is already in the database — not importing again.")
        sys.exit(0)

    if not args.yes:
        answer = input("\nSave this report to the live Sales database? [y/N] ").strip().lower()
        if answer != "y":
            print("Not saved.")
            sys.exit(0)

    report_id = save_report(report)
    print(f"\nSaved. Report id: {report_id}")


if __name__ == "__main__":
    main()
