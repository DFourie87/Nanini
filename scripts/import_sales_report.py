#!/usr/bin/env python3
"""
Import market agent account-sales PDFs straight into the Nanini Sales
tables, instead of typing them into the app by hand.

Usage:
    pip install pdfplumber requests
    python3 scripts/import_sales_report.py path/to/invoice.pdf
    python3 scripts/import_sales_report.py path/to/a/folder   # scans recursively for PDFs
    python3 scripts/import_sales_report.py path/to/invoice.pdf --yes   # skip confirmation

A single PDF can bundle multiple invoices (one per page) — each one found
is parsed, shown, and saved as its own separate Sales report. Pointing the
script at a folder finds every PDF under it (recursively) and processes
them one by one; reports already in the database are skipped automatically.

This talks to the same Supabase project the app uses (same URL + publishable
anon key as nanini_app/lib/core/supabase_client.dart), so an insert here
shows up in the app immediately.

Run this from your own computer/network — Supabase isn't reachable from
some sandboxed environments (e.g. Claude's own containers), which is why
this exists as a script you run yourself rather than something Claude runs
for you directly.

Currently supported market agents / layouts:
  - RSA Markagente (Interaction Market Services Tshwane)
  - Wenpro Markagente, CL de Villiers Markagente, Botha Roodt Johannesburg
    and Dapper Agencies (these four share one underlying invoice template,
    in Afrikaans or English)
  - Universal Leaf South Africa (tobacco) — sub-grades like F2F/F2P/F4P are
    rolled up into their base grade (F1-F6, S1-S4) since that's all the
    app tracks for tobacco

Every finer size/grade split (e.g. a pepper colour's 5kg vs 4kg boxes, or a
tobacco base grade's F2F vs F2P sub-grades) is saved as its own line item,
with the quantity and average price recorded in that line item's
description — the app doesn't have a dedicated quantity column, so this is
how that detail stays visible when you open a report in the app.

Adding support for another market agent: send Claude a sample PDF and ask
it to extend this script. Unknown product/grade codes raise a clear error
naming the code rather than guessing at what they mean.
"""
import argparse
import pathlib
import re
import sys

SUPABASE_URL = "https://nwyizwccmyanbdjmmdds.supabase.co"
SUPABASE_ANON_KEY = "sb_publishable_rJTMVGBh4FleAEBrDPWQzw_QC7c2dxV"

REPORT_DB_FIELDS = [
    "category", "agent", "report_number", "report_date",
    "gross_total", "commission_before_vat", "vat", "vat_on_sales", "nett_amount",
]


class ParseError(Exception):
    pass


def extract_pages(pdf_path):
    import pdfplumber

    with pdfplumber.open(pdf_path) as pdf:
        return [page.extract_text() or "" for page in pdf.pages]


# ---------------------------------------------------------------------------
# RSA Markagente (Interaction Market Services Tshwane)
# ---------------------------------------------------------------------------

RSA_PEPPER_COLOUR_MAP = {"PPRE": "Red", "PPYE": "Yellow", "PPGR": "Green"}
RSA_PEPPER_SIZE_MAP = {"L": "5kg", "M": "4kg"}
RSA_BUTTERNUT_SIZE_MAP = {"L": "10kg", "M": "7kg"}


def _classify_rsa_product(code, size_code):
    """Returns (category, subcategory, size_label) or raises ParseError."""
    if code in RSA_PEPPER_COLOUR_MAP:
        return "peppers", RSA_PEPPER_COLOUR_MAP[code], RSA_PEPPER_SIZE_MAP.get(size_code, size_code)
    if code == "BNUT":
        if size_code not in RSA_BUTTERNUT_SIZE_MAP:
            raise ParseError(f"Unknown RSA butternut size code {size_code!r} — add it to RSA_BUTTERNUT_SIZE_MAP.")
        label = RSA_BUTTERNUT_SIZE_MAP[size_code]
        return "butternut", label, label
    raise ParseError(f"Unknown RSA product code {code!r} — add a mapping for it in _classify_rsa_product.")


