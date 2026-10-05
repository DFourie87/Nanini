#!/usr/bin/env python3
"""
Import market agent account-sales PDFs straight into the Nanini Sales
tables, instead of typing them into the app by hand.

Usage:
    pip install pdfplumber requests
    python3 scripts/import_sales_report.py path/to/invoice.pdf
    python3 scripts/import_sales_report.py path/to/a/folder   # scans recursively for PDFs
    python3 scripts/import_sales_report.py path/to/invoice.pdf --yes   # skip confirmation
    python3 scripts/import_sales_report.py --delete-report 56186011    # fix a bad import, then re-run it

A single PDF can bundle multiple invoices (one per page) — each one found
is parsed, shown, and saved as its own separate Sales report. Pointing the
script at a folder finds every PDF under it (recursively) and processes
them one by one; reports already in the database are skipped automatically
(but if one was saved without box/bag/kg counts, its line items are replaced
by the PDF's counted ones -- run once with --rescan to fill in old reports).

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
  - Peppadew International (the buyer): a grading report per load, its
    classes by kg and value, red or yellow by the supplier number
  - Universal Leaf South Africa (tobacco) — sub-grades like F2F/F2P/F4P are
    rolled up into their base grade (F1-F6, S1-S4) since that's all the
    app tracks for tobacco

Every finer size/grade split (e.g. a pepper colour's 5kg vs 4kg boxes, or a
tobacco base grade's F2F vs F2P sub-grades) is saved as its own line item,
with its quantity saved in the line item's qty (boxes, bags or kg -- the
Sales summary's box/bag counts come from it) and repeated with the average
price in its description. Pepper box sizes (5kg / 4kg) are saved as the
line's class, the same as a report typed into the app.

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

# Since the database lockdown, the public app key above can no longer read or
# write the Sales tables -- this script needs the project's SECRET key. Keep
# it only on this PC: either in the SUPABASE_SECRET_KEY environment variable
# or in scripts/supabase_secret_key.txt next to this script (that file is in
# .gitignore -- never commit it). See scripts/README.md.
SECRET_KEY_FILE = pathlib.Path(__file__).with_name("supabase_secret_key.txt")


def _api_key():
    import os

    key = os.environ.get("SUPABASE_SECRET_KEY", "").strip()
    if not key and SECRET_KEY_FILE.exists():
        key = SECRET_KEY_FILE.read_text(encoding="utf-8").strip()
    if not key:
        print(
            "WARNING: no Supabase secret key found (SUPABASE_SECRET_KEY or scripts/supabase_secret_key.txt) -- "
            "using the public key, which the locked-down database refuses.",
            file=sys.stderr,
        )
        return SUPABASE_ANON_KEY
    return key


def _auth_headers():
    key = _api_key()
    headers = {"apikey": key}
    # New-style secret keys (sb_secret_...) go in apikey only; legacy JWT
    # keys (eyJ...) and the public key also go in Authorization.
    if not key.startswith("sb_secret_"):
        headers["Authorization"] = f"Bearer {key}"
    return headers

REPORT_DB_FIELDS = [
    "category", "agent", "report_number", "report_date",
    "gross_total", "commission_before_vat", "vat", "vat_on_sales", "nett_amount",
]


class ParseError(Exception):
    pass


class AgentDocument(ParseError):
    """A market agent's other document (daily list, detail, summary,
    afrekeningstaat) -- not an account sale, but kept with them."""


class NotTracked(ParseError):
    """An invoice for a crop the farm no longer grows -- skipped quietly, not an error."""


def extract_pages(pdf_path):
    import pdfplumber

    try:
        with pdfplumber.open(pdf_path) as pdf:
            return [page.extract_text() or "" for page in pdf.pages]
    except Exception:
        # Some PDFs trip pdfplumber up ("'<' not supported between instances
        # of 'NoneType' and 'str'"): read them with pypdfium2 (comes with
        # pdfplumber) instead.
        import pypdfium2

        doc = pypdfium2.PdfDocument(pdf_path)
        try:
            return [page.get_textpage().get_text_range().replace("\r\n", "\n") for page in doc]
        finally:
            doc.close()


# ---------------------------------------------------------------------------
# RSA Markagente (Interaction Market Services Tshwane)
# ---------------------------------------------------------------------------

RSA_PEPPER_COLOUR_MAP = {"PPRE": "Red", "PPYE": "Yellow", "PPGR": "Green"}
RSA_PEPPER_SIZE_MAP = {"L": "5kg", "M": "4kg"}
RSA_BUTTERNUT_SIZE_MAP = {"L": "10kg", "M": "7kg"}
# Product codes on old invoices for crops no longer planted (not in the app).
RSA_NOT_TRACKED_CODES = {"MEWM"}


# Washed potatoes (POWK ... POTATO MONDIAL (WASHED)): size code = class
# digit + size letter ("1L"). By price on the invoices: L > Z > M > R > S > U
# (U, the smallest, at about half of S, as Baby).
RSA_POTATO_SIZE_MAP = {"L": "Large", "Z": "Large/Medium", "M": "Medium", "R": "Small/Medium", "S": "Small", "U": "Baby", "B": "Baby"}


def _classify_rsa_product(code, size_code):
    """Returns (category, subcategory, size_label) or raises ParseError."""
    if code == "POWK":
        m = re.fullmatch(r"(\d)([A-Z]+)", size_code)
        if not m or m.group(2) not in RSA_POTATO_SIZE_MAP:
            raise ParseError(f"Unknown RSA potato size code {size_code!r} — add it to RSA_POTATO_SIZE_MAP.")
        return "potatoes", RSA_POTATO_SIZE_MAP[m.group(2)], f"Class {m.group(1)}"
    if code in RSA_NOT_TRACKED_CODES:
        raise NotTracked(f"Product {code} is no longer grown and isn't tracked in the app -- skipped.")
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

        # Pepper box size (5kg/4kg) is the app's "Weight" class for peppers;
        # a potato's class (Class 1) its "Class".
        if category == "peppers":
            klass = size_label if size_label in ("5kg", "4kg") else None
        elif category == "potatoes":
            klass = size_label
        else:
            klass = None
        key = (category, subcategory, klass, size_label)
        entry = detail.setdefault(key, {"sold": 0, "value": 0.0})
        entry["sold"] += sold
        entry["value"] += value

    if not detail:
        raise ParseError("Found no product lines in this invoice.")

    return _reports_by_category(
        agent="RSA Markagente Pretoria",
        report_number=report_number_m.group(1),
        report_date=report_date,
        gross_total=float(gross_m.group(1)),
        commission_before_vat=round(commission_before_vat, 2),
        vat=round(vat, 2),
        nett_amount=float(nett_m.group(1)),
        detail=detail,
        # Peppers and butternuts in boxes, potatoes in bags.
        unit_name={"potatoes": "bags"},
    )


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
        weight = RSA_PEPPER_SIZE_MAP.get(size_code)  # L -> 5kg, M -> 4kg
        return "peppers", colour, weight, weight or size_code
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
    # Negative when only costs were charged (everything destroyed, nothing sold).
    nett_m = re.search(r"(?:Netto Bedrag|Nett Amount)\s+(-?" + NUM_DEC + r")", text)
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

    report_date = f"{date_m.group(1)}-{date_m.group(2)}-{date_m.group(3)}"
    commission_before_vat, vat = _sa_number(deductions_m.group(1)), _sa_number(deductions_m.group(2))
    nett = nett_m.group(1)
    nett_amount = -_sa_number(nett[1:]) if nett.startswith("-") else _sa_number(nett)
    gross_total = sum(d["value"] for d in detail.values())

    return _reports_by_category(
        agent=agent,
        report_number=report_number_m.group(1),
        report_date=report_date,
        gross_total=round(gross_total, 2),
        commission_before_vat=round(commission_before_vat, 2),
        vat=round(vat, 2),
        nett_amount=round(nett_amount, 2),
        detail=detail,
        unit_name="units",
    )


WENFAM_ACCOUNT_SALE_RE = re.compile(r"(?:Verkope nr|Account Sale no):")


def parse_wenfam(pages):
    reports = []
    errors = []
    for page_text in pages:
        try:
            page_reports = parse_wenfam_page(page_text)
        except ParseError as e:
            print(f"  (skipping one invoice on this PDF: {e})", file=sys.stderr)
            errors.append(str(e))
            continue
        if page_reports is not None:
            reports.extend(page_reports)
    if not reports:
        if not any(WENFAM_ACCOUNT_SALE_RE.search(p) for p in pages):
            # The agent's other documents (daily lists, detail and summary
            # pages) -- not an account sale.
            raise AgentDocument("Don't recognise this layout (a market agent's document, but not an account sale) -- skipped.")
        if errors and all("only unsupported produce" in e for e in errors):
            raise NotTracked(f"Only produce the app doesn't track: {errors[0].split(': ', 1)[-1]}")
    return reports


# ---------------------------------------------------------------------------
# Peppadew International (the buyer): a grading report per load
# ---------------------------------------------------------------------------

# Nanini's supplier numbers at Peppadew: one per colour.
PEPPADEW_SUPPLIERS = {"30ZZ608": "Red", "30ZZ718": "Yellow"}
# Both ways Peppadew writes numbers: "5 116,96" and "2,691.44" (or "1293.2").
PEP_NUM = r"\d+(?:[ \u00a0,]\d{3})*(?:[.,]\d+)?"


def _pep_number(s):
    s = re.sub(r"[ \u00a0]", "", s)
    # With a point, commas are thousands ("2,691.44"); without, the comma is the decimal ("5116,96").
    return float(s.replace(",", "") if "." in s else s.replace(",", "."))


def parse_peppadew_grading(text):
    """A load graded at Peppadew: kg and value per class (and the kg
    rejected), as a report under Peppadew -- red or yellow by the supplier number."""
    rec_m = re.search(r"RECEIVING NUMBER:\s*(GRV-\d+)", text)
    date_m = re.search(r"Date Received:\s*(?:(\d{4})/(\d{2})/(\d{2})|(\d{2})/(\d{2})/(\d{4}))", text)
    total_m = re.search(r"Total Value\s*R\s*(" + PEP_NUM + r")", text)
    if not (rec_m and date_m and total_m):
        raise ParseError("Could not find the receiving number / date / total value in this Peppadew grading report.")
    supplier_m = re.search(r"Supplier Number:\s*(\S+)", text)
    fruit_m = re.search(r"Fruit:\s*(.+?)\s+Number of Bins", text)
    colour = PEPPADEW_SUPPLIERS.get(supplier_m.group(1) if supplier_m else "")
    if colour is None:
        colour = "Yellow" if "yellow" in (fruit_m.group(1) if fruit_m else "").lower() else None
    if colour is None:
        raise ParseError(f"Unknown Peppadew supplier number {supplier_m.group(1) if supplier_m else '?'} -- add it to PEPPADEW_SUPPLIERS.")
    kg = {c: _pep_number(k) for c, k in re.findall(r"Class (\d) [\d ,.]+? ?g [\d,.]+% (" + PEP_NUM + r") ?kg", text)}
    value = {c: _pep_number(v) for c, v in re.findall(r"Class (\d) R\s*(" + PEP_NUM + r")", text)}
    total = _pep_number(total_m.group(1))
    if abs(sum(value.values()) - total) > 0.05:
        raise ParseError(f"The classes add up to R{sum(value.values()):,.2f} but the total value is R{total:,.2f}.")
    detail = {}
    for c in sorted(set(kg) | set(value)):
        if kg.get(c, 0) or value.get(c, 0):
            detail[("peppadew", colour, f"Class {c}", f"Class {c}")] = {"sold": kg.get(c, 0.0), "value": value.get(c, 0.0)}
    rejected_m = re.search(r"Total Rejected Fruit [\d ,.]+? ?g [\d,.]+% (" + PEP_NUM + r") ?kg", text)
    if rejected_m and _pep_number(rejected_m.group(1)):
        detail[("peppadew", colour, "Rejected", "Rejected")] = {"sold": _pep_number(rejected_m.group(1)), "value": 0.0}
    if not detail:
        raise ParseError(f"Grading report {rec_m.group(1)}: no classes found.")
    return [_build_report(
        category="peppadew",
        agent="Peppadew",
        report_number=rec_m.group(1),
        report_date=(f"{date_m.group(1)}-{date_m.group(2)}-{date_m.group(3)}" if date_m.group(1)
                     else f"{date_m.group(6)}-{date_m.group(5)}-{date_m.group(4)}"),
        gross_total=round(total, 2),
        commission_before_vat=0.0,
        vat=0.0,
        vat_on_sales=None,
        nett_amount=round(total, 2),
        detail=detail,
        unit_name="kg",
    )]


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
    # A class can be None next to "5kg" (a pepper line without its box size):
    # sort it as "".
    for (cat, subcat, klass, size_label), info in sorted(detail.items(), key=lambda kv: tuple(x or "" for x in kv[0])):
        sold, value = info["sold"], info["value"]
        avg = value / sold if sold else 0.0
        qty_str = f"{sold:,.2f}" if unit_name == "kg" else f"{int(sold):,}"
        prefix = f"{size_label}: " if size_label and size_label not in (subcat, klass) else ""
        description = f"{prefix}{qty_str} {unit_name} @ R{avg:.2f}/{unit_name}"
        line_items.append({
            "category": cat,
            "subcategory": subcat,
            "class": klass,
            "gross_amount": round(value, 2),
            # Boxes / bags / kg: the Sales summary counts these per subcategory.
            "qty": round(sold, 2) if unit_name == "kg" else int(sold),
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


def _reports_by_category(agent, report_number, report_date, gross_total, commission_before_vat, vat, nett_amount,
                         detail, unit_name):
    """One report per crop. An account sale with two crops on it (peppers
    and butternuts) becomes a report for each, numbered "303984 (peppers)",
    its commission, VAT and nett shared by each crop's gross (the last takes
    the cents left, so the reports add up to the account sale)."""
    categories = sorted({k[0] for k in detail})
    if isinstance(unit_name, dict):
        names = unit_name
        unit_name = None
    else:
        names = {}
    if len(categories) == 1:
        unit_name = unit_name or names.get(categories[0], "boxes")
        return [_build_report(
            category=categories[0], agent=agent, report_number=report_number, report_date=report_date,
            gross_total=gross_total, commission_before_vat=commission_before_vat, vat=vat, vat_on_sales=None,
            nett_amount=nett_amount, detail=detail, unit_name=unit_name,
        )]
    total = sum(d["value"] for d in detail.values())
    out = []
    left = {"gross": gross_total, "commission": commission_before_vat, "vat": vat, "nett": nett_amount}
    for i, cat in enumerate(categories):
        part = {k: v for k, v in detail.items() if k[0] == cat}
        share = sum(d["value"] for d in part.values()) / total if total else 0
        last = i == len(categories) - 1
        amounts = {}
        for name, whole in (("gross", gross_total), ("commission", commission_before_vat), ("vat", vat), ("nett", nett_amount)):
            amounts[name] = round(left[name], 2) if last else round(whole * share, 2)
            left[name] -= amounts[name]
        out.append(_build_report(
            category=cat, agent=agent, report_number=f"{report_number} ({cat})", report_date=report_date,
            gross_total=amounts["gross"], commission_before_vat=amounts["commission"], vat=amounts["vat"],
            vat_on_sales=None, nett_amount=amounts["nett"], detail=part, unit_name=unit_name or names.get(cat, "boxes"),
        ))
    return out


def detect_and_parse(pages):
    joined = "\n".join(pages)
    if "PEPPADEW" in joined.upper():
        if "GRADING REPORT" in joined:
            return parse_peppadew_grading(joined)
        if "FARMER PAYMENT ADVICE" in joined:
            # Peppadew's payment advice: kept (import_market_payments.py reads it).
            raise AgentDocument("Don't recognise this layout (Peppadew's payment advice, not a grading report) -- skipped.")
    if "RSA MARKAGENTE" in joined or "INTERACTION MARKET SERVICES" in joined:
        return parse_rsa(joined)
    if any(marker in joined for marker, _ in WENFAM_AGENT_MARKERS):
        reports = parse_wenfam(pages)
        if not reports:
            raise ParseError("Recognised this as a Wenpro-family invoice but couldn't extract any usable report.")
        return reports
    # The tobacco invoice has its "Date Of Sale" (a SARS report can name
    # Universal Leaf, and "ULSA" turns up inside other words).
    if ("Universal Leaf South Africa" in joined or re.search(r"\bULSA\b", joined)) and "Date Of Sale" in joined:
        return parse_tobacco_ulsa(joined)
    raise ParseError("Don't recognise this layout (not a known market-agent account sale) -- skipped.")


def report_exists(report_number):
    import requests

    resp = requests.get(
        f"{SUPABASE_URL}/rest/v1/sales_reports",
        params={"report_number": f"eq.{report_number}", "select": "id"},
        headers=_auth_headers(),
        timeout=30,
    )
    resp.raise_for_status()
    return len(resp.json()) > 0


def delete_report(report_number):
    """Deletes a report and its line items by report_number. Returns True if something was deleted."""
    import requests

    headers = _auth_headers()
    resp = requests.get(
        f"{SUPABASE_URL}/rest/v1/sales_reports",
        params={"report_number": f"eq.{report_number}", "select": "id"},
        headers=headers,
        timeout=30,
    )
    resp.raise_for_status()
    rows = resp.json()
    if not rows:
        return False
    report_id = rows[0]["id"]

    resp = requests.delete(
        f"{SUPABASE_URL}/rest/v1/sales_line_items", params={"report_id": f"eq.{report_id}"}, headers=headers, timeout=30
    )
    resp.raise_for_status()
    resp = requests.delete(
        f"{SUPABASE_URL}/rest/v1/sales_reports", params={"id": f"eq.{report_id}"}, headers=headers, timeout=30
    )
    resp.raise_for_status()
    return True


def add_missing_counts(report):
    """A report already in the database whose line items have no box/bag/kg
    count (saved without qty, e.g. "PEPR BX050 CL 1 L"): its line items are
    replaced by this parse's, which carry the counts -- only when both add up
    to the same rand, so nothing else about the report changes. Returns the
    number of lines saved, or 0 when there was nothing to fill in."""
    import requests

    headers = _auth_headers()
    resp = requests.get(
        f"{SUPABASE_URL}/rest/v1/sales_reports",
        params={"report_number": f"eq.{report['report_number']}", "select": "id"},
        headers=headers,
        timeout=30,
    )
    resp.raise_for_status()
    rows = resp.json()
    if not rows:
        return 0
    report_id = rows[0]["id"]
    resp = requests.get(
        f"{SUPABASE_URL}/rest/v1/sales_line_items",
        params={"report_id": f"eq.{report_id}", "select": "id,qty,description,gross_amount"},
        headers=headers,
        timeout=30,
    )
    resp.raise_for_status()
    saved = resp.json()
    count_in_text = re.compile(r"[0-9][0-9,]*(?:\.[0-9]+)? (?:boxes|bags|kg|units) @")
    if not saved or all(li["qty"] is not None or count_in_text.search(li["description"] or "") for li in saved):
        return 0
    saved_gross = sum(float(li["gross_amount"] or 0) for li in saved)
    parsed_gross = sum(li["gross_amount"] for li in report["line_items"])
    if abs(saved_gross - parsed_gross) > 0.05:
        print(f"  Its lines have no box count, but they add up to R{saved_gross:,.2f} and this PDF to "
              f"R{parsed_gross:,.2f} -- left as is.")
        return 0

    resp = requests.post(
        f"{SUPABASE_URL}/rest/v1/sales_line_items",
        json=[{**li, "report_id": report_id} for li in report["line_items"]],
        headers={**headers, "Content-Type": "application/json"},
        timeout=30,
    )
    resp.raise_for_status()
    old_ids = ",".join(str(li["id"]) for li in saved)
    resp = requests.delete(
        f"{SUPABASE_URL}/rest/v1/sales_line_items", params={"id": f"in.({old_ids})"}, headers=headers, timeout=30
    )
    resp.raise_for_status()
    return len(report["line_items"])


def save_report(report):
    import requests

    headers = {
        **_auth_headers(),
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


def process_pdf(pdf_path, args, totals, header):
    """Imports one PDF. Returns True when the file is fully dealt with (saved,
    already in the database, not tracked, or not a market-agent invoice at
    all) so later runs can skip it; False when it should be tried again."""
    # The agents' companion files: Wenpro-family detail (_Det) and summary
    # (_Sum) next to each account sale (_Inv), and RSA's cheque advices
    # (ACCCHEQS) -- not account sales.
    if re.search(r"_(?:Det|Sum)\.pdf$", pdf_path.name, re.IGNORECASE) or "_ACCCHEQS_" in pdf_path.name.upper():
        totals["unrecognised"] += 1
        return True
    try:
        pages = extract_pages(str(pdf_path))
        reports = detect_and_parse(pages)
    except NotTracked as e:
        print(f"{header}\n  {e}")
        totals["skipped"] += 1
        return True
    except ParseError as e:
        reason = str(e).splitlines()[0]
        if reason.startswith("Don't recognise"):
            # Bank statements, tax returns, supplier invoices... -- the
            # folder holds far more of these than account sales, so they're
            # only counted, not listed.
            totals["unrecognised"] += 1
            return True
        print(f"{header}\n  Could not parse this invoice: {e}")
        totals["failed"] += 1
        totals["failures"].append((pdf_path, reason))
        return False
    except Exception as e:  # a damaged/locked PDF shouldn't stop the whole run
        print(f"{header}\n  Could not open this PDF: {e}")
        totals["failed"] += 1
        totals["failures"].append((pdf_path, f"Could not open: {e}"))
        # Reading it again won't help: listed once, and again only when the
        # file changes (a good copy saved over it).
        return True

    print(header)
    done = True
    for i, report in enumerate(reports, 1):
        print(f"  --- Report {i} of {len(reports)} ---")
        print_report(report)

        try:
            if report_exists(report["report_number"]):
                print(f"\n  Report number {report['report_number']} is already in the database — not importing again.")
                filled = add_missing_counts(report)
                if filled:
                    print(f"  Box counts added: its line items replaced by these {filled} (same rand total).")
                    totals["counted"] += 1
                print()
                totals["skipped"] += 1
                continue

            if not args.yes:
                answer = input("\n  Save this report to the live Sales database? [y/N] ").strip().lower()
                if answer != "y":
                    print("  Not saved.\n")
                    totals["skipped"] += 1
                    done = False
                    continue

            report_id = save_report(report)
        except Exception as e:  # e.g. no internet -- try this file again next run
            print(f"\n  Could not save to the database: {e}\n")
            totals["failed"] += 1
            totals["failures"].append((pdf_path, f"Could not save: {e}"))
            done = False
            continue
        print(f"\n  Saved. Report id: {report_id}\n")
        totals["saved"] += 1
    return done


SEEN_FILE = pathlib.Path(__file__).with_name("import_seen.json")


def _file_stamp(path):
    st = path.stat()
    return f"{st.st_size}:{int(st.st_mtime)}"


def _load_seen():
    import json

    try:
        return json.loads(SEEN_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def _save_seen(seen):
    import json

    try:
        SEEN_FILE.write_text(json.dumps(seen), encoding="utf-8")
    except OSError as e:
        print(f"WARNING: could not save {SEEN_FILE.name} ({e}) -- the next run will read every PDF again.")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("path", nargs="?", help="A single invoice PDF, or a folder to scan recursively for PDFs.")
    parser.add_argument("--yes", action="store_true", help="Skip the confirmation prompt.")
    parser.add_argument("--rescan", action="store_true", help="Read every PDF again, including ones already dealt with.")
    parser.add_argument(
        "--only-folder",
        metavar="NAME",
        help="When scanning a folder, only read PDFs inside subfolders with this name (e.g. BTW), at any depth.",
    )
    parser.add_argument(
        "--delete-report",
        metavar="REPORT_NUMBER",
        help="Delete a report and its line items by report number (e.g. to fix one saved before a parser bug was "
        "corrected, then re-import it). Ignores `path`.",
    )
    args = parser.parse_args()
    # The scheduled task writes to a log file; without this, normal output is
    # held back and ends up out of order with (or missing from) the log.
    sys.stdout.reconfigure(line_buffering=True)
    sys.stderr.reconfigure(line_buffering=True)

    if args.delete_report:
        if not args.yes:
            answer = input(
                f"Permanently delete report {args.delete_report} and all its line items? [y/N] "
            ).strip().lower()
            if answer != "y":
                print("Not deleted.")
                sys.exit(0)
        deleted = delete_report(args.delete_report)
        print(f"Deleted report {args.delete_report}." if deleted else f"Report {args.delete_report} not found.")
        sys.exit(0)

    if not args.path:
        parser.error("path is required unless --delete-report is given")
    target = pathlib.Path(args.path)
    if not target.exists():
        print(
            f"PROBLEM: {target} doesn't exist. If it's on an external, USB or network drive, check that drive is "
            "connected; otherwise check the folder/file name and update run_import_task.bat."
        )
        sys.exit(1)
    if target.is_dir():
        pdf_paths = sorted(target.rglob("*.pdf"))
        if args.only_folder:
            wanted = args.only_folder.lower()
            pdf_paths = [p for p in pdf_paths if any(part.lower() == wanted for part in p.relative_to(target).parts[:-1])]
        if not pdf_paths:
            print(f"No PDFs found under {target}.")
            sys.exit(0)
    else:
        pdf_paths = [target]

    # PDFs already dealt with on an earlier run (same file, unchanged) are
    # skipped, so the daily run only reads new or changed ones. --rescan
    # reads everything again.
    use_seen = target.is_dir()
    seen = _load_seen() if use_seen and not args.rescan else {}
    totals = {"saved": 0, "counted": 0, "skipped": 0, "failed": 0, "unrecognised": 0, "unchanged": 0, "failures": []}
    for n, pdf_path in enumerate(pdf_paths, 1):
        key = str(pdf_path.resolve())
        stamp = _file_stamp(pdf_path)
        if use_seen and seen.get(key) == stamp:
            totals["unchanged"] += 1
            continue
        header = f"\n########## [{n}/{len(pdf_paths)}] {pdf_path} ##########"
        if process_pdf(pdf_path, args, totals, header):
            seen[key] = stamp
            if use_seen and n % 50 == 0:
                _save_seen(seen)
        else:
            seen.pop(key, None)
    if use_seen:
        _save_seen(seen)

    print(
        f"\nDone: {totals['saved']} saved, {totals['skipped']} already imported/skipped, "
        f"{totals['failed']} could not be read, {totals['unrecognised']} not market-agent invoices, "
        f"{totals['unchanged']} unchanged since the last run."
        + (f" Box counts added to {totals['counted']} report(s) saved without them." if totals["counted"] else "")
    )

    # Summary for the log: PDFs that ARE market-agent invoices but couldn't be
    # read need a parser fix; unrecognised ones are usually other documents
    # (statements, letters...) in the same folder and can be ignored.
    fixable = totals["failures"]
    if fixable:
        print(f"\nNEEDS A LOOK -- {len(fixable)} PDF(s) look like market-agent invoices (or are damaged) but could not be read. "
              "Send one of each kind to Claude:")
        for p, reason in fixable:
            print(f"  {p}\n      -> {reason}")


if __name__ == "__main__":
    main()
