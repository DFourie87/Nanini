#!/usr/bin/env python3
"""
Adds the payments to suppliers from ABSA bank statement CSVs (Absa online
banking > transaction history > export CSV) to the hub's Suppliers app.

    py scripts\\import_bank_payments.py "D:\\Kliente\\Nanini 121 BK\\2027\\BTW" --dry-run
    py scripts\\import_bank_payments.py "D:\\Kliente\\Nanini 121 BK\\2027\\BTW"
    py scripts\\import_bank_payments.py "D:\\Kliente\\Nanini 121 BK\\2027\\BTW" --find muni
      (only lists the bank lines with "muni" in them, and each CSV's dates -- changes nothing)

How it works:
  * Reads every ABSA CSV (columns Date, Description, Amount, Balance) in the
    folder and its subfolders, or the one file given. The same transaction in
    two overlapping CSVs counts once.
  * Only payments made to a beneficiary ("DIGITAL PAYMENT ... ABSA BANK
    <beneficiary name>") are looked at. The beneficiary name is matched to a
    supplier in the app:
      - by the supplier's account number in it ("Eskom 8441635490"), else
      - by the supplier's name or bank account holder at its start ("VKB
        Augustus 2026" -> VKB, "NTB" -> Noord Tranvaal Boere).
    A name that fits more than one supplier (just "Eskom") is listed, not
    added. Everything else (wages, cash, card purchases, other payees) is
    left alone and nothing about it is kept.
  * A payment already in the app for that supplier on the same day with the
    same amount (typed in by hand, or an earlier run) isn't added again.

  * Money in from a buyer paid straight into the bank (Peppadew -- no
    payment summaries): each deposit naming it (the customer's bank_match,
    docs/sql/customers_buyers.sql) is a payment on its account in Sales.
  * Money in from the market agents: each payment summary on a customer's
    account in Sales (import_market_payments.py) is matched to the deposit of
    the same amount in the bank, from 3 days before its date to 10 after, and
    gets that bank date -- the proof it came in.

The bank CSVs stay on this PC -- never commit or share them. Needs the
Supabase secret key (scripts/supabase_secret_key.txt) like the sales import.
"""
import argparse
import collections
import csv
import datetime as dt
import io
import pathlib
import re
import sys

from import_sales_report import SUPABASE_URL, _auth_headers

PAYEE_RE = re.compile(r"\bABSA BANK\s+(.+?)\s*$", re.I)
# A card purchase: "POS PURCHASE (4.60) (EFFEC 19082026) LAEVELD AGROCHEM PITER POLOK CARD NO. 4258"
POS_RE = re.compile(r"\bPOS PURCHASE\b.*?\(EFFEC\s+(\d{2})(\d{2})(\d{4})\)\s+(.+?)\s+CARD NO\b", re.I)


def norm(text):
    return " ".join(re.sub(r"[^a-z0-9]+", " ", (text or "").lower()).split())


def read_csv(path):
    """ABSA transactions: [(date, description, amount, balance)]; [] if it isn't one."""
    raw = pathlib.Path(path).read_bytes()
    try:
        text = raw.decode("utf-8-sig")
    except UnicodeDecodeError:
        text = raw.decode("cp1252")
    rows = list(csv.reader(io.StringIO(text)))
    if not rows or [c.strip().lower() for c in rows[0][:4]] != ["date", "description", "amount", "balance"]:
        return []
    out = []
    for r in rows[1:]:
        if len(r) < 4 or not r[0].strip():
            continue
        try:
            day = dt.datetime.strptime(r[0].strip(), "%Y%m%d").date()
            out.append((day, r[1].strip(), float(r[2]), float(r[3] or 0)))
        except ValueError:
            continue
    return out


def payments_in(paths):
    """Payments to beneficiaries, each once: [(date, payee, amount)]."""
    seen, out = set(), []
    for path in paths:
        for day, desc, amount, balance in read_csv(path):
            # The same transaction in two CSVs (ABSA's export, one typed out
            # from a printed statement): the same day, amount and balance after it.
            key = (day, amount, balance) if balance else (day, desc, amount, balance)
            if amount >= 0 or key in seen:
                continue
            seen.add(key)
            m = PAYEE_RE.search(desc)
            if m:
                out.append((day, m.group(1).strip(), round(-amount, 2)))
    return sorted(out)


def card_purchases_in(paths):
    """Card purchases, each once: [(date bought, shop, amount)]."""
    seen, out = set(), []
    for path in paths:
        for day, desc, amount, balance in read_csv(path):
            # The same transaction in two CSVs (ABSA's export, one typed out
            # from a printed statement): the same day, amount and balance after it.
            key = (day, amount, balance) if balance else (day, desc, amount, balance)
            if amount >= 0 or key in seen:
                continue
            seen.add(key)
            m = POS_RE.search(desc)
            if m:
                try:
                    bought = dt.date(int(m.group(3)), int(m.group(2)), int(m.group(1)))
                except ValueError:
                    bought = day
                out.append((bought, m.group(4).strip(), round(-amount, 2)))
    return sorted(out)


