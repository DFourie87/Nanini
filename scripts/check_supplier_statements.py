#!/usr/bin/env python3
"""
Checks a supplier's statements against the invoices, credit notes and
payments in the Suppliers app, month by month:

    py scripts\\check_supplier_statements.py VKB
    py scripts\\check_supplier_statements.py VKB --detail     # VKB: invoice by invoice
    py scripts\\check_supplier_statements.py Omnia

For each statement: the previous statement's balance + invoices on account
(not cash sales) - credit notes - payments since = what the statement should
say. The difference is what the supplier charged without an invoice here
(VKB: interest, credit insurance) -- or an invoice or payment missing.

Only reads; changes nothing. Documents still "to check" in the app are
counted too, and marked.
"""
import re
import sys

from import_sales_report import SUPABASE_URL, _auth_headers

# A VKB statement's account line: "030826 PBMO FT-153589 TOP LINK ... 1 370.04 18 306.58 S"
# (date ddmmyy, branch, document, ..., the document's total, the balance).
# Other documents (a payment, a journal, ...) have other codes, e.g. "BET-1234".
VKB_LINE = re.compile(r"^`?\s*(\d{6})\s+([A-Z]{4})\s+([A-Z]{2,4}-\d+)\s+(.*)$")


def statement_lines(text):
    """VKB: the documents on the account part of the statement:
    [(key e.g. "PBMO153589" or "IJB-84787", date yyyy-mm-dd, amount, text)].
    Stops at the cash sales ("KONTANTTRANSAKSIES")."""
    from fetch_supplier_docs import amounts_in

    out = []
    for line in text.splitlines():
        if "KONTANTTRANSAKSIES" in line.upper() or "SEKURITEIT AANDEELHOUERSLENINGS" in line.upper() and out:
            break
        m = VKB_LINE.match(line.strip())
        if not m or "BAL O/B" in line:
            continue
        vals = amounts_in(m.group(4))
        if len(vals) < 2:
            continue
        d = m.group(1)
        doc = m.group(3)
        key = m.group(2) + doc.split("-", 1)[1] if doc.startswith("FT-") else doc
        out.append((key, f"20{d[4:6]}-{d[2:4]}-{d[0:2]}", round(vals[-2], 2), " ".join(m.group(4).split()[:6])))
    return out


def compare(on_statement, app_docs, log=print):
    """What's on the statement but not in the app, and the other way round."""
    def key(ref):
        return re.sub(r"[^A-Z0-9]", "", (ref or "").upper())

    in_app = {}
    for d in app_docs:
        k = key(d.get("reference"))
        if k in in_app:
            log(f"      {d.get('reference')} {d['doc_date']}: R{float(d['amount']):,.2f} is in the app TWICE -- delete the extra one")
        in_app[k] = d
    listed = set()
    charges = 0.0
    for k, day, amount, text in on_statement:
        if not k.startswith(("FT", "IJB", "KT")) and "-" in k:
            log(f"      {k} {day}: R{amount:,.2f} {text} (not an invoice or VKB charge -- a payment or journal?)")
        elif not k.startswith(("IJB", "KT")) and key(k) in in_app:
            listed.add(key(k))
            d = in_app[key(k)]
            if abs(float(d["amount"]) - amount) > 0.01:
                log(f"      {k} {day}: R{amount:,.2f} on the statement, R{float(d['amount']):,.2f} in the app")
        elif k.startswith("IJB"):
            charges += amount
            log(f"      {k} {day}: R{amount:,.2f} {text} (VKB's own charge -- no invoice)")
        else:
            log(f"      {k} {day}: R{amount:,.2f} on the statement -- NOT in the app")
    for k, d in in_app.items():
        if k not in listed:
            log(f"      {d.get('reference')} {d['doc_date']}: R{float(d['amount']):,.2f} in the app -- NOT on this statement"
                + (" (cash sale?)" if not d.get("cash_sale") else ""))
    return round(charges, 2)


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
    detail = "--detail" in sys.argv
    if detail:
        sys.argv.remove("--detail")
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
            docs = get("supplier_docs", select="doc_date,kind,amount,reference,status,cash_sale,notes,file_path,file_name",
                       supplier_id=f"eq.{s['id']}", order="doc_date")
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
            if detail:
                from fetch_supplier_docs import App, read_pdf

                app = App()
                st = sorted(statements, key=lambda x: x["doc_date"])
                for prev, cur in zip(st, st[1:]):
                    if not cur.get("file_path"):
                        continue
                    print(f"  Statement {cur['doc_date']} line by line:")
                    lines = statement_lines(read_pdf(app.download(cur["file_path"])))
                    month = [d for d in docs if prev["doc_date"] < d["doc_date"] <= cur["doc_date"]
                             and d["kind"] in ("invoice", "credit_note") and not d.get("cash_sale")]
                    charges = compare(lines, month)
                    print(f"      VKB's own charges (interest, insurance): R{charges:,.2f}")
                print()
    except Exception as e:
        print(f"PROBLEM: could not read the app ({e}).")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