def parse_rsa(text):
    report_number_m = re.search(r"ACCOUNT SALES NO\s*:\s*(\d+)", text)
    date_m = re.search(r"\bDATE\s*:\s*(\d{2})/(\d{2})/(\d{4})", text)
    gross_m = re.search(r"GROSS AMOUNT\s+([\d.]+)", text)
    nett_m = re.search(r"NETT AMOUNT\s+([\d.]+)", text)
    if not (report_number_m and date_m and gross_m and nett_m):
        raise ParseError("Could not find report number / date / gross / nett amount in RSA invoice text.")

    report_date = f"{date_m.group(3)}-{date_m.group(2)}-{date_m.group(1)}"

    # Named deduction rows vary (COLDSTORAGE isn't always present), so rather
    # than enumerate specific labels, take the deductions table's own grand
    # total row: a line of exactly three bare numbers (Amount, VAT, Total),
    # which always appears last, right before NETT AMOUNT.
    grand_total_matches = re.findall(r"^([\d.]+)\s+([\d.]+)\s+([\d.]+)\b", text, re.MULTILINE)
    if not grand_total_matches:
        raise ParseError("Could not find the deductions grand-total row in this RSA invoice.")
    commission_before_vat, vat, _ = (float(x) for x in grand_total_matches[-1])

    detail = {}  # (category, subcategory, class, size_label) -> {"sold": boxes, "value": rand}
    for block in text.split("---"):
        prod_m = re.search(r"PRODUCT\s*:\s*(\S+)\s+(\S+)\s+\S+\s+.+?SMAN", block)
        sold_m = re.search(r"SOLD\s*:\s*(\d+)", block)
        value_m = re.search(r"VALUE\s*:\s*([\d.]+)", block)
        if not prod_m or not value_m:
            continue
        code = prod_m.group(1).upper()
        size_code = prod_m.group(2).upper()
        category, subcategory, size_label = _classify_rsa_product(code, size_code)
        value = float(value_m.group(1))
        sold = int(sold_m.group(1)) if sold_m else 0

        key = (category, subcategory, None, size_label)
        entry = detail.setdefault(key, {"sold": 0, "value": 0.0})
        entry["sold"] += sold
        entry["value"] += value

    if not detail:
        raise ParseError("Found no product lines in this invoice.")
    categories = {k[0] for k in detail}
    if len(categories) != 1:
        raise ParseError(f"Invoice mixes multiple sales categories ({categories}) — not supported yet.")

    return [_build_report(
        category=categories.pop(),
        agent="RSA Markagente Pretoria",
        report_number=report_number_m.group(1),
        report_date=report_date,
        gross_total=float(gross_m.group(1)),
        commission_before_vat=round(commission_before_vat, 2),
        vat=round(vat, 2),
        vat_on_sales=None,
        nett_amount=float(nett_m.group(1)),
        detail=detail,
        unit_name="boxes",
    )]


# ---------------------------------------------------------------------------
# Shared template: Wenpro / CL de Villiers / Botha Roodt / Dapper
# (same underlying software, Afrikaans or English labels)
# ---------------------------------------------------------------------------

WENFAM_AGENT_MARKERS = [
    ("WENPRO MARKAGENTE", "Wenpro Markagente"),
    ("CL DE VILLIERS MARKAGENTE", "CL de Villiers Markagente"),
    ("BOTHA ROODT JOHANNESBURG", "Botha Roodt Johannesburg"),
    ("DAPPER AGENCIES", "Dapper Agencies"),
]

NUM_INT = r"\d+(?:\s\d{3})*"
NUM_DEC = r"\d+(?:\s\d{3})*\.\d+"