def receipts_in(paths):
    """Money in, each once: [(date, description, amount)]."""
    seen, out = set(), []
    for path in paths:
        for day, desc, amount, balance in read_csv(path):
            key = (day, amount, balance) if balance else (day, desc, amount, balance)
            if amount <= 0 or key in seen:
                continue
            seen.add(key)
            out.append((day, desc, round(amount, 2)))
    return sorted(out)


def match_receipts(receipts, payments):
    """Each customer payment {'id', 'pay_date', 'amount', 'name'} to the deposit
    of its amount from 3 days before its date to 10 after (the nearest; one
    naming the agent first), each deposit used once: [(payment, (date, description, amount))]."""
    used, out = set(), []
    for p in sorted(payments, key=lambda p: p["pay_date"]):
        day = dt.date.fromisoformat(p["pay_date"])
        amount = round(float(p["amount"]), 2)
        words = [w for w in norm(p.get("name")).split() if len(w) >= 4]
        fits = [(i, r) for i, r in enumerate(receipts)
                if i not in used and abs(r[2] - amount) < 0.01 and -3 <= (r[0] - day).days <= 10]
        if not fits:
            continue
        i, r = min(fits, key=lambda f: (not any(w in norm(f[1][1]) for w in words), abs((f[1][0] - day).days)))
        used.add(i)
        out.append((p, r))
    return out


def buyer_deposits(receipts, buyers):
    """Deposits from buyers paid straight into the bank: [(customer, (date,
    description, amount))] for each deposit whose description has the
    customer's bank_match in it."""
    out = []
    for r in receipts:
        for c in buyers:
            key = norm(c.get("bank_match"))
            if key and f" {key} " in f" {norm(r[1])} ":
                out.append((c, r))
                break
    return out


def match_payee(payee, suppliers):
    """(supplier, None) when it's clear; (None, [candidates]) when it fits
    several; (None, []) when it's no supplier."""
    digits = re.findall(r"\d{6,}", payee)
    by_number = [s for s in suppliers
                 if len(re.sub(r"\D", "", s.get("account_no") or "")) >= 6
                 and any(re.sub(r"\D", "", s["account_no"]) in d for d in digits)]
    if len(by_number) == 1:
        return by_number[0], None
    p = norm(payee)
    by_name = []
    for s in suppliers:
        for key in {norm(s.get("name")), norm(s.get("bank_account_holder"))}:
            if len(key) >= 3 and (p == key or p.startswith(key + " ")):
                by_name.append(s)
                break
    if by_number:
        by_name = [s for s in by_name if s in by_number] or by_number
    if len(by_name) == 1:
        return by_name[0], None
    return None, by_name


