#!/usr/bin/env python3
"""
Brings the potato bags bought from Crown Bag (their tax invoices, by email)
into the hub's Packaging > Bags/Boxes tab, to see how many bags are on the
floor to pack (the last stock take plus purchases, less 0.5% of that for
losses, less the bags used).

    python scripts\\fetch_crown_bags.py                 # from 1 Feb 2026
    python scripts\\fetch_crown_bags.py --since 2026-10-01
    python scripts\\fetch_crown_bags.py --dry-run       # show what it finds, change nothing
    python scripts\\fetch_crown_bags.py --show invoice.pdf   # what's read from one PDF

How it works:
  * Reads Gmail READ-ONLY through scripts/gmail_access.py (same sign-in as
    fetch_supplier_docs.py): only emails from Crown Bag (anyone at
    crownbag.co.za, or annekevdm@vkb.co.za) with a PDF attached.
  * Takes only tax invoices (and credit notes, as bags taken off) -- not
    quotes, orders or statements -- and from each its bag lines, e.g.
    "10kg NANINI - 1 LARGE 25/02/26 35 000 Bags": the bag (weight, grade,
    size; every 2nd and 3rd grade, and a brown bag, is the brown bag), the date and
    how many. Levies, transport and paper pallets are
    left out.
  * Each invoice line goes into the app once (the invoice number and line),
    however often it's run or the invoice was emailed.

Needs the Supabase secret key (scripts/supabase_secret_key.txt) like the
sales import, and docs/sql/bag_purchases.sql run once.
"""
import argparse
import datetime as dt
import email
import email.policy
import email.utils
import pathlib
import re
import sys
import tempfile

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
SENDERS = ["crownbag.co.za", "annekevdm@vkb.co.za"]
# Bags bought from 1 Feb 2026 (earlier invoices are left out).
DEFAULT_SINCE = dt.date(2026, 2, 1)

# The bag, as the phones count the pallets: Baby and Small use the same
# 10kg Small bag; all 2nd and 3rd grades the brown (generic) bag.
BAGS = {
    (1, 10, "BABY"): "small10",
    (1, 10, "SMALL"): "small10",
    (1, 10, "L/MED"): "largemed10",
    (1, 10, "LARGE"): "large10",
    (1, 7, "S/MED"): "smallmed7",
    (1, 7, "MED"): "med7",
    (1, 10, "MED"): "med10",  # the 10kg Medium, a green bag
    # All 2nd and 3rd grades go in the same bag: normally a brown generic one.
    (2, 10, "MED"): "brown10",
    (2, 10, "L/MED"): "brown10",
    (2, 10, "LARGE"): "brown10",
}
# ... and every 3rd grade too.
BAGS.update({(3, 10, size): "brown10" for size in ("BABY", "SMALL", "S/MED", "MED", "L/MED", "LARGE")})
BROWN = "brown10"

# "10kg NANINI - 1 LARGE 25/02/26 35 000Bags" (the item code before it may be
# run into the text: "1P0O-WTAHT0O0-17-7KG NANINI - 1 MED ...").
# Also "10KG NANINI BDY - 1 LARGE" and "7KG NANINI - MED - GREEN" (no grade:
# 1st grade; a colour after it), as on PSI33313.
BAG_LINE = re.compile(
    r"(?P<kg>10|7)\s*kg\s+NANINI(?:\s+BDY)?\s*-\s*(?:(?P<grade>[123])\s+)?(?P<size>BABY|SMALL|S\s*/\s*MED|MED(?:IUM)?|L\s*/\s*MED|LARGE)\b"
    r".*?(?P<date>\d{2}/\d{2}/\d{2,4})\s+(?P<qty>\d{1,3}(?:[  ]\d{3})*|\d+)\s*Bags", re.I)


# The brown generic bag (2nd and 3rd grades), not printed NANINI: "10kg BROWN ...
# 25/02/26 5 000Bags".
BROWN_LINE = re.compile(r"(?P<kg>10)\s*kg\b(?P<desc>[^\n]*?\bBROWN\b[^\n]*?)\s+(?P<date>\d{2}/\d{2}/\d{2,4})\s+"
                        r"(?P<qty>\d{1,3}(?:[ \u00a0]\d{3})*|\d+)\s*Bags", re.I)


def _size(s):
    s = re.sub(r"\s+", "", s.upper())
    return "MED" if s == "MEDIUM" else s


def _date(s):
    d, m, y = s.split("/")
    y = int(y) + (2000 if len(y) == 2 else 0)
    return dt.date(y, int(m), int(d)).isoformat()


def is_invoice(text):
    """'tax' / 'credit' for a Crown Bag tax invoice or credit note; None for
    anything else (a quote, order confirmation, statement)."""
    if not re.search(r"crown\s*bag", text, re.I):
        return None
    if re.search(r"credit\s*(memo|note)", text, re.I):
        return "credit"
    if re.search(r"tax\s+invoice", text, re.I) and not re.search(r"quot|pro\s*-?\s*forma|order\s+confirmation|statement", text, re.I):
        return "tax"
    return None