# grn-no, descriptor (lazy), then 7 numeric columns:
# Lewer/Sent, ReedsBetaal/PrevPaid, Verniet/Discards, BetaalNou/PayNow,
# PrysPer/Price (decimal), Bruto/Gross (decimal), AantalVrd/QtyUnsold
WENFAM_ROW_RE = re.compile(
    r"^(\d+)\s+(.+?)\s+(" + NUM_INT + r")\s+(" + NUM_INT + r")\s+(" + NUM_INT + r")\s+(" + NUM_INT + r")\s+("
    + NUM_DEC + r")\s+(" + NUM_DEC + r")\s+(" + NUM_INT + r")\s*$",
    re.MULTILINE,
)
WENFAM_TOTAAL_RE = re.compile(
    r"^(?:Totaal|Total):\s+(" + NUM_INT + r")\s+(" + NUM_INT + r")\s+(" + NUM_INT + r")\s+(" + NUM_INT + r")\s+("
    + NUM_DEC + r")\s+(" + NUM_DEC + r")\s+(" + NUM_INT + r")\s*$",
    re.MULTILINE,
)

POTATO_SIZE_MAP = {
    "XS": "Baby", "S/M": "Small/Medium", "L/M": "Large/Medium",
    "S": "Small", "M": "Medium", "L": "Large",
}
BUTTERNUT_PACK_MAP = {"100": "10kg", "070": "7kg"}


def _sa_number(s):
    return float(s.replace(" ", ""))


def _classify_wenfam_product(prefix, descriptor):
    """Returns (category, subcategory, klass, size_label) or None if unsupported."""
    if prefix == "POTS":
        m = re.search(r"\bCL\s+(\d)\s+(XS|S/M|L/M|S|M|L)\b", descriptor)
        if not m:
            raise ParseError(f"Could not read potato class/size from product description {descriptor!r}.")
        klass = f"Class {m.group(1)}"
        size_code = m.group(2)
        return "potatoes", POTATO_SIZE_MAP[size_code], klass, size_code
    if prefix == "BNUT":
        m = re.search(r"PC(\d{3})", descriptor)
        if not m or m.group(1) not in BUTTERNUT_PACK_MAP:
            raise ParseError(f"Unknown butternut pack code in {descriptor!r} — add it to BUTTERNUT_PACK_MAP.")
        return "butternut", BUTTERNUT_PACK_MAP[m.group(1)], None, BUTTERNUT_PACK_MAP[m.group(1)]
    if prefix in ("PEPY", "PEPR", "PEPG"):
        colour = {"PEPY": "Yellow", "PEPR": "Red", "PEPG": "Green"}[prefix]
        m = re.search(r"\bCL\s+\d+\s+([LM])\b", descriptor)
        size_code = m.group(1) if m else "?"
        return "peppers", colour, None, size_code
    return None  # unsupported produce (e.g. MELW = melons) — not a sales category the app tracks