class App:
    def __init__(self, dry_run=False):
        import requests

        self.requests = requests
        self.headers = _auth_headers()
        self.dry_run = dry_run

    def suppliers(self):
        r = self.requests.get(f"{SUPABASE_URL}/rest/v1/suppliers", params={"select": "id,name,account_no,bank_account_holder"},
                              headers=self.headers, timeout=30)
        r.raise_for_status()
        return r.json()

    def existing(self):
        """Payments already in the app: Counter of (supplier_id, date, amount) --
        all of them, a page at a time (the database gives 1000 at most at once)."""
        rows, start = [], 0
        while True:
            r = self.requests.get(f"{SUPABASE_URL}/rest/v1/supplier_payments",
                                  params={"select": "supplier_id,pay_date,amount", "order": "id"},
                                  headers={**self.headers, "Range-Unit": "items", "Range": f"{start}-{start + 999}"}, timeout=60)
            r.raise_for_status()
            page = r.json()
            rows += page
            if len(page) < 1000:
                break
            start += 1000
        return collections.Counter((p["supplier_id"], p["pay_date"], round(float(p["amount"]), 2)) for p in rows)

    def invoice_for(self, supplier, day, amount):
        """An invoice on the supplier's account (not a till slip) of this
        amount within a week of [day] -- a card purchase that pays it."""
        r = self.requests.get(f"{SUPABASE_URL}/rest/v1/supplier_docs", params=[
            ("select", "id"), ("supplier_id", f"eq.{supplier['id']}"), ("kind", "eq.invoice"), ("amount", f"eq.{amount}"),
            ("cash_sale", "is.false"), ("doc_date", f"gte.{(day - dt.timedelta(days=7)).isoformat()}"),
            ("doc_date", f"lte.{(day + dt.timedelta(days=7)).isoformat()}")], headers=self.headers, timeout=30)
        if not r.ok:
            return False
        return bool(r.json())

    def add(self, supplier, day, amount, payee):
        if self.dry_run:
            return
        row = {"supplier_id": supplier["id"], "pay_date": day.isoformat(), "amount": amount,
               "reference": payee[:80], "notes": "From the ABSA bank statement (CSV)."}
        r = self.requests.post(f"{SUPABASE_URL}/rest/v1/supplier_payments", json=row,
                               headers={**self.headers, "Prefer": "return=minimal"}, timeout=30)
        r.raise_for_status()


    def unmatched_customer_payments(self):
        """Market agents' payments not yet found in the bank, or None if the
        customers aren't set up (docs/sql/customers.sql)."""
        r = self.requests.get(f"{SUPABASE_URL}/rest/v1/customer_payments",
                              params={"select": "id,pay_date,amount,customers(name)", "bank_date": "is.null"},
                              headers=self.headers, timeout=30)
        if not r.ok:
            return None
        return [{**p, "name": (p.get("customers") or {}).get("name", "")} for p in r.json()]

    def buyers(self):
        """Customers paid straight into the bank (bank_match set); [] when not set up."""
        r = self.requests.get(f"{SUPABASE_URL}/rest/v1/customers", params={"select": "id,name,bank_match", "bank_match": "not.is.null"},
                              headers=self.headers, timeout=30)
        return r.json() if r.ok else []

    def add_buyer_payment(self, customer, receipt):
        """Returns True when it's new (the same day and amount isn't there yet)."""
        day, desc, amount = receipt
        if self.dry_run:
            r = self.requests.get(f"{SUPABASE_URL}/rest/v1/customer_payments",
                                  params={"select": "id", "customer_id": f"eq.{customer['id']}", "pay_date": f"eq.{day.isoformat()}",
                                          "amount": f"eq.{amount}"}, headers=self.headers, timeout=30)
            return r.ok and not r.json()
        r = self.requests.post(f"{SUPABASE_URL}/rest/v1/customer_payments", params={"on_conflict": "customer_id,pay_date,amount"},
                               json={"customer_id": customer["id"], "pay_date": day.isoformat(), "amount": amount, "method": "bank",
                                     "bank_date": day.isoformat(), "bank_reference": desc[:120],
                                     "notes": "From the ABSA bank statement (CSV)."},
                               headers={**self.headers, "Prefer": "return=representation,resolution=ignore-duplicates"}, timeout=30)
        r.raise_for_status()
        return bool(r.json())

    def set_receipt(self, payment, receipt):
        if self.dry_run:
            return
        day, desc, _ = receipt
        r = self.requests.patch(f"{SUPABASE_URL}/rest/v1/customer_payments", params={"id": f"eq.{payment['id']}"},
                                json={"bank_date": day.isoformat(), "bank_reference": desc[:120]},
                                headers={**self.headers, "Prefer": "return=minimal"}, timeout=30)
        r.raise_for_status()

    def set_bank_date(self, day):
        """The last day the bank statements cover -- what's due in the
        Suppliers app is as at this day (docs/sql/bank_import.sql)."""
        if self.dry_run:
            return True
        r = self.requests.post(f"{SUPABASE_URL}/rest/v1/bank_import", params={"on_conflict": "id"},
                               json={"id": 1, "last_date": day.isoformat(), "imported_at": dt.datetime.now(dt.timezone.utc).isoformat()},
                               headers={**self.headers, "Prefer": "return=minimal,resolution=merge-duplicates"}, timeout=30)
        return r.ok


def last_bank_day(paths):
    """The latest transaction day in the bank CSVs."""
    return max((day for p in paths for day, *_ in read_csv(p)), default=None)


def run(paths, app, log=print):
    suppliers = app.suppliers()
    have = app.existing()
    added = already = 0
    unsure = []
    others = 0
    for day, payee, amount in payments_in(paths):
        supplier, candidates = match_payee(payee, suppliers)
        if supplier is None:
            if candidates:
                unsure.append((day, payee, amount, candidates))
            else:
                others += 1
            continue
        key = (supplier["id"], day.isoformat(), amount)
        if have[key] > 0:
            have[key] -= 1
            already += 1
            continue
        app.add(supplier, day, amount, payee)
        added += 1
        log(f"  {supplier['name']}: {day.isoformat()} R{amount:,.2f} ({payee})")
    # Card purchases at a supplier (Laeveld's till): a payment only when its
    # invoice is on the account -- a till slip (VKB's) never is.
    for day, shop, amount in card_purchases_in(paths):
        supplier, _ = match_payee(shop, suppliers)
        if supplier is None or not app.invoice_for(supplier, day, amount):
            continue
        key = (supplier["id"], day.isoformat(), amount)
        if have[key] > 0:
            have[key] -= 1
            already += 1
            continue
        app.add(supplier, day, amount, f"Card: {shop}")
        added += 1
        log(f"  {supplier['name']}: {day.isoformat()} R{amount:,.2f} (card at the till: {shop})")
    for day, payee, amount, candidates in unsure:
        log(f"  NOT ADDED -- {day.isoformat()} R{amount:,.2f} \"{payee}\" could be: "
            + ", ".join(c["name"] for c in candidates) + " -- type it in on the right account.")
    return added, already, len(unsure), others


