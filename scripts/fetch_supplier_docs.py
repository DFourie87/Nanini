#!/usr/bin/env python3
"""
Brings supplier invoices, credit notes and statements that arrive by email
(Gmail) into the hub's Suppliers app, to be checked and confirmed there.

    python scripts\\fetch_supplier_docs.py
    python scripts\\fetch_supplier_docs.py --days 120      # look further back
    python scripts\\fetch_supplier_docs.py --since 2026-03-01   # everything since a date
    python scripts\\fetch_supplier_docs.py --dry-run       # show what it would do, change nothing

How it works:
  * Reads the suppliers and their email addresses from the app (the supplier's
    Email field; several addresses may be listed, separated by commas, and an
    entry like "@agri.co.za" matches anyone at that domain).
  * Reads Gmail READ-ONLY through scripts/gmail_access.py (the Google
    sign-in, or the app password -- same as fetch_gmail_invoices.py; stays
    on this PC only): nothing in Gmail is changed, moved, deleted, labelled,
    sent or even marked as read.
  * Only emails FROM a supplier's address with a PDF attached are looked at;
    every other email is skipped and nothing about it is kept.
  * Each PDF is uploaded to the app's private "supplier-docs" storage and
    added to that supplier as "From email -- to check", with what could be
    read from it filled in: invoice, credit note or statement; the date; the
    number; the total (or a statement's closing balance). Nothing counts in
    the supplier's account until someone confirms it in the app.
  * Remembers which emails it has handled (scripts/supplier_gmail_seen.json,
    only Gmail's message numbers), and the same attachment is never added
    twice.

Needs the Supabase secret key (scripts/supabase_secret_key.txt) like the
sales import, and docs/sql/suppliers.sql + suppliers_email.sql run once.
"""
import argparse
import datetime as dt
import email
import email.policy
import email.utils
import json
import pathlib
import re
import sys
import tempfile
import uuid

from gmail_access import GmailProblem, open_gmail
from import_sales_report import SUPABASE_URL, _auth_headers, extract_pages

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
SEEN_FILE = SCRIPT_DIR / "supplier_gmail_seen.json"
BUCKET = "supplier-docs"
MAX_PDF = 15 * 1024 * 1024


# ---------------------------------------------------------------------------
# Matching an email to a supplier
# ---------------------------------------------------------------------------

def supplier_addresses(email_field):
    """The addresses (and "@domain" entries) in a supplier's Email field."""
    out = []
    for part in re.split(r"[,;\s]+", email_field or ""):
        part = part.strip().strip("<>").lower()
        if "@" in part:
            out.append(part)
    return out


def match_suppliers(sender, suppliers):
    """The suppliers whose Email field lists [sender], else its domain --
    several when they share an address (Eskom's accounts, Kanaan/Oorvloed)."""
    sender = (sender or "").strip().lower()
    if "@" not in sender:
        return []
    domain = "@" + sender.split("@", 1)[1]
    exact = [s for s in suppliers if sender in s["addresses"]]
    return exact or [s for s in suppliers if domain in s["addresses"]]


def match_supplier(sender, suppliers):
    found = match_suppliers(sender, suppliers)
    return found[0] if found else None


def _squash(text):
    return re.sub(r"[\s\-]", "", text or "").lower()


def pick_supplier(candidates, text, subject="", filename=""):
    """Of suppliers sharing an address, the one this document is for: its
    account number in the PDF (or subject / file name), else its name.
    Returns (supplier, sure)."""
    if len(candidates) == 1:
        return candidates[0], True
    hay = f"{text}\n{subject}\n{filename}"
    squashed = _squash(hay)
    by_account = []
    for c in candidates:
        acc = _squash(str(c.get("account_no") or ""))
        if not acc:
            continue
        # Long numbers can be found even when printed with spaces; short ones
        # (e.g. "302") only as a whole word.
        if (len(acc) >= 6 and acc in squashed) or re.search(rf"(?<![\w]){re.escape(acc)}(?![\w])", hay.lower()):
            by_account.append(c)
    accounts = {_squash(str(c.get("account_no") or "")) for c in by_account}
    if len(accounts) == 1 and len(by_account) == 1:
        return by_account[0], True
    pool = by_account or candidates
    by_name = [c for c in pool if c["name"].lower() in hay.lower()]
    if len(by_name) == 1:
        return by_name[0], True
    return (by_name or pool)[0], False


def gmail_query(suppliers, days, since=None):
    terms = sorted({a.lstrip("@") for s in suppliers for a in s["addresses"]})
    when = f"after:{since:%Y/%m/%d}" if since else f"newer_than:{days}d"
    return f'"has:attachment filename:pdf {when} from:({" OR ".join(terms)})"'


# ---------------------------------------------------------------------------
# Reading the PDF: what it is, its date, number and amount
# ---------------------------------------------------------------------------