def invoice_number(text):
    m = re.search(r"(?:Invoice|Credit\s*(?:Memo|Note))\s*No\.?\s*([A-Z]{2,5}\d{3,})", text, re.I) or re.search(r"\b(PS[A-Z]{0,2}\d{4,})\b", text)
    return m.group(1) if m else None


def bag_lines(text):
    """[{item, kg, grade, size, date, qty, description}] of the bags on an
    invoice; unknown bags as item None (to report)."""
    out = []
    for line in text.splitlines():
        m = BAG_LINE.search(line)
        if not m:
            b = BROWN_LINE.search(line)
            if b and not re.search(r"levy|transport", line, re.I):
                out.append({
                    "item": BROWN,
                    "description": f"10kg{b.group('desc')}".strip()[:60],
                    "date": _date(b.group("date")),
                    "qty": int(re.sub(r"\D", "", b.group("qty"))),
                })
            continue
        kg, grade, size = int(m.group("kg")), int(m.group("grade") or 1), _size(m.group("size"))
        out.append({
            "item": BAGS.get((grade, kg, size)),
            "description": f"{kg}kg NANINI - {grade} {size}",
            "date": _date(m.group("date")),
            "qty": int(re.sub(r"\D", "", m.group("qty"))),
        })
    return out


def why_skipped(text):
    """Why a PDF from Crown Bag isn't taken: what it seems to be."""
    if not re.search(r"crown\s*bag", text, re.I):
        return "not from Crown Bag"
    if is_invoice(text):
        return "an invoice with no NANINI or brown potato bags on it"
    for pattern, what in [(r"statement", "a statement"), (r"quot", "a quote"), (r"pro\s*-?\s*forma", "a pro forma"),
                          (r"order\s+confirmation|sales\s+order", "an order"), (r"remittance", "a remittance")]:
        if re.search(pattern, text, re.I):
            return what
    return "not a tax invoice"


def read_invoice(text):
    """(invoice number, kind, lines) or None when it's not a Crown Bag invoice with bags."""
    kind = is_invoice(text)
    if not kind:
        return None
    lines = bag_lines(text)
    if not lines:
        return None
    if kind == "credit":
        for l in lines:
            l["qty"] = -l["qty"]
    return invoice_number(text), kind, lines


def rows_for(number, lines, fallback_key):
    """The bag_purchases rows: one per bag line, keyed by the invoice, the bag
    and how many (not the line's place: a line read later must not move the
    others), so each is added once."""
    ref = number or fallback_key
    out, seen = [], {}
    for l in lines:
        if not l["item"]:
            continue
        key = f"crownbag:{ref}:{l['item']}:{l['qty']}"
        seen[key] = seen.get(key, 0) + 1
        out.append({
            "purchase_date": l["date"],
            "produce": "potato",
            "item": l["item"],
            "qty": l["qty"],
            "reference": number,
            "description": l["description"],
            "source_key": key if seen[key] == 1 else f"{key}:{seen[key]}",
        })
    return out


def not_there_yet(rows, existing):
    """The rows not in the app yet: the same invoice, bag, number and date as
    one there (whatever its source_key -- the earlier runs numbered the lines)
    counts as there."""
    have = {}
    for e in existing:
        k = (e.get("reference"), e.get("item"), e.get("qty"), e.get("purchase_date"))
        have[k] = have.get(k, 0) + 1
    out = []
    for r in rows:
        k = (r["reference"], r["item"], r["qty"], r["purchase_date"])
        if have.get(k):
            have[k] -= 1
        else:
            out.append(r)
    return out


def gmail_query(since):
    """Gmail's search, in quotes: over IMAP (X-GM-RAW) it must be one quoted
    string -- unquoted, Gmail answers "Could not parse command". The Google
    sign-in way takes the quotes off."""
    return f'"has:attachment filename:pdf after:{since:%Y/%m/%d} from:({" OR ".join(SENDERS)})"'


def pdf_text(data):
    from import_sales_report import extract_pages

    with tempfile.TemporaryDirectory() as d:
        p = pathlib.Path(d) / "doc.pdf"
        p.write_bytes(data)
        return "\n".join(extract_pages(p))


def pdfs_in(raw):
    """(email date 'YYYY-MM-DD', file name, PDF) of each PDF in an email."""
    msg = email.message_from_bytes(raw, policy=email.policy.default)
    try:
        sent = email.utils.parsedate_to_datetime(msg["Date"]).date().isoformat()
    except Exception:
        sent = "?"
    for part in msg.walk():
        name = part.get_filename() or ""
        if part.get_content_type() == "application/pdf" or name.lower().endswith(".pdf"):
            data = part.get_payload(decode=True)
            if data:
                yield sent, name or "invoice.pdf", data


