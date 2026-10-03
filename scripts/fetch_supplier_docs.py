#!/usr/bin/env python3
"""
Brings supplier invoices, credit notes and statements that arrive by email
(Gmail) into the hub's Suppliers app, to be checked and confirmed there.

    python scripts\\fetch_supplier_docs.py
    python scripts\\fetch_supplier_docs.py --days 120      # look further back
    python scripts\\fetch_supplier_docs.py --dry-run       # show what it would do, change nothing

How it works:
  * Reads the suppliers and their email addresses from the app (the supplier's
    Email field; several addresses may be listed, separated by commas, and an
    entry like "@agri.co.za" matches anyone at that domain).
  * Logs in to Gmail with the same app password as fetch_gmail_invoices.py
    (scripts/gmail_account.txt -- stays on this PC only). The mailbox is
    opened READ-ONLY: nothing in Gmail is changed, moved, deleted, labelled,
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
import imaplib
import json
import pathlib
import re
import sys
import tempfile
import uuid

from fetch_gmail_invoices import ACCOUNT_FILE, IMAP_HOST, find_all_mail, load_account
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


def match_supplier(sender, suppliers):
    """The supplier whose Email field lists [sender] (or its domain)."""
    sender = (sender or "").strip().lower()
    if "@" not in sender:
        return None
    domain = "@" + sender.split("@", 1)[1]
    for s in suppliers:
        if sender in s["addresses"]:
            return s
    for s in suppliers:
        if domain in s["addresses"]:
            return s
    return None


def gmail_query(suppliers, days):
    terms = sorted({a.lstrip("@") for s in suppliers for a in s["addresses"]})
    return f'"has:attachment filename:pdf newer_than:{days}d from:({" OR ".join(terms)})"'


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


def guess_kind(text, subject="", filename=""):
    t = f"{subject}\n{filename}\n{text[:3000]}".lower()
    if "statement" in t or "staat" in t or "state of account" in t:
        return "statement"
    if "credit note" in t or "credit memo" in t or "kredietnota" in t:
        return "credit_note"
    return "invoice"


# Labels whose line holds the amount, best first.
STATEMENT_LABELS = ["closing balance", "balance due", "amount due", "total due", "total outstanding",
                    "amount payable", "balance owing", "outstanding balance", "balance"]
INVOICE_LABELS = ["total due", "amount due", "invoice total", "grand total", "total incl", "total (incl",
                  "balance due", "amount payable", "total"]


def guess_amount(text, kind):
    labels = STATEMENT_LABELS if kind == "statement" else INVOICE_LABELS
    lines = text.splitlines()
    for label in labels:
        found = None
        for line in lines:
            low = line.lower()
            if label in low and not ("sub" in low and label == "total") and not ("vat" in low and label == "total"):
                vals = amounts_in(line[low.index(label):])
                if vals:
                    found = vals[-1]  # the last such line: totals are at the bottom
        if found is not None:
            return round(found, 2)
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


def guess_date(text, kind):
    labels = (["statement date", "date of statement", "as at", "period ending"] if kind == "statement" else
              ["invoice date", "tax invoice date", "credit note date", "date of invoice", "document date"]) + ["date"]
    lines = text.splitlines()
    for label in labels:
        for line in lines:
            low = line.lower()
            if label in low and "due date" not in low:
                d = _date_in(line[low.index(label):])
                if d:
                    return d
    for line in lines[:40]:
        d = _date_in(line)
        if d:
            return d
    return None


REF_RE = re.compile(
    r"(?:tax\s+invoice|invoice|credit\s+note|document)\s*(?:no\.?|number|num|nr\.?|#)\s*[:.\-]?\s*([A-Z0-9][A-Z0-9\-/]{2,})",
    re.IGNORECASE,
)


def guess_reference(text, kind, subject=""):
    if kind == "statement":
        return None
    for src in (text, subject):
        m = REF_RE.search(src or "")
        if m:
            return m.group(1).strip()
    return None


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


def guess_all(text, subject, filename, sent):
    kind = guess_kind(text, subject, filename)
    return {
        "kind": kind,
        "doc_date": (guess_date(text, kind) or sent).isoformat(),
        "amount": guess_amount(text, kind),
        "reference": guess_reference(text, kind, subject),
    }


# ---------------------------------------------------------------------------
# The app (Supabase): suppliers, upload, add "to check"
# ---------------------------------------------------------------------------

class App:
    def __init__(self, dry_run=False):
        import requests

        self.requests = requests
        self.headers = _auth_headers()
        self.dry_run = dry_run

    def suppliers(self):
        r = self.requests.get(f"{SUPABASE_URL}/rest/v1/suppliers", params={"select": "id,name,email"},
                              headers=self.headers, timeout=30)
        r.raise_for_status()
        return [dict(s, addresses=supplier_addresses(s.get("email"))) for s in r.json()]

    def already_added(self, key):
        r = self.requests.get(f"{SUPABASE_URL}/rest/v1/supplier_docs", params={"select": "id", "email_key": f"eq.{key}"},
                              headers=self.headers, timeout=30)
        r.raise_for_status()
        return bool(r.json())

    def add(self, supplier, pdf, filename, guess, sender, subject, sent, key):
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
            "notes": None if guess["amount"] is not None else "Amount not found in the PDF -- type it in.",
        }
        r = self.requests.post(f"{SUPABASE_URL}/rest/v1/supplier_docs", json=row,
                               headers={**self.headers, "Prefer": "return=minimal"}, timeout=30)
        if not r.ok:
            # Not added: don't leave the PDF behind.
            self.requests.delete(f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{path}", headers=self.headers, timeout=30)
            if r.status_code == 409:
                return  # already there (another run)
            r.raise_for_status()


def process_message(raw, msg_id, suppliers, app, log=print):
    """Adds the PDFs of one email from a supplier. Returns how many were added."""
    msg = email.message_from_bytes(raw, policy=email.policy.default)
    sender = email.utils.parseaddr(msg.get("From", ""))[1]
    supplier = match_supplier(sender, suppliers)
    if supplier is None:
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
        pdf = part.get_payload(decode=True) or b""
        if not pdf.startswith(b"%PDF") or len(pdf) > MAX_PDF:
            log(f"  Skipped {name} from {supplier['name']} (not a PDF, or over 15 MB)")
            continue
        key = f"gmail:{msg_id}:{name}"
        if app.already_added(key):
            continue
        guess = guess_all(read_pdf(pdf), subject, name, sent)
        app.add(supplier, pdf, name, guess, sender, subject, sent, key)
        amount = "amount ?" if guess["amount"] is None else f"R{guess['amount']:,.2f}"
        log(f"  {supplier['name']}: {guess['kind']} {guess['reference'] or ''} {guess['doc_date']} {amount} ({name})")
        added += 1
    return added


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--days", type=int, default=60, help="How far back to look in Gmail (default 60 days).")
    parser.add_argument("--rescan", action="store_true", help="Check emails again even if an earlier run already handled them.")
    parser.add_argument("--dry-run", action="store_true", help="Only show what would be added; change nothing.")
    args = parser.parse_args()
    sys.stdout.reconfigure(line_buffering=True)

    app = App(dry_run=args.dry_run)
    try:
        suppliers = [s for s in app.suppliers() if s["addresses"]]
    except Exception as e:
        print(f"PROBLEM: could not read the suppliers from the app ({e}). Was docs/sql/suppliers.sql run?")
        return 1
    if not suppliers:
        print("No supplier has an email address in the app yet -- nothing to look for.")
        return 0

    address, app_password = load_account()
    try:
        seen = set() if args.rescan else set(json.loads(SEEN_FILE.read_text(encoding="utf-8")))
    except (OSError, ValueError):
        seen = set()

    try:
        imap = imaplib.IMAP4_SSL(IMAP_HOST)
        imap.login(address, app_password)
    except imaplib.IMAP4.error as e:
        print(f"PROBLEM: Gmail refused the login ({e}). Check the address and app password in {ACCOUNT_FILE.name}.")
        return 1
    except OSError as e:
        print(f"PROBLEM: could not reach Gmail ({e}). Check this PC's internet connection.")
        return 1

    added = already = failed = 0
    try:
        # Read-only: nothing in Gmail is changed (BODY.PEEK doesn't even mark as read).
        imap.select(find_all_mail(imap), readonly=True)
        typ, data = imap.uid("SEARCH", None, "X-GM-RAW", gmail_query(suppliers, args.days))
        uids = data[0].split() if typ == "OK" and data and data[0] else []
        print(f"{len(uids)} email(s) with PDFs from {len(suppliers)} supplier(s) in the last {args.days} days.")
        for uid in uids:
            typ, parts = imap.uid("FETCH", uid, "(X-GM-MSGID BODY.PEEK[])")
            if typ != "OK" or not parts or not isinstance(parts[0], tuple):
                continue
            header, raw = parts[0]
            m = re.search(rb"X-GM-MSGID (\d+)", header)
            msg_id = m.group(1).decode() if m else uid.decode()
            if msg_id in seen:
                already += 1
                continue
            try:
                added += process_message(raw, msg_id, suppliers, app)
                if not args.dry_run:
                    seen.add(msg_id)
            except Exception as e:
                failed += 1
                print(f"  PROBLEM with an email ({e}) -- it will be tried again next run.")
    finally:
        try:
            imap.logout()
        except Exception:
            pass
        if not args.dry_run:
            SEEN_FILE.write_text(json.dumps(sorted(seen)), encoding="utf-8")

    what = "would be added" if args.dry_run else "added to the app to check"
    print(f"Done: {added} PDF(s) {what}, {already} email(s) already handled, {failed} problem(s).")
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