def run_buyers(paths, app, log=print):
    """Buyers' deposits added as payments on their accounts: how many new."""
    added = 0
    for c, (day, desc, amount) in buyer_deposits(receipts_in(paths), app.buyers()):
        if app.add_buyer_payment(c, (day, desc, amount)):
            added += 1
            log(f"  {c['name']}: paid {day.isoformat()} R{amount:,.2f} ({desc})")
    return added


def run_receipts(paths, app, log=print):
    """The market agents' payments found in the bank: how many, or None
    when the customers aren't set up."""
    payments = app.unmatched_customer_payments()
    if payments is None:
        return None
    found = match_receipts(receipts_in(paths), payments)
    for p, (day, desc, amount) in found:
        app.set_receipt(p, (day, desc, amount))
        log(f"  {p['name']}: paid {p['pay_date']} R{amount:,.2f} -- in the bank {day.isoformat()} ({desc})")
    return len(found)


def find(paths, text, log=print):
    """The bank lines whose description has [text] in it, and the dates each CSV covers."""
    want = text.lower()
    seen = set()
    for p in paths:
        rows = read_csv(p)
        log(f"  {p.name}: {min(r[0] for r in rows):%d %b %Y} to {max(r[0] for r in rows):%d %b %Y}, {len(rows)} line(s)")
    hits = 0
    for p in paths:
        for day, desc, amount, balance in read_csv(p):
            if want in desc.lower() and (day, desc, amount, balance) not in seen:
                seen.add((day, desc, amount, balance))
                log(f"  {day:%Y-%m-%d}  R{amount:>12,.2f}  {desc}")
                hits += 1
    log(f"{hits} line(s) with \"{text}\".")
    return hits


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("path", help="A bank CSV, or the folder they're in (subfolders too).")
    parser.add_argument("--dry-run", action="store_true", help="Only show what would be added; change nothing.")
    parser.add_argument("--find", metavar="TEXT", help="Only list the bank lines whose description has TEXT in it (and the dates each CSV covers).")
    args = parser.parse_args()
    sys.stdout.reconfigure(line_buffering=True)

    root = pathlib.Path(args.path)
    if not root.exists():
        print(f"PROBLEM: {root} doesn't exist. If it's on an external, USB or network drive, check it's connected.")
        return 1
    paths = [root] if root.is_file() else sorted(p for p in root.rglob("*") if p.suffix.lower() == ".csv")
    paths = [p for p in paths if read_csv(p)]
    if not paths:
        print(f"No ABSA bank CSV (Date, Description, Amount, Balance) found in {root}.")
        return 0
    print(f"{len(paths)} bank CSV(s): " + ", ".join(p.name for p in paths))
    if args.find:
        find(paths, args.find)
        return 0
    try:
        added, already, unsure, others = run(paths, App(dry_run=args.dry_run))
    except Exception as e:
        print(f"PROBLEM: could not reach the app ({e}).")
        return 1
    last = last_bank_day(paths)
    if last:
        app_ok = App(dry_run=args.dry_run).set_bank_date(last)
        print(f"Bank statements up to {last:%d %b %Y}: the Suppliers app shows what's due as at that day."
              if app_ok else "NOTE: run docs/sql/bank_import.sql once so the Suppliers app shows the bank date.")
    try:
        received = run_receipts(paths, App(dry_run=args.dry_run))
    except Exception as e:
        received = None
        print(f"PROBLEM: could not match the market agents' payments ({e}).")
    if received is not None:
        print(f"{received} market agent payment(s) {'would be' if args.dry_run else ''} found in the bank.".replace("  ", " "))
    try:
        bought = run_buyers(paths, App(dry_run=args.dry_run))
        if bought:
            print(f"{bought} buyer payment(s) {'would be ' if args.dry_run else ''}added to their accounts.")
    except Exception as e:
        print(f"PROBLEM: could not add the buyers' payments ({e}).")
    what = "would be added" if args.dry_run else "added"
    print(f"Done: {added} supplier payment(s) {what}, {already} already in the app, {unsure} not sure (listed above), "
          f"{others} other payment(s) not to a supplier left alone.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