def parse_wenfam_page(text):
    agent = next((name for marker, name in WENFAM_AGENT_MARKERS if marker in text), None)
    if agent is None:
        return None

    report_number_m = re.search(r"(?:Verkope nr|Account Sale no):\s*(\d+)", text)
    date_m = re.search(r"\b(?:Datum|Date):\s*(\d{4})/(\d{2})/(\d{2})", text)
    deductions_m = re.search(
        r"(?:Totale Aftrekkings \(BTW Uitgesluit\)|Total Deductions \(Excluding VAT\))\s+("
        + NUM_DEC + r")\s+(" + NUM_DEC + r")",
        text,
    )
    nett_m = re.search(r"(?:Netto Bedrag|Nett Amount)\s+(" + NUM_DEC + r")", text)
    if not (report_number_m and date_m and deductions_m and nett_m):
        return None  # not a full invoice on this page (e.g. a continuation page) — nothing to import

    detail = {}  # (category, subcategory, class, size_label) -> {"sold": units, "value": rand}
    skipped_unsupported = []
    row_gross_sum = 0.0
    for row_m in WENFAM_ROW_RE.finditer(text):
        grn, descriptor = row_m.group(1), row_m.group(2)
        # groups: 1=grn 2=descriptor 3=Lewer 4=ReedsBetaal 5=Verniet 6=BetaalNou 7=PrysPer 8=Bruto 9=AantalVrd
        betaal_nou, prysper, bruto, aantal = row_m.group(6), row_m.group(7), row_m.group(8), row_m.group(9)
        prefix_m = re.match(r"([A-Z]{3,4})\b", descriptor)
        if not prefix_m:
            continue
        prefix = prefix_m.group(1)
        classified = _classify_wenfam_product(prefix, descriptor)
        bruto_val = _sa_number(bruto)
        row_gross_sum += bruto_val
        if classified is None:
            skipped_unsupported.append((grn, descriptor, bruto_val))
            continue
        category, subcategory, klass, size_label = classified
        sold = int(_sa_number(betaal_nou))  # "Betaal nou" / "Pay now" = units settled this invoice

        key = (category, subcategory, klass, size_label)
        entry = detail.setdefault(key, {"sold": 0, "value": 0.0})
        entry["sold"] += sold
        entry["value"] += bruto_val

    totaal_m = WENFAM_TOTAAL_RE.search(text)
    if totaal_m:
        printed_total = _sa_number(totaal_m.group(6))
        if abs(printed_total - row_gross_sum) > 0.05:
            raise ParseError(
                f"Parsed line items sum to R{row_gross_sum:.2f} but the invoice's printed total is "
                f"R{printed_total:.2f} — row parsing likely missed something; not importing this report."
            )

    if not detail:
        if skipped_unsupported:
            names = ", ".join(sorted({d.split()[0] for _, d, _ in skipped_unsupported}))
            raise ParseError(f"Report {report_number_m.group(1)}: only unsupported produce found ({names}). Skipping.")
        raise ParseError(f"Report {report_number_m.group(1)}: found no product lines.")

    categories = {k[0] for k in detail}
    if len(categories) != 1:
        raise ParseError(f"Report {report_number_m.group(1)} mixes multiple categories ({categories}) — not supported yet.")

    report_date = f"{date_m.group(1)}-{date_m.group(2)}-{date_m.group(3)}"
    commission_before_vat, vat = _sa_number(deductions_m.group(1)), _sa_number(deductions_m.group(2))
    nett_amount = _sa_number(nett_m.group(1))
    gross_total = sum(d["value"] for d in detail.values())

    return _build_report(
        category=categories.pop(),
        agent=agent,
        report_number=report_number_m.group(1),
        report_date=report_date,
        gross_total=round(gross_total, 2),
        commission_before_vat=round(commission_before_vat, 2),
        vat=round(vat, 2),
        vat_on_sales=None,
        nett_amount=round(nett_amount, 2),
        detail=detail,
        unit_name="units",
    )


def parse_wenfam(pages):
    reports = []
    for page_text in pages:
        try:
            report = parse_wenfam_page(page_text)
        except ParseError as e:
            print(f"  (skipping one invoice on this PDF: {e})", file=sys.stderr)
            continue
        if report is not None:
            reports.append(report)
    return reports


# ---------------------------------------------------------------------------
# Universal Leaf South Africa (tobacco)
# ---------------------------------------------------------------------------

TOBACCO_BASE_GRADES = {f"F{i}" for i in range(1, 7)} | {f"S{i}" for i in range(1, 5)}
NUM_COMMA = r"[\d,]+\.\d{2}"


def _comma_number(s):
    return float(s.replace(",", ""))


