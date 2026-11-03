#!/usr/bin/env python3
"""
Finds account sale PDFs with several account sales in one file (RSA's
layout: RSA Markagente, Farmers Trust, Botha Roodt from Freshmark) and
checks each sale in it against Sales -- before the importer split such a
file, it read it as one sale: the first sale's number with every sale's
products, and the other sales were never saved. Only reads; changes
nothing.

    py scripts\\check_multi_account_sales.py "D:\\Kliente\\Nanini 121 BK"
    py scripts\\check_multi_account_sales.py "D:\\Kliente\\Nanini 121 BK" --all   # every PDF, whatever its name

Each sale is:
  OK       in Sales, its gross and its products as on the PDF
  MISSING  not in Sales: import the file again (the sales already in are skipped)
  WRONG    in Sales, but its gross or products differ (all the file's
           products under one number): delete it, then import the file again
The commands for it are printed at the end.
"""
import argparse
import pathlib
import re
import sys

from import_sales_report import SUPABASE_URL, ParseError, _auth_headers, detect_and_parse, extract_pages

# The names RSA-layout account sales come with ("12683_ACCSALES_PRE.RSA_...",
# "Account-Sales_092220_...", "..._PRE.BT1_...").
NAME_RE = re.compile(r"ACCSALES|Account-Sales|PRE\.(?:RSA|BT)", re.IGNORECASE)
SALE_NO_RE = re.compile(r"(?<!PREVIOUS )ACCOUNT SALES NO\s*:\s*(\d+)")


def sale_numbers(text):
    """The account sales in a PDF's text, in order (not its PREVIOUS ACCOUNT SALES NO)."""
    out = []
    for m in SALE_NO_RE.finditer(text):
        if m.group(1) not in out:
            out.append(m.group(1))
    return out


def verdict(report, saved, lines_total):
    """OK / MISSING / WRONG for a sale from the PDF ([report]) and what Sales
    has for its number ([saved]: its row or None; [lines_total]: its line
    items' gross together)."""
    if saved is None:
        return "MISSING"
    same_gross = abs(float(saved.get("gross_total") or 0) - report["gross_total"]) < 0.05
    same_lines = abs(lines_total - report["gross_total"]) < 0.05
    return "OK" if same_gross and same_lines else "WRONG"


def in_sales(report_number):
    """Sales' row for [report_number] and its line items' gross together, or (None, 0)."""
    import requests

    headers = _auth_headers()
    resp = requests.get(f"{SUPABASE_URL}/rest/v1/sales_reports", headers=headers, timeout=30,
                        params={"report_number": f"eq.{report_number}", "select": "id,gross_total,nett_amount"})
    resp.raise_for_status()
    rows = resp.json()
    if not rows:
        return None, 0.0
    resp = requests.get(f"{SUPABASE_URL}/rest/v1/sales_line_items", headers=headers, timeout=30,
                        params={"report_id": f"eq.{rows[0]['id']}", "select": "gross_amount"})
    resp.raise_for_status()
    return rows[0], sum(float(li.get("gross_amount") or 0) for li in resp.json())


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("folder", help="The client folder, e.g. D:\\Kliente\\Nanini 121 BK")
    parser.add_argument("--all", action="store_true", help="Read every PDF, not only those named like an account sale.")
    args = parser.parse_args()
    sys.stdout.reconfigure(line_buffering=True)

    root = pathlib.Path(args.folder)
    if not root.is_dir():
        print(f"PROBLEM: {root} doesn't exist. If it's on an external, USB or network drive, check it's connected.")
        return 1
    pdfs = [p for p in sorted(root.rglob("*.pdf")) if args.all or NAME_RE.search(p.name)]
    print(f"Checking {len(pdfs)} PDF(s){'' if args.all else ' named like an account sale'} under {root} ...")

    files = []  # (path, [(report, verdict)])
    for n, path in enumerate(pdfs, 1):
        if n % 200 == 0:
            print(f"  ... {n} of {len(pdfs)}")
        try:
            pages = extract_pages(str(path))
        except Exception:
            continue
        if len(sale_numbers("\n".join(pages))) < 2:
            continue
        try:
            reports = detect_and_parse(pages)
        except ParseError as e:
            files.append((path, [({"report_number": ", ".join(sale_numbers("\n".join(pages))), "gross_total": 0}, f"COULD NOT READ: {e}")]))
            continue
        checked = []
        for r in reports:
            saved, lines = in_sales(r["report_number"])
            checked.append((r, verdict(r, saved, lines), saved, lines))
        files.append((path, checked))

    if not files:
        print("\nNo PDF with several account sales in it. Nothing to fix.")
        return 0
    wrong, missing = [], []
    print(f"\n{len(files)} PDF(s) with several account sales in one file:")
    for path, checked in files:
        print(f"\n  {path}")
        for item in checked:
            r, v = item[0], item[1]
            if v.startswith("COULD NOT READ"):
                print(f"    sales {r['report_number']}: {v}")
                continue
            saved, lines = item[2], item[3]
            extra = "" if v != "WRONG" else f" -- Sales has gross R {float(saved.get('gross_total') or 0):,.2f}, products R {lines:,.2f}"
            print(f"    {v:<8} {r['report_number']} {r['report_date']}  gross R {r['gross_total']:,.2f}  nett R {r['nett_amount']:,.2f}{extra}")
            if v == "WRONG":
                wrong.append(r["report_number"])
            if v in ("WRONG", "MISSING") and path not in missing:
                missing.append(path)

    if not wrong and not missing:
        print("\nAll of them are in Sales as on the PDFs. Nothing to fix.")
        return 0
    print("\nTO FIX (after git pull):")
    for number in wrong:
        print(f'  py scripts\\import_sales_report.py --delete-report {number}')
    for path in missing:
        print(f'  py scripts\\import_sales_report.py "{path}"')
    return 0


if __name__ == "__main__":
    sys.exit(main())