MONTHS = {m: i for i, m in enumerate(
    ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"], start=1)}
MONTHS.update({"mei": 5, "okt": 10, "des": 12, "mrt": 3})  # Afrikaans

# A money amount: "R 12 345.67", "12,345.67", "12 345,67", "-1 200.00", "1200.00".
MONEY_RE = re.compile(r"-?\s?R?\s?(?:\d{1,3}(?:[ , .]\d{3})+|\d+)[.,]\d{2}(?!\d)")


def parse_money(text):
    """'R 12 345,67' -> 12345.67 (the last two digits are always the cents)."""
    neg = text.strip().startswith("-") or text.strip().endswith("-")
    digits = re.sub(r"[^\d]", "", text)
    if len(digits) < 3:
        return None
    value = int(digits) / 100
    return -value if neg else value


def amounts_in(line):
    return [v for v in (parse_money(m.group(0)) for m in MONEY_RE.finditer(line)) if v is not None]


# Attachments that aren't invoices or statements (e.g. the leaflet Eskom
# sends with every bill): skipped.
# VKB's "..._AANW_..." is an apportionment statement (shares), not the account.
# Eskom also sends leaflets and IT3(b) interest certificates.
IGNORE_NAMES = re.compile(r"supplementary\s*information|terms\s*(and|&)\s*conditions|newsletter|brochure|price\s*list|tariff"
                          r"|apportionment|(^|[_\W])aanw([_\W]|$)"
                          # Eskom: "Connect 2026" / rooftop solar leaflets, IT3(b) tax certificates
                          r"|(^|[_\W])connect([_\W\d]|$)|rooftop\s*solar|(^|[_\W])it3\s*\(?b", re.I)

# The file name often says what it is (Omnia: "..._ci_..." invoice,
# "..._st_..." statement; "Staat" = statement).
NAME_INVOICE = re.compile(r"(^|[_\W])(ci|inv|invoice|tax\s*invoice|faktuur)([_\W\d]|$)", re.I)
NAME_STATEMENT = re.compile(r"(^|[_\W])(st|stmt|statement|staat)([_\W\d]|$)", re.I)
NAME_CREDIT = re.compile(r"(^|[_\W])(cn|credit\s*note|kredietnota)([_\W\d]|$)", re.I)


def guess_kind(text, subject="", filename=""):
    if NAME_CREDIT.search(filename or ""):
        return "credit_note"
    if NAME_INVOICE.search(filename or ""):
        return "invoice"
    if NAME_STATEMENT.search(filename or ""):
        return "statement"
    t = f"{subject}\n{filename}\n{text[:3000]}".lower()
    if "statement" in t or "staat" in t or "state of account" in t:
        return "statement"
    if "credit note" in t or "credit memo" in t or "kredietnota" in t:
        return "credit_note"
    return "invoice"


# Labels whose line holds the amount, best first.
STATEMENT_LABELS = ["totaldue", "closing balance", "balance due", "amount due", "total due", "total outstanding",
                    "amount payable", "balance owing", "outstanding balance",
                    # Afrikaans (VKB: "TOTALE BALANS VERSKULDIG ...")
                    "balans verskuldig", "bedrag verskuldig", "totaal verskuldig", "uitstaande balans", "balance"]
# "totaldue": Eskom's bills for the bigger accounts run the words together.
INVOICE_LABELS = ["totaldue", "total due", "amount due", "invoice total", "grand total", "total incl", "total (incl",
                  "balance due", "amount payable", "total",
                  # Afrikaans (VKB: "TOTAAL : 1000.87", not "SUBTOTAAL")
                  "bedrag verskuldig", "totaal"]


def guess_amount(text, kind):
    labels = STATEMENT_LABELS if kind == "statement" else INVOICE_LABELS
    lines = text.splitlines()
    for label in labels:
        found = None
        for line in lines:
            low = line.lower()
            plain_total = label in ("total", "totaal")
            if label in low and not (plain_total and ("sub" in low or "vat" in low or "btw" in low)):
                vals = amounts_in(line[low.index(label):])
                if vals:
                    found = vals[-1]  # the last such line: totals are at the bottom
        if found is not None:
            return round(found, 2)
    if kind == "statement":
        return _age_analysis_total(lines)
    return None


AGE_COLUMNS = re.compile(r"\b(current|not due|30 days|60 days|90 days|120 days)\b", re.I)


def _age_analysis_total(lines):
    """The Total of the age analysis (Omnia: "Total  Not due  Current  30 days ..."
    with the amounts on the next line; others put Total last)."""
    for i, line in enumerate(lines):
        # Only the headings: another box can sit on the same line
        # ("... 150+ days Settlement discount 0,00").
        m = MONEY_RE.search(line)
        words = (line[:m.start()] if m else line).strip().lower()
        if len(AGE_COLUMNS.findall(words)) < 2:
            continue
        at_start, at_end = words.startswith("total"), words.endswith("total")
        if not (at_start or at_end):
            continue
        for nxt in lines[i + 1:i + 3]:
            vals = amounts_in(nxt)
            if len(vals) >= 2:
                return round(vals[0] if at_start else vals[-1], 2)
    return None


DATE_PATTERNS = [
    (re.compile(r"\b(20\d{2})[-/.](\d{1,2})[-/.](\d{1,2})\b"), "ymd"),
    (re.compile(r"\b(\d{1,2})[-/.](\d{1,2})[-/.](20\d{2})\b"), "dmy"),
    (re.compile(r"\b(\d{1,2})[\s-]+([A-Za-z]{3,9})[,\s-]+(20\d{2})\b"), "d mon y"),
    (re.compile(r"\b([A-Za-z]{3,9})\s+(\d{1,2}),?\s+(20\d{2})\b"), "mon d y"),
]


def _date_in(line):
    for rx, form in DATE_PATTERNS:
        for m in rx.finditer(line):
            try:
                if form == "ymd":
                    y, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
                elif form == "dmy":
                    d, mo, y = int(m.group(1)), int(m.group(2)), int(m.group(3))
                elif form == "d mon y":
                    d, mo, y = int(m.group(1)), MONTHS.get(m.group(2)[:3].lower()), int(m.group(3))
                else:
                    mo, d, y = MONTHS.get(m.group(1)[:3].lower()), int(m.group(2)), int(m.group(3))
                if mo:
                    return dt.date(y, mo, d)
            except ValueError:
                continue
    return None


COMPACT_DATE = re.compile(r"\b(20\d{2})(\d{2})(\d{2})\b")


def _compact_date_in(line):
    for m in COMPACT_DATE.finditer(line):
        try:
            return dt.date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        except ValueError:
            continue
    return None


def guess_date(text, kind):
    labels = (["statement date", "date of statement", "staatdatum", "as at", "period ending"] if kind == "statement" else
              ["invoice date", "tax invoice date", "credit note date", "date of invoice", "document date"]) + ["date"]
    lines = text.splitlines()
    for label in labels:
        for line in lines:
            low = line.lower()
            if label in low and "due date" not in low:
                d = _date_in(line[low.index(label):])
                if d:
                    return d
    # VKB: "STAATDATUM" with the date ("20260831") on the line below.
    for i, line in enumerate(lines[:-1]):
        if "staatdatum" in line.lower():
            d = _date_in(lines[i + 1]) or _compact_date_in(lines[i + 1])
            if d:
                return d
    for line in lines[:40]:
        d = _date_in(line)
        if d:
            return d
    # VKB invoices: only "20260928" near the top.
    for line in lines[:15]:
        d = _compact_date_in(line)
        if d:
            return d
    return None


REF_RE = re.compile(
    r"(?:tax\s+invoice|invoice|credit\s+note|document)\s*(?:no\.?|number|num|nr\.?|#)\s*[:.\-]?\s*([A-Z0-9][A-Z0-9\-/]{2,})",
    re.IGNORECASE,
)


DUE_LABELS = ["currentduedate", "current due date", "payment due date", "due date", "payment due", "pay by", "due by", "please pay before"]


def guess_due_date(text):
    """The due date printed on the document, if any (e.g. Eskom's "CURRENT
    DUE DATE" -- not the previous bill's, on the "brought forward" line)."""
    lines = [line for line in text.splitlines() if "brought forward" not in line.lower()]
    for label in DUE_LABELS:
        for line in lines:
            low = line.lower()
            if label in low:
                d = _date_in(line[low.index(label):])
                if d:
                    return d
    return None


def _carries_account(text):
    low = text.lower()
    return "brought forward" in low and ("amount due" in low or "total due" in low or "totaldue" in low)


def _brought_forward_unpaid(text):
    """On a bill that carries the account (Eskom): the previous balance
    brought forward less the payments received since -- already owed on the
    previous bill, so not part of this one's amount."""
    bf, paid = None, 0.0
    for line in text.splitlines():
        low = line.lower()
        if "brought forward" in low:
            vals = amounts_in(line[low.index("brought forward"):])
            if vals:
                bf = vals[-1]
        elif "payment" in low and "received" in low:
            vals = amounts_in(line)
            if vals:
                paid += -abs(vals[-1])
    return 0.0 if bf is None else round(bf + paid, 2)


def guess_statement_due(text):
    """On a statement: (what's already due, the date the current part is due).
    VKB: "30 DAE 6 454.81 REEDS BETAALBAAR" lines and "HUIDIG 12 936.91 30/09/2026"."""
    overdue, due = None, None
    for line in text.splitlines():
        low = line.lower()
        if "reeds betaalbaar" in low or "already due" in low:
            vals = amounts_in(line[:low.index("reeds betaalbaar" if "reeds betaalbaar" in low else "already due")])
            if vals:
                overdue = round((overdue or 0) + vals[-1], 2)
        elif due is None and re.search(r"\b(huidig|current)\b", low) and amounts_in(line):
            due = _date_in(line)
    return overdue, due


# A file named after the document number (VKB: "PBAH199617.pdf").
NAME_REF = re.compile(r"^[A-Z]{2,6}-?\d{4,}$")


def guess_reference(text, kind, subject="", filename=""):
    if kind == "statement":
        return None
    for src in (text, subject):
        m = REF_RE.search(src or "")
        if m:
            return m.group(1).strip()
    stem = pathlib.Path(filename or "").stem.strip()
    return stem if NAME_REF.match(stem) else None


def read_pdf(data):
    """The PDF's text, or '' if it can't be read (scanned image, damaged)."""
    with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as tmp:
        tmp.write(data)
        path = pathlib.Path(tmp.name)
    try:
        return "\n".join(extract_pages(str(path)))
    except Exception:
        return ""
    finally:
        path.unlink(missing_ok=True)


def guess_notice(text):
    """A warning, not an invoice (Eskom's "NOTICE OF DISCONNECTION FOR
    NON-PAYMENT"): what it says, to show in the app."""
    low = text.lower()
    if "notice of disconnection" not in low and "disconnection notice" not in low:
        return None
    overdue = None
    i = low.find("overdue amount")
    if i >= 0:
        vals = amounts_in(text[i:i + 120])
        overdue = vals[0] if vals else None
    by = None
    m = re.search(r"\bby\s+(2\s?0\s?\d\s?\d-\d{2}-\d{2})", text, re.I)
    if m:
        by = _date_in(m.group(1).replace(" ", ""))
    return " ".join(x for x in [
        "DISCONNECTION NOTICE for non-payment:",
        f"R{overdue:,.2f} overdue" if overdue is not None else "an overdue amount",
        f"-- to be paid by {by.isoformat()}, or the supply is cut." if by else "-- the supply will be cut.",
        "Not an invoice: check it's paid, then Remove it here.",
    ])


VAT_WORDS = re.compile(r"\b(vat|btw)\b", re.I)
VAT_SKIP = re.compile(r"\b(reg|no|nr|number|nommer|incl|excl|inclusive|exclusive|total|totaal|subtotal|subtotaal)\b", re.I)


TAX_TOTAL = re.compile(r"^\s*(?:total\s+)?tax\s*:?\s*R?\s*(-?\d[\d ,]*\.\d{2})\s*$", re.I)


def guess_vat(text, amount):
    """The VAT on the document ("VAT 15% R 727.50", "(PLUS) BTW : 110.99",
    Eskom's "VAT RAISED ON ITEMS AT 15% R 2,383.96", Sage's "Tax 3,060.00"),
    if it fits the amount."""
    vat = None
    for line in text.splitlines():
        low = line.lower()
        t = TAX_TOTAL.match(line)
        if t:
            vat = parse_money(t.group(1))
            continue
        m = VAT_WORDS.search(low)
        if not m or (VAT_SKIP.search(low) and "vat raised" not in low and "total vat" not in low):
            continue
        vals = [v for v in amounts_in(line[m.start():]) if v >= 0]
        if vals:
            vat = vals[-1]
    if vat is None or amount is None or not (0 <= vat <= abs(amount) * 0.2 + 0.05):
        return None
    return round(vat, 2)


def guess_adjustments(text):
    """Eskom: the bill's adjustments, e.g. "ADJUSTMENT Interest on overdue
    account R 14.23": [(description, amount)] (no VAT on them)."""
    out = []
    for line in text.splitlines():
        m = re.match(r"^\s*adjustment\s+(.+?)\s+R?\s*(-?\s?[\d ,]+\.\d{2})\s*$", line, re.I)
        if m:
            out.append((m.group(1).strip(), parse_money(m.group(2))))
    return out


def guess_charges(text):
    """Eskom: this bill's charges incl. VAT (charges for the period +
    adjustments such as interest + VAT)."""
    charges = vat = None
    for line in text.splitlines():
        low = line.lower()
        if "total charges for billing period" in low:
            vals = amounts_in(line[low.index("period"):])
            charges = vals[-1] if vals else charges
        elif "vat raised" in low:
            vals = [v for v in amounts_in(line[low.index("vat raised"):]) if v >= 0]
            vat = vals[-1] if vals else vat
    if charges is None:
        return None
    return round(charges + (vat or 0) + sum(a for _, a in guess_adjustments(text)), 2)


def guess_bill_summary(text):
    """Eskom's account summary: the balance brought forward when the bill was
    made out, and the payments received since ([{date, amount}])."""
    bf, paid = None, []
    for line in text.splitlines():
        low = line.lower()
        if "brought forward" in low:
            vals = amounts_in(line[low.index("brought forward"):])
            if vals:
                bf = round(vals[-1], 2)
        elif "payment" in low and "received" in low:
            vals = amounts_in(line)
            day = _date_in(line)
            if vals:
                paid.append({"date": day.isoformat() if day else None, "amount": round(abs(vals[-1]), 2)})
    return bf, paid


# Eskom's charge lines, e.g.
#   "Energy Charge 3,144 kWh @ R2.429 /kWh R 7,636.78"
#   "Service and Administration Charge @ R26.65 per day for 29 days R 772.85"
#   "Network Capacity Charge 200 kVA @ R56.60 : = R56.60/kVA R 11,320.00"
BILL_CHARGE = re.compile(
    r"^\s*(?P<desc>[A-Za-z][A-Za-z .()&/-]*?)\s+(?:(?P<qty>[\d,]+(?:\.\d+)?)\s*(?P<unit>kwh|kva|kvarh)\s+)?"
    r"@\s*R\s*(?P<rate>[\d.]+)(?P<rest>.*?)\s*R\s*(?P<amount>-?[\d,]+\.\d{2})\s*$", re.I)


def guess_bill_details(text):
    """Eskom: the usage (kWh) and fixed (per day / per kVA) charges of the
    bill, the kWh used, the days and the reading period -- or None."""
    charges = []
    for line in text.splitlines():
        m = BILL_CHARGE.match(line)
        if not m:
            continue
        rest = m.group("rest")
        days = re.search(r"per day for (\d+) days", rest, re.I)
        unit = (m.group("unit") or "").lower()
        if days:
            kind, unit = "fixed", "day"
        elif unit == "kva":
            kind, unit = "fixed", "kVA"
        elif unit in ("kwh", "kvarh"):
            kind, unit = "usage", "kWh" if unit == "kwh" else "kvarh"
        else:
            continue
        charges.append({
            "description": " ".join(m.group("desc").split()),
            "kind": kind,
            "quantity": float(m.group("qty").replace(",", "")) if m.group("qty") else None,
            "unit": unit,
            "rate": float(m.group("rate").rstrip(".")),
            "days": int(days.group(1)) if days else None,
            "amount": parse_money(m.group("amount")),
        })
    if not charges:
        return None
    kwh = days = start = end = None
    for line in text.splitlines():
        low = line.lower()
        if ("total energy consumed" in low or "energy consumption all" in low) and kwh is None:
            vals = re.findall(r"[\d,]+\.\d+", line)
            kwh = float(vals[-1].replace(",", "")) if vals else None
        m = re.search(r"no of days:\s*(\d+)", low)
        if m:
            days = int(m.group(1))
        m = re.search(r"(?:reading dates:|consumption details \()\s*(20\d{2})[/-](\d{2})[/-](\d{2})\s*-\s*(20\d{2})[/-](\d{2})[/-](\d{2})", low)
        if m:
            start, end = "-".join(m.group(1, 2, 3)), "-".join(m.group(4, 5, 6))
    if kwh is None:
        kwh = max((c["quantity"] or 0 for c in charges if c["unit"] == "kWh"), default=None) or None
    if days is None:
        days = next((c["days"] for c in charges if c["days"]), None)
    if days is None and start and end:
        days = (dt.date.fromisoformat(end) - dt.date.fromisoformat(start)).days
    return {"kwh": kwh, "days": days, "from": start, "to": end, "charges": charges}


def guess_description(text, filename=""):
    """A few words on what was bought (shown in the purchases report)."""
    low = text.lower()
    m = re.search(r"account\s*month\s+([a-z]+\s+20\d{2})", low)
    if m and "eskom" in low:
        return f"Electricity {m.group(1).title()}"
    # VKB: its items
    items = [i["description"] for i in item_lines(text)]
    if items:
        more = f" +{len(items) - 3} more" if len(items) > 3 else ""
        return ", ".join(items[:3]) + more
    return None


VKB_ITEM = re.compile(r"^\s*(\d{1,7})\s+(.+?)\s+((?:-?\d+\.\d+-?\s+){6}-?\d+\.\d+-?)\s*$")


def _num(token):
    neg = token.startswith("-") or token.endswith("-")
    v = float(token.strip("-"))
    return -v if neg else v


def item_lines(text):
    """VKB's item table: code, description, qty, price, gross, disc%, net,
    VAT, total -- the description may go on below, before "KOSPRYS"."""
    lines = text.splitlines()
    items = []
    for i, line in enumerate(lines):
        m = VKB_ITEM.match(line)
        if not m:
            continue
        nums = [_num(t) for t in m.group(3).split()]
        desc = m.group(2).strip()
        if i + 1 < len(lines) and not VKB_ITEM.match(lines[i + 1]):
            more = re.split(r"\bKOSPRYS\b", lines[i + 1], flags=re.I)[0].strip()
            if more and "kospr" in lines[i + 1].lower():
                desc = f"{desc} {more}"
        items.append({"description": desc, "quantity": nums[0], "excl_amount": round(nums[4], 2), "vat_amount": round(nums[5], 2)})
    return items


# Sage invoices (Oorvloed, Kanaan): "code description ... tax nett", e.g.
# "1000028 04/06 HFC950L na Pta 3,060.00 20,400.00".
SAGE_ITEM = re.compile(r"^\s*(\d{4,8})\s+(.+?)\s+(-?\d{1,3}(?:,\d{3})*\.\d{2})\s+(-?\d{1,3}(?:,\d{3})*\.\d{2})\s*$")


def sage_lines(text):
    out = []
    for line in text.splitlines():
        m = SAGE_ITEM.match(line)
        if m:
            tax, nett = (float(x.replace(",", "")) for x in m.group(3, 4))
            out.append({"description": m.group(2).strip(), "quantity": None, "excl_amount": round(nett, 2), "vat_amount": round(tax, 2)})
    return out


# Omnia: "... UOM qty unit-price gross(excl) VAT net(incl)", e.g.
# "OOK/K6970 POTASSIUM SULPHATE GRAN 50KG Factored Goods TN 2.000 15,622.00 31,244.00 0.00 31,244.00".
OMNIA_ITEM = re.compile(r"^\s*(.+?)\s+(\d+\.\d{3})\s+([\d,]+\.\d{2})\s+(-?[\d,]+\.\d{2})\s+(-?[\d,]+\.\d{2})\s+(-?[\d,]+\.\d{2})\s*$")


def omnia_lines(text):
    out = []
    for line in text.splitlines():
        m = OMNIA_ITEM.match(line)
        if not m:
            continue
        words = m.group(1).split()
        if words and "/" in words[0]:
            words = words[1:]  # the product code
        if words and re.fullmatch(r"[A-Z]{1,3}", words[-1]):
            words = words[:-1]  # the unit (TN, EA)
        gross, vat, net = (float(x.replace(",", "")) for x in m.group(4, 5, 6))
        if abs(gross + vat - net) > 0.05:
            continue
        out.append({"description": " ".join(words), "quantity": float(m.group(2)), "excl_amount": round(gross, 2), "vat_amount": round(vat, 2)})
    return out


def guess_lines(text, kind, amount, details):
    """The document's lines for the purchases report, each to go against a GL
    account: [{description, quantity, excl_amount, vat_amount}], adding up to
    the document (negative on a credit note). VKB: its items; Eskom: the
    bill's charges; others: the whole document as one line."""
    if kind == "statement":
        p = details.get("purchases_amount")
        if p is None:
            return []
        vat = details.get("vat_amount") or 0
        adjustments = guess_adjustments(text)
        return [{"description": details.get("description") or "Charges", "quantity": None,
                 "excl_amount": round(p - vat - sum(a for _, a in adjustments), 2), "vat_amount": vat}] + [
            {"description": d, "quantity": None, "excl_amount": a, "vat_amount": 0.0} for d, a in adjustments]
    if amount is None:
        return []
    sign = -1 if kind == "credit_note" else 1
    items = item_lines(text) or sage_lines(text) or omnia_lines(text)
    if items and abs(sum(i["excl_amount"] + i["vat_amount"] for i in items) - abs(amount)) < 1.0:
        return [dict(i, excl_amount=sign * abs(i["excl_amount"]), vat_amount=sign * abs(i["vat_amount"])) for i in items]
    vat = details.get("vat_amount")
    return [{"description": details.get("description"), "quantity": None,
             "excl_amount": round(sign * (abs(amount) - (vat or 0)), 2), "vat_amount": None if vat is None else sign * vat}]


def guess_details(text, kind, amount, filename=""):
    """VAT, purchases (incl. VAT) and a description for the purchases report."""
    purchases = guess_charges(text) if kind == "statement" else None
    vat = guess_vat(text, purchases if purchases is not None else amount)
    if kind == "statement" and purchases is None:
        vat = None  # an ordinary statement: its purchases are on the invoices
    out = {"vat_amount": vat, "purchases_amount": purchases, "description": guess_description(text, filename)}
    if purchases is not None:
        bf, paid = guess_bill_summary(text)
        out.update(brought_forward=bf, payments_received=paid or None, bill_details=guess_bill_details(text))
    return out


def _iso(d):
    return d.isoformat() if d else None


def guess_all(text, subject, filename, sent):
    kind = guess_kind(text, subject, filename)
    date = guess_date(text, kind) or sent
    overdue = None
    if kind == "statement":
        overdue, due = guess_statement_due(text)
    else:
        due = None if kind == "credit_note" else guess_due_date(text)
    if due and due < date:
        due = None  # a due date before the document's date was misread: the terms decide
    amount = guess_amount(text, kind)
    if kind == "credit_note" and amount is not None:
        amount = abs(amount)  # printed as "1 000.87-" on some
    reference = guess_reference(text, kind, subject, filename)
    if kind == "invoice" and amount is not None and _carries_account(text):
        # Eskom: each bill carries the account (brought forward, payments,
        # this month, total due) -- it's a statement: the latest one is
        # what's owed, its arrears already due, the rest by the due date.
        kind = "statement"
        unpaid = _brought_forward_unpaid(text)
        overdue = unpaid if 0.005 < unpaid <= amount else None
    g = {
        "kind": kind,
        "doc_date": date.isoformat(),
        "amount": amount,
        "reference": reference,
        "due_date": _iso(due),
    }
    if overdue is not None:
        g["overdue_amount"] = overdue
    notice = guess_notice(text)
    if notice:
        g.update(amount=None, reference=None, due_date=None, notice=notice)
    return g


def guess_full(text, subject, filename, sent):
    """guess_all plus the purchases-report details (only those found)."""
    g = guess_all(text, subject, filename, sent)
    if not g.get("notice"):
        details = guess_details(text, g["kind"], g["amount"], filename)
        g["lines"] = guess_lines(text, g["kind"], g["amount"], details)
        _vat_from_lines(details, g["lines"])
        g.update({k: v for k, v in details.items() if v is not None})
    return g


def _vat_from_lines(details, lines):
    """No VAT total read (Omnia): the lines' VAT."""
    if details.get("vat_amount") is None and lines and all(l["vat_amount"] is not None for l in lines):
        details["vat_amount"] = round(abs(sum(l["vat_amount"] for l in lines)), 2)


# ---------------------------------------------------------------------------
# The app (Supabase): suppliers, upload, add "to check"
# ---------------------------------------------------------------------------

# Columns added by later SQL files (sent only when there's a value).
NEWER_COLUMNS = ("overdue_amount", "vat_amount", "purchases_amount", "description", "brought_forward", "payments_received", "bill_details")


class App:
    def __init__(self, dry_run=False):
        import requests

        self.requests = requests
        self.headers = _auth_headers()
        self.dry_run = dry_run

    def suppliers(self):
        r = self.requests.get(f"{SUPABASE_URL}/rest/v1/suppliers", params={"select": "id,name,email,account_no"},
                              headers=self.headers, timeout=30)
        r.raise_for_status()
        return [dict(s, addresses=supplier_addresses(s.get("email"))) for s in r.json()]

    def already_added(self, key):
        r = self.requests.get(f"{SUPABASE_URL}/rest/v1/supplier_docs", params={"select": "id", "email_key": f"eq.{key}"},
                              headers=self.headers, timeout=30)
        r.raise_for_status()
        return bool(r.json())

    def add(self, supplier, pdf, filename, guess, sender, subject, sent, key, note=None):
        if self.dry_run:
            return
        path = f"{supplier['id']}/{uuid.uuid4()}.pdf"
        r = self.requests.post(f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{path}", data=pdf,
                               headers={**self.headers, "Content-Type": "application/pdf", "x-upsert": "false"}, timeout=120)
        r.raise_for_status()
        row = {
            "supplier_id": supplier["id"],
            "kind": guess["kind"],
            "doc_date": guess["doc_date"],
            "amount": guess["amount"] or 0,
            "reference": guess["reference"],
            "file_path": path,
            "file_name": filename,
            "status": "to_check",
            "email_from": sender,
            "email_subject": (subject or "")[:300],
            "email_date": sent.isoformat(),
            "email_key": key,
            "due_date": guess.get("due_date"),
            **{k: guess[k] for k in NEWER_COLUMNS if guess.get(k) is not None},
            "notes": " ".join(n for n in [
                guess.get("notice"),
                note,
                None if guess["amount"] is not None or guess.get("notice") else "Amount not found in the PDF -- type it in.",
            ] if n) or None,
        }
        r = self.requests.post(f"{SUPABASE_URL}/rest/v1/supplier_docs", json=row,
                               headers={**self.headers, "Prefer": "return=representation"}, timeout=30)
        if r.status_code == 400 and any(k in row for k in NEWER_COLUMNS):
            # The newer columns' SQL not run yet: add it without them.
            for k in NEWER_COLUMNS:
                row.pop(k, None)
            r = self.requests.post(f"{SUPABASE_URL}/rest/v1/supplier_docs", json=row,
                                   headers={**self.headers, "Prefer": "return=representation"}, timeout=30)
        if not r.ok:
            # Not added: don't leave the PDF behind.
            self.requests.delete(f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{path}", headers=self.headers, timeout=30)
            if r.status_code == 409:
                return  # already there (another run)
            r.raise_for_status()
        try:
            self.add_lines(r.json()[0]["id"], guess.get("lines") or [])
        except RuntimeError as e:
            print(f"  NOTE: {filename} added, but {e} -- fill them in later with --fill-details.")

    def add_lines(self, doc_id, lines):
        """The document's lines for the purchases report (needs
        docs/sql/suppliers_purchases.sql; skipped quietly before that)."""
        if not lines or self.dry_run:
            return
        rows = [{"doc_id": doc_id, "line_no": n + 1, **line} for n, line in enumerate(lines)]
        r = self.requests.post(f"{SUPABASE_URL}/rest/v1/supplier_doc_lines", params={"on_conflict": "doc_id,line_no"}, json=rows,
                               headers={**self.headers, "Prefer": "return=minimal,resolution=ignore-duplicates"}, timeout=30)
        if not r.ok:
            raise RuntimeError(f"the invoice lines weren't saved ({r.status_code}: {r.text[:300]})")

    def docs_without_lines(self):
        """Documents with a PDF but no lines yet (to fill in from the PDF)."""
        r = self.requests.get(f"{SUPABASE_URL}/rest/v1/supplier_docs",
                              params={"select": "id,supplier_id,kind,amount,doc_date,reference,file_path,file_name,notes,vat_amount,description",
                                      "file_path": "not.is.null"}, headers=self.headers, timeout=60)
        r.raise_for_status()
        docs = r.json()
        have = set()
        for offset in range(0, 10_000_000, 1000):  # all of them, 1000 at a time
            r = self.requests.get(f"{SUPABASE_URL}/rest/v1/supplier_doc_lines",
                                  params={"select": "doc_id", "order": "id", "limit": 1000, "offset": offset}, headers=self.headers, timeout=60)
            r.raise_for_status()
            have |= {x["doc_id"] for x in r.json()}
            if len(r.json()) < 1000:
                break
        return [d for d in docs if d["id"] not in have]

    def docs_of(self, name_start):
        """All documents with a PDF of the suppliers whose name starts so
        (e.g. "Eskom - 8441635490"), to read again."""
        r = self.requests.get(f"{SUPABASE_URL}/rest/v1/suppliers", params={"select": "id", "name": f"ilike.{name_start}*"},
                              headers=self.headers, timeout=30)
        r.raise_for_status()
        ids = [x["id"] for x in r.json()]
        if not ids:
            return []
        r = self.requests.get(f"{SUPABASE_URL}/rest/v1/supplier_docs",
                              params={"select": "id,supplier_id,kind,amount,doc_date,reference,file_path,file_name,notes,email_date,email_subject,vat_amount,description",
                                      "file_path": "not.is.null", "supplier_id": f"in.({','.join(ids)})"}, headers=self.headers, timeout=60)
        r.raise_for_status()
        return r.json()

    def clear_lines(self, doc_id):
        if self.dry_run:
            return
        r = self.requests.delete(f"{SUPABASE_URL}/rest/v1/supplier_doc_lines", params={"doc_id": f"eq.{doc_id}"}, headers=self.headers, timeout=30)
        r.raise_for_status()

    def download(self, path):
        r = self.requests.get(f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{path}", headers=self.headers, timeout=120)
        r.raise_for_status()
        return r.content

    def update_doc(self, doc_id, fields):
        if self.dry_run or not fields:
            return
        r = self.requests.patch(f"{SUPABASE_URL}/rest/v1/supplier_docs", params={"id": f"eq.{doc_id}"}, json=fields,
                                headers={**self.headers, "Prefer": "return=minimal"}, timeout=30)
        r.raise_for_status()


def fill_details(app, log=print, reread=None):
    """Reads the VAT, purchases, description and lines of the documents
    already in the app from their PDFs (as checked: kind and amount as
    confirmed). [reread]: all documents of the suppliers whose name starts
    so are read again in full -- amount, what's already due, due date and
    lines too (after a fix in reading their layout). Returns (filled, skipped)."""
    filled = skipped = 0
    for d in (app.docs_of(reread) if reread else app.docs_without_lines()):
        if "NOTICE" in (d.get("notes") or "") or not d.get("amount"):
            skipped += 1
            continue
        try:
            text = read_pdf(app.download(d["file_path"]))
        except Exception as e:
            log(f"  PROBLEM reading {d.get('file_name')}: {e}")
            skipped += 1
            continue
        amount = float(d["amount"])
        fields = {}
        if reread:
            try:
                sent = dt.date.fromisoformat(d.get("email_date") or d["doc_date"])
            except ValueError:
                sent = dt.date.today()
            g = guess_all(text, d.get("email_subject") or "", d.get("file_name") or "", sent)
            if g["kind"] == d["kind"] and g["amount"] is not None and not g.get("notice"):
                amount = g["amount"]
                fields = {"amount": amount, "due_date": g["due_date"], "doc_date": g["doc_date"]}
                if d["kind"] == "statement":
                    fields["overdue_amount"] = g.get("overdue_amount")
        details = guess_details(text, d["kind"], amount, d.get("file_name") or "")
        lines = guess_lines(text, d["kind"], amount, details)
        _vat_from_lines(details, lines)
        if not lines and not fields:
            skipped += 1
            continue
        fields.update({k: v for k, v in details.items() if v is not None and (reread or d.get(k) is None)})
        app.update_doc(d["id"], fields)
        if reread:
            app.clear_lines(d["id"])
        app.add_lines(d["id"], lines)
        if reread and "amount" in fields and abs(fields["amount"] - float(d["amount"])) >= 0.01:
            log(f"  {d['doc_date']} {d.get('reference') or d.get('file_name')}: amount R{float(d['amount']):,.2f} -> R{fields['amount']:,.2f}")
        vat = sum(l["vat_amount"] or 0 for l in lines)
        log(f"  {d['doc_date']} {d.get('reference') or d.get('file_name')}: {len(lines)} line(s), VAT R{vat:,.2f}")
        filled += 1
    return filled, skipped


def process_message(raw, msg_id, suppliers, app, log=print):
    """Adds the PDFs of one email from a supplier. Returns how many were added."""
    msg = email.message_from_bytes(raw, policy=email.policy.default)
    sender = email.utils.parseaddr(msg.get("From", ""))[1]
    candidates = match_suppliers(sender, suppliers)
    if not candidates:
        return 0  # not from a supplier: nothing kept
    try:
        sent = email.utils.parsedate_to_datetime(msg["Date"]).date()
    except (TypeError, ValueError):
        sent = dt.date.today()
    subject = str(msg.get("Subject", "") or "")
    added = 0
    for n, part in enumerate(msg.iter_attachments()):
        name = part.get_filename() or f"document-{n + 1}.pdf"
        if part.get_content_type() != "application/pdf" and not name.lower().endswith(".pdf"):
            continue
        if IGNORE_NAMES.search(name):
            continue  # a leaflet, not an invoice or statement
        pdf = part.get_payload(decode=True) or b""
        if not pdf.startswith(b"%PDF") or len(pdf) > MAX_PDF:
            log(f"  Skipped {name} from {sender} (not a PDF, or over 15 MB)")
            continue
        key = f"gmail:{msg_id}:{name}"
        if app.already_added(key):
            continue
        text = read_pdf(pdf)
        supplier, sure = pick_supplier(candidates, text, subject, name)
        note = None
        if not sure:
            note = "Could be: " + ", ".join(
                f"{c['name']}{' ' + str(c['account_no']) if c.get('account_no') else ''}" for c in candidates) + " -- check the account."
        guess = guess_full(text, subject, name, sent)
        app.add(supplier, pdf, name, guess, sender, subject, sent, key, note=note)
        amount = "amount ?" if guess["amount"] is None else f"R{guess['amount']:,.2f}"
        due = f" due {guess['due_date']}" if guess.get("due_date") else ""
        if guess.get("overdue_amount"):
            due += f" (R{guess['overdue_amount']:,.2f} already due)"
        unsure = "" if sure else "  <-- supplier not sure, " + note
        if guess.get("notice"):
            log(f"  !! {supplier['name']}: {guess['notice']} ({name}, {guess['doc_date']})")
            added += 1
            continue
        log(f"  {supplier['name']}: {guess['kind']} {guess['reference'] or ''} {guess['doc_date']}{due} {amount} ({name}){unsure}")
        added += 1
    return added


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--days", type=int, default=60, help="How far back to look in Gmail (default 60 days).")
    parser.add_argument("--since", type=dt.date.fromisoformat, metavar="YYYY-MM-DD",
                        help="Look at emails from this date on (instead of --days), e.g. 2026-03-01.")
    parser.add_argument("--rescan", action="store_true", help="Check emails again even if an earlier run already handled them.")
    parser.add_argument("--dry-run", action="store_true", help="Only show what would be added; change nothing.")
    parser.add_argument("--show", metavar="PDF", help="Only show the text read from this PDF and what was found in it.")
    parser.add_argument("--fill-details", action="store_true",
                        help="Read the VAT and invoice lines of the documents already in the app from their PDFs (no Gmail).")
    parser.add_argument("--reread", metavar="SUPPLIER",
                        help='With --fill-details: read ALL documents of the suppliers whose name starts so again in full, e.g. "Eskom - 8441635490".')
    args = parser.parse_args()
    sys.stdout.reconfigure(line_buffering=True)

    if args.fill_details:
        try:
            filled, skipped = fill_details(App(dry_run=args.dry_run), reread=args.reread)
        except Exception as e:
            print(f"PROBLEM: {e} -- was docs/sql/suppliers_purchases.sql run?")
            return 1
        print(f"Done: {filled} document(s) {'would be ' if args.dry_run else ''}filled in, {skipped} without lines (statements, notices, scans).")
        return 0

    if args.show:
        path = pathlib.Path(args.show)
        if not path.is_file():
            print(f"No such file: {path}\nSave the PDF from Gmail first, then give its real place, e.g.\n"
                  f'  py scripts\\fetch_supplier_docs.py --show "%USERPROFILE%\\Downloads\\{path.name}"')
            return 1
        text = read_pdf(path.read_bytes())
        print(text or "(no text in this PDF -- a scan or a printed copy; the amount must be typed in)")
        print("-" * 60)
        g = guess_full(text, "", path.name, dt.date.today())
        lines = g.pop("lines", [])
        print(g)
        for line in lines:
            print("   ", line)
        return 0

    app = App(dry_run=args.dry_run)
    try:
        suppliers = [s for s in app.suppliers() if s["addresses"]]
    except Exception as e:
        print(f"PROBLEM: could not read the suppliers from the app ({e}). Was docs/sql/suppliers.sql run?")
        return 1
    if not suppliers:
        print("No supplier has an email address in the app yet -- nothing to look for.")
        return 0

    try:
        seen = set() if args.rescan else set(json.loads(SEEN_FILE.read_text(encoding="utf-8")))
    except (OSError, ValueError):
        seen = set()

    added = already = failed = 0
    gmail = None
    try:
        # Read-only: nothing in Gmail is changed.
        gmail = open_gmail()
        ids = gmail.search(gmail_query(suppliers, args.days, args.since))
        when = f"since {args.since.isoformat()}" if args.since else f"in the last {args.days} days"
        print(f"{len(ids)} email(s) with PDFs from {len(suppliers)} supplier(s) {when}.")
        for msg_id in ids:
            if msg_id in seen:
                already += 1
                continue
            try:
                added += process_message(gmail.fetch(msg_id), msg_id, suppliers, app)
                if not args.dry_run:
                    seen.add(msg_id)
            except Exception as e:
                failed += 1
                print(f"  PROBLEM with an email ({e}) -- it will be tried again next run.")
    except GmailProblem as e:
        print(f"PROBLEM: {e}")
        return 1
    finally:
        if gmail:
            gmail.close()
        if not args.dry_run:
            SEEN_FILE.write_text(json.dumps(sorted(seen)), encoding="utf-8")

    what = "would be added" if args.dry_run else "added to the app to check"
    print(f"Done: {added} PDF(s) {what}, {already} email(s) already handled, {failed} problem(s).")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