def parse_tobacco_ulsa(text):
    if "Universal Leaf South Africa" not in text and "ULSA" not in text:
        return None

    report_number_m = re.search(r"TAX INVOICE NO:\s*(\S+)", text)
    date_m = re.search(r"Date Of Sale:\s*(\d{1,2})/(\d{1,2})/(\d{4})", text)
    total_row_m = re.search(
        r"Total:\s+(" + NUM_COMMA + r")\s+(\d+)\s+(" + NUM_COMMA + r")\s+(" + NUM_COMMA + r")\s+(" + NUM_COMMA + r")",
        text,
    )
    deductions_m = re.search(
        r"Total Deductions:\s+(-?" + NUM_COMMA + r")\s+(-?" + NUM_COMMA + r")\s+(-?" + NUM_COMMA + r")", text
    )
    nett_m = re.search(r"Total Net Payment\s+(" + NUM_COMMA + r")", text)
    if not (report_number_m and date_m and total_row_m and deductions_m and nett_m):
        raise ParseError("Could not find report number / date / totals in this ULSA tobacco invoice.")

    report_date = f"{date_m.group(3)}-{int(date_m.group(1)):02d}-{int(date_m.group(2)):02d}"

    row_re = re.compile(
        r"^(" + NUM_COMMA + r")\s+([A-Z0-9]+)\s+(\d+)\s+(" + NUM_COMMA + r")\s+(" + NUM_COMMA + r")\s+("
        + NUM_COMMA + r")\s+(" + NUM_COMMA + r")\s*$",
        re.MULTILINE,
    )
    detail = {}  # (category, base_grade, class, sub_grade) -> {"sold": kg, "value": rand}
    row_gross_sum = 0.0
    for m in row_re.finditer(text):
        kilos, grade, units, price, excl, vat_amt, total = m.groups()
        if grade == "Total":
            continue
        grade_m = re.match(r"^([FS]\d)([A-Z]?)$", grade)
        if not grade_m or grade_m.group(1) not in TOBACCO_BASE_GRADES:
            raise ParseError(
                f"Unknown tobacco grade {grade!r} — only F1-F6/S1-S4 (and their lettered sub-grades) are supported."
            )
        base_grade = grade_m.group(1)
        excl_val = _comma_number(excl)
        kg_val = _comma_number(kilos)
        row_gross_sum += excl_val

        key = ("tobacco", base_grade, None, grade)
        entry = detail.setdefault(key, {"sold": 0.0, "value": 0.0})
        entry["sold"] += kg_val
        entry["value"] += excl_val

    printed_total = _comma_number(total_row_m.group(3))
    if abs(printed_total - row_gross_sum) > 0.05:
        raise ParseError(
            f"Parsed tobacco grade lines sum to R{row_gross_sum:.2f} but the invoice total is R{printed_total:.2f}."
        )

    if not detail:
        raise ParseError("Found no tobacco grade lines in this invoice.")

    gross_total = _comma_number(total_row_m.group(3))
    vat_on_sales = _comma_number(total_row_m.group(4))
    commission_before_vat = abs(_comma_number(deductions_m.group(1)))
    vat = abs(_comma_number(deductions_m.group(2)))
    nett_amount = _comma_number(nett_m.group(1))

    return [_build_report(
        category="tobacco",
        agent="Universal Leaf South Africa",
        report_number=report_number_m.group(1),
        report_date=report_date,
        gross_total=round(gross_total, 2),
        commission_before_vat=round(commission_before_vat, 2),
        vat=round(vat, 2),
        vat_on_sales=round(vat_on_sales, 2),
        nett_amount=round(nett_amount, 2),
        detail=detail,
        unit_name="kg",
    )]


# ---------------------------------------------------------------------------
# Shared report-building / DB helpers
# ---------------------------------------------------------------------------

def _build_report(category, agent, report_number, report_date, gross_total, commission_before_vat,
                   vat, vat_on_sales, nett_amount, detail, unit_name):
    """`detail` maps (category, subcategory, class, size_label) -> {"sold": qty, "value": rand}.

    One line item is saved per key (not merged by subcategory alone), so the
    finer size/grade breakdown is visible in the app, not just in this
    script's console output. `size_label` is folded into the description
    when it says something beyond the subcategory itself (e.g. a pepper
    colour's box size, or a tobacco base grade's sub-grade) — for
    potatoes/butternut, where the subcategory already *is* the size, it's
    just the quantity/avg price.
    """
    line_items = []
    for (cat, subcat, klass, size_label), info in sorted(detail.items()):
        sold, value = info["sold"], info["value"]
        avg = value / sold if sold else 0.0
        qty_str = f"{sold:,.2f}" if unit_name == "kg" else f"{int(sold):,}"
        prefix = f"{size_label}: " if size_label and size_label != subcat else ""
        description = f"{prefix}{qty_str} {unit_name} @ R{avg:.2f}/{unit_name}"
        line_items.append({
            "category": cat,
            "subcategory": subcat,
            "class": klass,
            "gross_amount": round(value, 2),
            "description": description,
        })

    return {
        "category": category,
        "agent": agent,
        "report_number": report_number,
        "report_date": report_date,
        "gross_total": gross_total,
        "commission_before_vat": commission_before_vat,
        "vat": vat,
        "vat_on_sales": vat_on_sales,
        "nett_amount": nett_amount,
        "line_items": line_items,
    }


