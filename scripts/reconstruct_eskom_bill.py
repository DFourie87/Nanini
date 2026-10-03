#!/usr/bin/env python3
"""
Works back a missing Eskom bill (one that never arrived) from the bills
either side and the bank payments, and adds it to the Suppliers app as a
clearly marked RECONSTRUCTED entry -- no PDF, not an Eskom document:

    py scripts\\reconstruct_eskom_bill.py --account 6426721839 --month 2026-05 --dry-run
    py scripts\\reconstruct_eskom_bill.py --account 6426721839 --month 2026-05

How it's worked out (VAT 15%, no interest assumed):
  * Amount due        = the next bill's balance brought forward.
  * Payments on it    = bank payments after the previous bill that the next
                        bill doesn't list.
  * Charges incl. VAT = amount due - previous bill's amount due + those payments.
  * Fixed costs       = days between the readings x the per-day tariffs of the
                        next bill (this point's, after the tariff change).
  * Usage             = the rest of the charges excl. VAT / the per-kWh tariffs
                        -> the kWh used.
Lands "to check" in the app: confirm it there. Needs the bills either side
read in full (fetch_supplier_docs.py --fill-details --reread "Eskom").
"""
import argparse
import datetime as dt
import sys

from import_sales_report import SUPABASE_URL, _auth_headers

VAT = 0.15


def _d(s):
    return dt.date.fromisoformat(s) if s else None


