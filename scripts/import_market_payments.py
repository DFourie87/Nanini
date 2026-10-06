#!/usr/bin/env python3
"""
Puts the market agents' payment summaries (afrekeningstate) on their
customer accounts in the hub's Sales app: each payment, and the account
sales it paid.

    python scripts\\import_market_payments.py "D:\\Kliente\\Nanini 121 BK"
    python scripts\\import_market_payments.py "D:\\Kliente\\Nanini 121 BK" --dry-run   # only show

Reads, under the BTW folders (any year):
  * the Joburg agents' payment summaries (..._Sum.pdf) -- Wenpro, Dapper,
    CL de Villiers, Botha Roodt -- saved there by fetch_gmail_invoices.py;
  * RSA's (12683_ACCCHEQS_...pdf), downloaded from Technofresh by hand;
  * Universal Leaf's tobacco invoices (ULSA006606 ...pdf), each its own
    settlement statement;
  * Peppadew's payment advices (30ZZ608.pdf), saved from Gmail. Its payment
    may already be in the app from the bank (the deposit, by
    import_bank_payments.py): the advice's loads then go on that one.
A payment already in the app (same agent, date and amount) is skipped, and
PDFs already dealt with aren't read again (scripts/market_payments_seen.json).
The customers come from customers.sql; an agent that isn't one is listed.
"""
import argparse
import datetime as dt
import json
import pathlib
import re
import sys

from import_sales_report import SUPABASE_URL, ParseError, _auth_headers, extract_pages
from market_statements import parse_statement

SEEN_FILE = pathlib.Path(__file__).with_name("market_payments_seen.json")


def is_candidate(path):
    """A payment summary by its file name."""
    name = path.name.upper()
    # Universal Leaf's invoices: "ULSA006606 - Nanini ...pdf" or "Nanini Boerdery - 6583.pdf",
    # saved from Gmail with the sender's address in the name.
    return (name.endswith("_SUM.PDF") or "_ACCCHEQS_" in name or bool(re.search(r"\bULSA\d+", name))
            or "UNIVERSALLEAF" in name or bool(re.search(r"NANINI BOERDERY - \d+\.PDF$", name))
            # Peppadew's payment advices: "30ZZ608.pdf" (the supplier number), from @peppadew.com.
            or "PEPPADEW" in name or bool(re.search(r"\b30ZZ\d+", name)))


class App:
    def __init__(self, dry_run=False):
        import requests

        self.requests = requests
        self.dry_run = dry_run
        self.headers = _auth_headers()
        r = requests.get(f"{SUPABASE_URL}/rest/v1/customers", params={"select": "id,name,agent"}, headers=self.headers, timeout=30)
        r.raise_for_status()
        self.customers = {c["agent"]: c for c in r.json()}

    def exists(self, customer_id, date, amount):
        r = self.requests.get(
            f"{SUPABASE_URL}/rest/v1/customer_payments",
            params={"select": "id", "customer_id": f"eq.{customer_id}", "pay_date": f"eq.{date}", "amount": f"eq.{amount}"},
            headers=self.headers,
            timeout=30,
        )
        r.raise_for_status()
        return bool(r.json())

    def bank_payment_for(self, customer_id, date, amount):
        """A payment of this amount taken straight from the bank (a buyer's
        deposit, Peppadew) within 15 days of [date]: {'id', 'lines'} or None."""
        day = dt.date.fromisoformat(date)
        r = self.requests.get(f"{SUPABASE_URL}/rest/v1/customer_payments", params=[
            ("select", "id,pay_date,customer_payment_lines(id)"), ("customer_id", f"eq.{customer_id}"), ("amount", f"eq.{amount}"),
            ("method", "eq.bank"), ("pay_date", f"gte.{(day - dt.timedelta(days=15)).isoformat()}"),
            ("pay_date", f"lte.{(day + dt.timedelta(days=15)).isoformat()}")], headers=self.headers, timeout=30)
        r.raise_for_status()
        rows = r.json()
        return {"id": rows[0]["id"], "date": rows[0]["pay_date"], "lines": len(rows[0].get("customer_payment_lines") or [])} if rows else None

    def add(self, customer_id, st, file_name):
        headers = {**self.headers, "Content-Type": "application/json", "Prefer": "return=representation"}
        r = self.requests.post(f"{SUPABASE_URL}/rest/v1/customer_payments", headers=headers, timeout=30, json={
            "customer_id": customer_id,
            "pay_date": st["date"],
            "amount": st["paid"],
            "method": st["method"] or None,
            "file_name": file_name,
        })
        r.raise_for_status()
        payment_id = r.json()[0]["id"]
        self.add_lines(payment_id, st, undo=True)

    def add_lines(self, payment_id, st, undo=False, file_name=None):
        """The account sales the payment paid. [undo]: take the payment out
        again if they can't be saved (not half a payment); [file_name]: kept on it."""
        headers = {**self.headers, "Content-Type": "application/json", "Prefer": "return=representation"}
        lines = [{
            "payment_id": payment_id,
            "line_no": i + 1,
            "report_number": s["account_sale"],
            "delivery_note": s.get("delivery"),
            "received": s.get("received"),
            "sales": s["sales"],
            "deductions": s["deductions"],
            "loans": s.get("loans", 0),
            "nett": s["nett"],
            "qty": s.get("qty"),
        } for i, s in enumerate(st["sales"])]
        r = self.requests.post(f"{SUPABASE_URL}/rest/v1/customer_payment_lines", headers=headers, timeout=30, json=lines)
        if not r.ok and undo:
            # Not half a payment: take it out again, so the next run retries.
            self.requests.delete(f"{SUPABASE_URL}/rest/v1/customer_payments", params={"id": f"eq.{payment_id}"},
                                 headers=self.headers, timeout=30)
        r.raise_for_status()
        if file_name:
            self.requests.patch(f"{SUPABASE_URL}/rest/v1/customer_payments", params={"id": f"eq.{payment_id}"},
                                json={"file_name": file_name}, headers={**self.headers, "Prefer": "return=minimal"}, timeout=30)


