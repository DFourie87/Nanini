#!/usr/bin/env python3
"""
Checks a supplier's statements against the invoices, credit notes and
payments in the Suppliers app, month by month:

    py scripts\\check_supplier_statements.py VKB
    py scripts\\check_supplier_statements.py Omnia

For each statement: the previous statement's balance + invoices on account
(not cash sales) - credit notes - payments since = what the statement should
say. The difference is what the supplier charged without an invoice here
(VKB: interest, credit insurance) -- or an invoice or payment missing.

Only reads; changes nothing. Documents still "to check" in the app are
counted too, and marked.
"""
import sys

from import_sales_report import SUPABASE_URL, _auth_headers


def check(statements, docs, payments, log=print, tolerance=1.0):
    """Returns the differences [(statement date, difference)]; logs a block per statement."""
    out = []
    statements = sorted(statements, key=lambda s: s["doc_date"])
    for prev, cur in zip(statements, statements[1:]):
        a, b = prev["doc_date"], cur["doc_date"]
        between = [d for d in docs if a < d["doc_date"] <= b]
        inv = [d for d in between if d["kind"] == "invoice" and not d.get("cash_sale")]
        cn = [d for d in between if d["kind"] == "credit_note" and not d.get("cash_sale")]
        cash = [d for d in between if d.get("cash_sale")]
        paid = [p for p in payments if a < p["pay_date"] <= b]
        to_check = sum(1 for d in inv + cn if d.get("status") == "to_check")
        expected = round(float(prev["amount"]) + sum(float(d["amount"]) for d in inv)
                         - sum(float(d["amount"]) for d in cn) - sum(float(p["amount"]) for p in paid), 2)
        diff = round(float(cur["amount"]) - expected, 2)
        out.append((b, diff))
        log(f"  Statement {b}: R{float(cur['amount']):,.2f}" + ("  OK" if abs(diff) <= tolerance else f"  -- R{diff:,.2f} more than ours" if diff > 0 else f"  -- R{-diff:,.2f} less than ours"))
        log(f"      previous R{float(prev['amount']):,.2f} + {len(inv)} invoice(s) R{sum(float(d['amount']) for d in inv):,.2f}"
            f" - {len(cn)} credit note(s) R{sum(float(d['amount']) for d in cn):,.2f}"
            f" - payments R{sum(float(p['amount']) for p in paid):,.2f}"
            + "".join(f" ({p['pay_date']} R{float(p['amount']):,.2f})" for p in paid)
            + f" = R{expected:,.2f}")
        if cash:
            log(f"      (+ {len(cash)} cash sale(s) R{sum(float(d['amount']) for d in cash):,.2f} paid at the till -- not on the account)")
        if to_check:
            log(f"      ({to_check} of these still to check in the app)")
    return out


def main():
    if len(sys.argv) < 2:
        print('Which supplier? e.g.  py scripts\\check_supplier_statements.py VKB')
        return 1
    import requests

    headers = _auth_headers()

    def get(table, **params):
        r = requests.get(f"{SUPABASE_URL}/rest/v1/{table}", params=params, headers=headers, timeout=60)
        r.raise_for_status()
        return r.json()

    sys.stdout.reconfigure(line_buffering=True)
    try:
        for s in get("suppliers", select="id,name", name=f"ilike.{sys.argv[1]}*", order="name"):
            docs = get("supplier_docs", select="doc_date,kind,amount,reference,status,cash_sale,notes", supplier_id=f"eq.{s['id']}", order="doc_date")
            docs = [d for d in docs if "NOTICE" not in (d.get("notes") or "")]
            payments = get("supplier_payments", select="pay_date,amount", supplier_id=f"eq.{s['id']}", order="pay_date")
            statements = [d for d in docs if d["kind"] == "statement"]
            print(s["name"])
            if len(statements) < 2:
                print("  Fewer than two statements -- nothing to check yet.")
                continue
            diffs = check(statements, docs, payments)
            print(f"  Differences together: R{sum(d for _, d in diffs):,.2f}")
            print()
    except Exception as e:
        print(f"PROBLEM: could not read the app ({e}).")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