def reconstruct(prev, nxt, payments, month):
    """The missing bill between [prev] and [nxt] (rows from supplier_docs)
    as a supplier_docs row (+ "lines"), or raises ValueError saying why."""
    for b, which in ((prev, "previous"), (nxt, "next")):
        if b.get("brought_forward") is None or not b.get("bill_details"):
            raise ValueError(f"the {which} bill ({b['doc_date']}) isn't read in full -- run --fill-details --reread \"Eskom\" first")
    amount = round(float(nxt["brought_forward"]), 2)
    listed = {(round(float(p["amount"]), 2)) for p in nxt.get("payments_received") or []}
    paid = [p for p in payments if prev["doc_date"] < p["pay_date"] <= nxt["doc_date"] and round(float(p["amount"]), 2) not in listed]
    paid_total = round(sum(float(p["amount"]) for p in paid), 2)
    incl = round(amount - float(prev["amount"]) + paid_total, 2)
    excl = round(incl / (1 + VAT), 2)
    vat = round(incl - excl, 2)

    pd, nd = prev["bill_details"], nxt["bill_details"]
    start, end = _d(pd.get("to")), _d(nd.get("from"))
    if not start or not end or end <= start:
        raise ValueError("the reading dates of the bills either side aren't known")
    days = (end - start).days
    charges = nd.get("charges") or []
    # The next bill's own tariffs (on a bill with two tariff periods: the later ones).
    per_day, per_kwh = {}, {}
    for c in charges:
        if c.get("kind") == "fixed" and c.get("unit") == "day":
            per_day[c["description"]] = c["rate"]
        elif c.get("kind") == "usage" and c.get("unit") == "kWh":
            per_kwh[c["description"]] = c["rate"]
    if not per_day or not per_kwh:
        raise ValueError("the next bill has no per-day / per-kWh tariffs to work back with")
    fixed_lines = [{"description": k, "kind": "fixed", "quantity": None, "unit": "day", "rate": r, "days": days,
                    "amount": round(r * days, 2)} for k, r in per_day.items()]
    fixed = round(sum(l["amount"] for l in fixed_lines), 2)
    rate = sum(per_kwh.values())
    kwh = round((excl - fixed) / rate) if excl > fixed else 0
    usage_lines = [{"description": k, "kind": "usage", "quantity": float(kwh), "unit": "kWh", "rate": r, "days": None,
                    "amount": round(r * kwh, 2)} for k, r in per_kwh.items()]
    usage = round(sum(l["amount"] for l in usage_lines), 2)
    # What rounding the kWh leaves over, so the lines add up to the charges.
    rest = round(excl - fixed - usage, 2)
    if rest:
        usage_lines.append({"description": "Rounding (kWh worked back)", "kind": "usage", "quantity": None, "unit": "kWh",
                            "rate": 0.0, "days": None, "amount": rest})
    bill_day = (_d(nxt["doc_date"]).replace(day=1) - dt.timedelta(days=1)).replace(day=min(_d(nxt["doc_date"]).day, 28))
    label = f"Electricity {dt.date.fromisoformat(month + '-01'):%B %Y} (reconstructed)"
    return {
        "kind": "statement",
        "doc_date": bill_day.isoformat(),
        "amount": amount,
        "reference": f"RECONSTRUCTED-{month}",
        "status": "to_check",
        "purchases_amount": incl,
        "vat_amount": vat,
        "description": label,
        "brought_forward": round(float(prev["amount"]), 2),
        "payments_received": [{"date": p["pay_date"], "amount": round(float(p["amount"]), 2)} for p in paid] or None,
        "bill_details": {"kwh": float(kwh), "days": days, "from": start.isoformat(), "to": end.isoformat(),
                         "reading": "reconstructed", "charges": fixed_lines + usage_lines},
        "notes": ("RECONSTRUCTED -- no Eskom bill was received. Worked back from the bills of "
                  f"{prev['doc_date']} and {nxt['doc_date']} and the bank payments; usage from the next bill's tariffs. "
                  "Not an Eskom document."),
        "lines": [{"description": label, "quantity": None, "excl_amount": excl, "vat_amount": vat}],
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--account", required=True, help="The Eskom account number, e.g. 6426721839.")
    parser.add_argument("--month", required=True, help="The missing bill's month, e.g. 2026-05.")
    parser.add_argument("--dry-run", action="store_true", help="Only show what would be added.")
    args = parser.parse_args()
    sys.stdout.reconfigure(line_buffering=True)
    import requests

    headers = _auth_headers()

    def get(table, **params):
        r = requests.get(f"{SUPABASE_URL}/rest/v1/{table}", params=params, headers=headers, timeout=60)
        r.raise_for_status()
        return r.json()

    try:
        sup = get("suppliers", select="id,name", name=f"ilike.eskom*{args.account}*")
        if len(sup) != 1:
            print(f"PROBLEM: no single Eskom supplier with account {args.account} in the app.")
            return 1
        sid = sup[0]["id"]
        bills = get("supplier_docs", select="*", supplier_id=f"eq.{sid}", kind="eq.statement", order="doc_date")
        payments = get("supplier_payments", select="pay_date,amount", supplier_id=f"eq.{sid}", order="pay_date")
        first = args.month + "-01"
        prev = [b for b in bills if b["doc_date"] < first]
        nxt = [b for b in bills if b["doc_date"] >= first]
        if any(b["doc_date"].startswith(args.month) for b in bills):
            print(f"There's already a bill for {args.month} on {sup[0]['name']} -- nothing to do.")
            return 0
        if not prev or not nxt:
            print("PROBLEM: need a bill before and a bill after the missing month.")
            return 1
        row = reconstruct(prev[-1], nxt[0], payments, args.month)
    except ValueError as e:
        print(f"PROBLEM: {e}")
        return 1

    d = row["bill_details"]
    fixed = [c for c in d["charges"] if c["kind"] == "fixed"]
    usage = [c for c in d["charges"] if c["kind"] == "usage" and c["rate"]]
    print(f"{sup[0]['name']}: {row['description']}, dated {row['doc_date']}")
    print(f"  Amount due R{row['amount']:,.2f} (the next bill's balance brought forward)")
    print(f"  Brought forward R{row['brought_forward']:,.2f}; paid " +
          (", ".join(f"R{p['amount']:,.2f} on {p['date']}" for p in row["payments_received"] or []) or "nothing"))
    print(f"  Charges R{row['purchases_amount']:,.2f} incl. VAT = R{row['lines'][0]['excl_amount']:,.2f} + VAT R{row['vat_amount']:,.2f}")
    day_rates = " + ".join("R%.2f" % c["rate"] for c in fixed)
    kwh_rates = " + ".join("R%.4f" % c["rate"] for c in usage)
    print(f"  Fixed: {d['days']} days x ({day_rates}) = R{sum(c['amount'] for c in fixed):,.2f}")
    print(f"  Usage: {d['kwh']:,.0f} kWh x ({kwh_rates}) = R{sum(c['amount'] for c in d['charges'] if c['kind'] == 'usage'):,.2f}")
    print(f"  Readings {d['from']} to {d['to']}")
    if args.dry_run:
        print("Dry run: nothing added.")
        return 0
    lines = row.pop("lines")
    row["supplier_id"] = sid
    r = requests.post(f"{SUPABASE_URL}/rest/v1/supplier_docs", json=row, headers={**headers, "Prefer": "return=representation"}, timeout=30)
    r.raise_for_status()
    doc_id = r.json()[0]["id"]
    r = requests.post(f"{SUPABASE_URL}/rest/v1/supplier_doc_lines", json=[{"doc_id": doc_id, "line_no": 1, **lines[0]}],
                      headers={**headers, "Prefer": "return=minimal"}, timeout=30)
    r.raise_for_status()
    print("Added to the app as \"to check\" (marked RECONSTRUCTED) -- confirm it there.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