def handle(app, path, totals):
    """Returns True when the PDF is dealt with (added, already there, or not a summary)."""
    try:
        st = parse_statement(extract_pages(str(path)), path.name)
    except ParseError as e:
        if str(e).startswith("Not an afrekeningstaat") and not path.name.upper().endswith("_SUM.PDF"):
            totals["other"] += 1
            return True
        # A Joburg agent's payment summary (_Sum.pdf) it can't read yet: listed,
        # and read again next time (not put aside as "not a summary").
        print(f"{path}\n  Could not read this payment summary: {e}")
        totals["failed"].append((path, str(e)))
        return False
    except Exception as e:  # a damaged PDF shouldn't stop the run
        print(f"{path}\n  Could not open this PDF: {e}")
        totals["failed"].append((path, f"Could not open: {e}"))
        return False
    customer = app.customers.get(st["agent"])
    if customer is None:
        print(f"{path}\n  {st['agent']} isn't a customer in the app (run customers.sql) -- not added.")
        totals["failed"].append((path, f"{st['agent']} isn't a customer"))
        return False
    if app.exists(customer["id"], st["date"], st["paid"]):
        totals["there"] += 1
        return True
    sales = ", ".join(s["account_sale"] for s in st["sales"])
    # A buyer's deposit already taken from the bank (Peppadew): its loads go on it.
    bank = app.bank_payment_for(customer["id"], st["date"], st["paid"])
    if bank is not None:
        if bank["lines"]:
            totals["there"] += 1
            return True
        print(f"{customer['name']}: R{st['paid']:,.2f} in the bank {bank['date']} -- account sales {sales}"
              f"{'  (dry run, not added)' if app.dry_run else ''}")
        if not app.dry_run:
            app.add_lines(bank["id"], st, file_name=path.name)
        totals["added"] += 1
        return not app.dry_run
    print(f"{customer['name']}: paid {st['date']} R{st['paid']:,.2f} -- account sales {sales}"
          f"{'  (dry run, not added)' if app.dry_run else ''}")
    if not app.dry_run:
        app.add(customer["id"], st, path.name)
    totals["added"] += 1
    return not app.dry_run


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("folder", help="The client folder, e.g. D:\\Kliente\\Nanini 121 BK")
    parser.add_argument("--dry-run", action="store_true", help="Only show what would be added; change nothing.")
    parser.add_argument("--rescan", action="store_true", help="Read every summary again, including ones already dealt with.")
    args = parser.parse_args()
    sys.stdout.reconfigure(line_buffering=True)

    folder = pathlib.Path(args.folder)
    if not folder.is_dir():
        print(f"PROBLEM: {folder} doesn't exist -- check the drive is connected.")
        return 1
    paths = sorted(p for p in folder.rglob("*.pdf")
                   if is_candidate(p) and any(part.lower() == "btw" for part in p.relative_to(folder).parts[:-1]))
    try:
        seen = {} if args.rescan else json.loads(SEEN_FILE.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        seen = {}
    app = App(dry_run=args.dry_run)
    totals = {"added": 0, "there": 0, "other": 0, "unchanged": 0, "failed": []}
    for p in paths:
        key = str(p.resolve())
        stamp = f"{p.stat().st_size}:{int(p.stat().st_mtime)}"
        if seen.get(key) == stamp:
            totals["unchanged"] += 1
            continue
        if handle(app, p, totals):
            seen[key] = stamp
    if not args.dry_run:
        try:
            SEEN_FILE.write_text(json.dumps(seen), encoding="utf-8")
        except OSError as e:
            print(f"WARNING: could not save {SEEN_FILE.name} ({e}).")
    print(f"\nDone: {totals['added']} payment(s) {'to add' if args.dry_run else 'added'}, {totals['there']} already in the app, "
          f"{totals['other']} not payment summaries, {totals['unchanged']} unchanged since the last run.")
    if totals["failed"]:
        print(f"\nNEEDS A LOOK -- {len(totals['failed'])}:")
        for p, why in totals["failed"]:
            print(f"  {p}\n      -> {why}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