def show(path):
    text = pdf_text(pathlib.Path(path).read_bytes())
    print(text)
    print("-" * 60)
    found = read_invoice(text)
    if not found:
        print("Not a Crown Bag tax invoice / credit note with bags on it.")
        return
    number, kind, lines = found
    print(f"{kind} {number}")
    for l in lines:
        print(f"  {l['date']}  {l['qty']:>8}  {l['description']:<26} -> {l['item'] or 'NOT KNOWN'}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--since", type=dt.date.fromisoformat, default=DEFAULT_SINCE, metavar="YYYY-MM-DD",
                        help="Bags bought from this date (default 2026-02-01): earlier invoices are left out.")
    parser.add_argument("--dry-run", action="store_true", help="Only show what would be added; change nothing.")
    parser.add_argument("--show", metavar="PDF", help="Only show the text read from this PDF and the bags found in it.")
    args = parser.parse_args()
    if args.show:
        show(args.show)
        return 0

    import requests
    from gmail_access import GmailProblem, open_gmail
    from import_sales_report import SUPABASE_URL, _auth_headers

    headers = _auth_headers()
    query = gmail_query(args.since)
    try:
        gmail = open_gmail()
    except GmailProblem as e:
        print(e)
        return 1
    try:
        ids = gmail.search(query)
        print(f"{len(ids)} emails from Crown Bag since {args.since:%d %b %Y} with a PDF.")
        rows, unknown, invoices, skipped = [], [], {}, []
        for msg_id in ids:
            for sent, name, data in pdfs_in(gmail.fetch(msg_id)):
                try:
                    text = pdf_text(data)
                    found = read_invoice(text)
                except Exception as e:  # a PDF that can't be read: say so, carry on
                    skipped.append((sent, name, f"can't be read ({e})"))
                    continue
                if not found:
                    skipped.append((sent, name, why_skipped(text)))
                    continue
                number, kind, lines = found
                # Only bags bought from the start date (an older invoice emailed later too).
                lines = [l for l in lines if l["date"] >= args.since.isoformat()]
                if not lines:
                    skipped.append((sent, number or name, f"bags bought before {args.since:%d %b %Y}"))
                    continue
                key = number or f"{msg_id}:{name}"
                if key in invoices:
                    continue  # the same invoice in another email
                invoices[key] = (kind, lines)
                rows += rows_for(number, lines, f"{msg_id}:{name}")
                unknown += [(number or name, l["description"]) for l in lines if not l["item"]]
    finally:
        gmail.close()

    for key, (kind, lines) in sorted(invoices.items(), key=lambda kv: kv[1][1][0]["date"]):
        print(f"{lines[0]['date']}  {'Credit ' if kind == 'credit' else ''}{key}: "
              + ", ".join(f"{l['qty']} x {l['description']}" for l in lines))
    if skipped:
        print("\nPDFs left out (not potato bag invoices):")
        for sent, name, why in sorted(skipped):
            print(f"  emailed {sent}  {name}: {why}")
    totals = {}
    for r in rows:
        totals[r["description"]] = totals.get(r["description"], 0) + r["qty"]
    print(f"\n{len(invoices)} invoices; bags bought:")
    for d, q in sorted(totals.items()):
        print(f"  {d:<26} {q:>9,}".replace(",", " "))
    if unknown:
        print("\nBags not known to the app (left out -- tell Claude what they are):")
        for ref, d in unknown:
            print(f"  {ref}: {d}")
    if args.dry_run:
        print("\nDry run: nothing added.")
        return 0
    if rows:
        r = requests.get(f"{SUPABASE_URL}/rest/v1/bag_purchases", headers=headers, timeout=60,
                         params={"select": "reference,item,qty,purchase_date", "source_key": "like.crownbag:*"})
        if r.status_code == 404:
            print("\nThe bag_purchases table isn't there yet: run docs/sql/bag_purchases.sql in Supabase first.")
            return 1
        r.raise_for_status()
        new = not_there_yet(rows, r.json())
        if not new:
            print(f"\nNothing new: all {len(rows)} invoice lines are in the app already.")
            return 0
        r = requests.post(f"{SUPABASE_URL}/rest/v1/bag_purchases", params={"on_conflict": "source_key"}, json=new,
                          headers={**headers, "Prefer": "resolution=ignore-duplicates,return=representation"}, timeout=60)
        if r.status_code == 404:
            print("\nThe bag_purchases table isn't there yet: run docs/sql/bag_purchases.sql in Supabase first.")
            return 1
        r.raise_for_status()
        print(f"\n{len(r.json())} new invoice lines added to Packaging > Bags/Boxes "
              f"({len(rows) - len(r.json())} were there already):")
        for a in r.json():
            print(f"  {a['purchase_date']}  {a['reference']}  {a['qty']:>8}  {a['description']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