def detect_and_parse(pages):
    joined = "\n".join(pages)
    if "RSA MARKAGENTE" in joined or "INTERACTION MARKET SERVICES" in joined:
        return parse_rsa(joined)
    if any(marker in joined for marker, _ in WENFAM_AGENT_MARKERS):
        reports = parse_wenfam(pages)
        if not reports:
            raise ParseError("Recognised this as a Wenpro-family invoice but couldn't extract any usable report.")
        return reports
    if "Universal Leaf South Africa" in joined or "ULSA" in joined:
        return parse_tobacco_ulsa(joined)
    raise ParseError(
        "Don't recognise this invoice's layout.\n"
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


def print_report(report):
    print("Parsed report:")
    print(f"  Category:      {report['category']}")
    print(f"  Agent:         {report['agent']}")
    print(f"  Report number: {report['report_number']}")
    print(f"  Report date:   {report['report_date']}")
    print(f"  Gross total:   R {report['gross_total']:,.2f}")
    print(f"  Commission:    R {report['commission_before_vat']:,.2f}")
    print(f"  VAT:           R {report['vat']:,.2f}")
    if report["vat_on_sales"] is not None:
        print(f"  VAT on sales:  R {report['vat_on_sales']:,.2f}")
    print(f"  Nett amount:   R {report['nett_amount']:,.2f}")
    print("  Line items (saved to the app, with size/grade breakdown in each description):")
    for li in report["line_items"]:
        klass = f" ({li['class']})" if li["class"] else ""
        print(f"    {li['subcategory']:<14}{klass:<10} R {li['gross_amount']:>12,.2f}  [{li['description']}]")


def process_pdf(pdf_path, args, totals):
    pages = extract_pages(str(pdf_path))
    try:
        reports = detect_and_parse(pages)
    except ParseError as e:
        print(f"  Could not parse this invoice: {e}", file=sys.stderr)
        totals["failed"] += 1
        return

    for i, report in enumerate(reports, 1):
        print(f"  --- Report {i} of {len(reports)} ---")
        print_report(report)

        if report_exists(report["report_number"]):
            print(f"\n  Report number {report['report_number']} is already in the database — not importing again.\n")
            totals["skipped"] += 1
            continue

        if not args.yes:
            answer = input("\n  Save this report to the live Sales database? [y/N] ").strip().lower()
            if answer != "y":
                print("  Not saved.\n")
                totals["skipped"] += 1
                continue

        report_id = save_report(report)
        print(f"\n  Saved. Report id: {report_id}\n")
        totals["saved"] += 1


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("path", help="A single invoice PDF, or a folder to scan recursively for PDFs.")
    parser.add_argument("--yes", action="store_true", help="Skip the confirmation prompt.")
    args = parser.parse_args()

    target = pathlib.Path(args.path)
    if target.is_dir():
        pdf_paths = sorted(target.rglob("*.pdf"))
        if not pdf_paths:
            print(f"No PDFs found under {target}.")
            sys.exit(0)
    else:
        pdf_paths = [target]

    totals = {"saved": 0, "skipped": 0, "failed": 0}
    for n, pdf_path in enumerate(pdf_paths, 1):
        print(f"\n########## [{n}/{len(pdf_paths)}] {pdf_path} ##########")
        process_pdf(pdf_path, args, totals)

    print(f"\nDone: {totals['saved']} saved, {totals['skipped']} skipped, {totals['failed']} unreadable/unsupported.")


if __name__ == "__main__":
    main()
