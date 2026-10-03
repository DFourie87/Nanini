#!/usr/bin/env python3
"""
Checks every Eskom account's bills in the Suppliers app, bill by bill:

    py scripts\\check_eskom_bills.py

  1. The balance brought forward = the previous bill's amount due.
  2. Each payment the bill lists is in the bank payments (same amount,
     within a week).
  3. Brought forward - payments + this bill's charges (incl. VAT and
     interest) = the amount due.

Only reads; changes nothing. Bills read before their account summary was
kept: run  py scripts\\fetch_supplier_docs.py --fill-details --reread "Eskom"  first.
"""
import datetime as dt
import sys

from import_sales_report import SUPABASE_URL, _auth_headers

TOLERANCE = 0.05


def _day(s):
    try:
        return dt.date.fromisoformat(s)
    except (TypeError, ValueError):
        return None


def in_bank(paid, payments):
    """The bank payment that fits a payment the bill lists, or None."""
    day = _day(paid.get("date"))
    for p in payments:
        if abs(float(p["amount"]) - float(paid["amount"])) < 0.01:
            pday = _day(p["pay_date"])
            if day is None or pday is None or abs((pday - day).days) <= 7:
                return p
    return None


def check_account(name, bills, payments, log=print, bank_from=None):
    """Returns how many problems; logs one line per bill. [bank_from]: the
    first day the bank payments in the app cover -- earlier payments can't be
    found there and aren't a problem."""
    log(name)
    problems = 0
    prev = None
    used = set()
    for b in sorted(bills, key=lambda x: x["doc_date"]):
        amount = float(b["amount"])
        charges = b.get("purchases_amount")
        bf = b.get("brought_forward")
        paid = b.get("payments_received") or []
        notes = []
        if bf is None or charges is None:
            notes.append("not read in full -- run --fill-details --reread \"Eskom\"")
        else:
            if prev is not None and abs(float(bf) - float(prev["amount"])) > TOLERANCE:
                notes.append(f"brought forward R{float(bf):,.2f} but the previous bill ({prev['doc_date']}) was R{float(prev['amount']):,.2f}")
            total_paid = sum(float(p["amount"]) for p in paid)
            expected = round(float(bf) - total_paid + float(charges), 2)
            if abs(expected - amount) > TOLERANCE:
                notes.append(f"b/f - paid + charges = R{expected:,.2f}, the bill says R{amount:,.2f} (R{amount - expected:,.2f} more)")
        paid_text = []
        for p in paid:
            match = in_bank(p, [x for x in payments if x["id"] not in used])
            if match:
                used.add(match["id"])
                paid_text.append(f"paid R{float(p['amount']):,.2f} {p.get('date') or ''} ok (bank {match['pay_date']})")
            elif bank_from and p.get("date") and p["date"] < bank_from:
                paid_text.append(f"paid R{float(p['amount']):,.2f} {p['date']} (before the bank payments in the app)")
            else:
                paid_text.append(f"paid R{float(p['amount']):,.2f} {p.get('date') or ''} NOT in the bank payments")
                notes.append(f"payment R{float(p['amount']):,.2f} of {p.get('date') or '?'} not in the bank payments")
        status = "OK" if not notes else "CHECK"
        problems += bool(notes)
        due = f"R{amount:,.2f}" if amount >= 0 else f"R{-amount:,.2f} in credit"
        log(f"  {b['doc_date']} {b.get('reference') or ''}: b/f R{float(bf or 0):,.2f}; {'; '.join(paid_text) or 'no payments'}; "
            f"charges R{float(charges or 0):,.2f}; due {due}  {status}")
        for n in notes:
            log(f"      !! {n}")
        prev = b
    later = [p for p in payments if p["id"] not in used and prev is not None and p["pay_date"] > prev["doc_date"]]
    for p in later:
        log(f"  paid since the last bill: R{float(p['amount']):,.2f} on {p['pay_date']} (on the next bill)")
    return problems


def main():
    import requests

    headers = _auth_headers()

    def get(table, **params):
        r = requests.get(f"{SUPABASE_URL}/rest/v1/{table}", params=params, headers=headers, timeout=60)
        r.raise_for_status()
        return r.json()

    sys.stdout.reconfigure(line_buffering=True)
    try:
        suppliers = get("suppliers", select="id,name", name="ilike.eskom*", order="name")
        first = get("supplier_payments", select="pay_date", order="pay_date", limit=1)
        bank_from = first[0]["pay_date"] if first else None
        problems = 0
        for s in suppliers:
            bills = get("supplier_docs", select="id,doc_date,reference,amount,purchases_amount,brought_forward,payments_received,status",
                        supplier_id=f"eq.{s['id']}", kind="eq.statement", order="doc_date")
            payments = get("supplier_payments", select="id,pay_date,amount", supplier_id=f"eq.{s['id']}", order="pay_date")
            problems += check_account(s["name"], bills, payments, bank_from=bank_from)
            print()
    except Exception as e:
        print(f"PROBLEM: could not read the app ({e}).")
        return 1
    print("All Eskom bills tie up." if problems == 0 else f"{problems} bill(s) to check (marked !! above).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
