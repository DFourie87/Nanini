#!/usr/bin/env python3
"""
Checks a supplier's statements against the invoices, credit notes and
payments in the Suppliers app, month by month:

    py scripts\\check_supplier_statements.py VKB
    py scripts\\check_supplier_statements.py VKB --detail     # VKB: invoice by invoice
    py scripts\\check_supplier_statements.py Omnia
    py scripts\\check_supplier_statements.py VKB --add-charges [--dry-run]
    py scripts\\check_supplier_statements.py VKB --add-missing [--dry-run]

--add-charges: VKB's own charges on each statement (IJB-...: interest,
credit insurance) are added to the app as invoices, so the account ties
up, with their contra account: credit insurance 3850/000, interest
3680/000 (CHARGE_ACCOUNTS). Each once only; no VAT on them.
--add-missing: an invoice on a statement that isn't in the app is made
from the statement's lines (items, amounts excl. VAT, VAT), marked as
recreated from the statement -- no invoice PDF.

For each statement: the previous statement's balance + invoices on account
(not cash sales) - credit notes - payments since = what the statement should
say. The difference is what the supplier charged without an invoice here
(VKB: interest, credit insurance) -- or an invoice or payment missing.

Without --add-charges, only reads; changes nothing. Documents still "to check" in the app are
counted too, and marked.
"""
import re
import sys

from import_sales_report import SUPABASE_URL, _auth_headers

# A VKB statement's account line: "030826 PBMO FT-153589 TOP LINK ... 1 370.04 18 306.58 S"
# (date ddmmyy, branch, document, ..., the document's total, the balance).
# Other documents (a payment, a journal, ...) have other codes, e.g. "BET-1234".
VKB_LINE = re.compile(r"^`?\s*(\d{6})\s+([A-Z]{4})\s+([A-Z]{2,4}-\d+)\s+(.*)$")

# VKB's own charges on the statement and their contra account.
CHARGE_ACCOUNTS = (("KREDIETVERSEKERING", "3850/000"), ("RENTE", "3680/000"), ("AANSPORINGSKORT", "1954/000"))
# Accounts not in the chart loaded from GL_Codes.xlsx: added to the app when first used.
NEW_ACCOUNTS = {"1954/000": "Discount Received"}

# An item on a VKB statement: "LK`S GRID BRAAI BIG BOX S/ST 010384 1.00 923.21 MD 138.48 ..."
# (description, card no., quantity, amount excl. VAT, MD, [VAT]).
_AMT = r"\d{1,3}(?: \d{3})*\.\d{2}"
VKB_ITEM = re.compile(rf"^(?P<desc>.*?)\s+\d{{6}}\s+(?P<qty>-?\d+\.\d+)\s+(?P<amt>{_AMT})(?P<neg>-?)\s+MD\b(?P<rest>.*)$")


def vkb_amounts(text):
    """The amounts on a VKB line. A credit there ends in "-" ("1 021.79-"),
    which must not make the next amount negative ("1 021.79- 30 778.28")."""
    from fetch_supplier_docs import amounts_in

    return amounts_in(re.sub(r"(\.\d{2})-(?=\s|$)", r"\1CR", text))


def statement_lines(text):
    """VKB: the documents on the account part of the statement:
    [(key e.g. "PBMO153589" or "IJB-84787", date yyyy-mm-dd, amount, text)].
    Stops at the cash sales ("KONTANTTRANSAKSIES")."""
    out = []
    for line in text.splitlines():
        if "KONTANTTRANSAKSIES" in line.upper() or "SEKURITEIT AANDEELHOUERSLENINGS" in line.upper() and out:
            break
        m = VKB_LINE.match(line.strip())
        if not m or "BAL O/B" in line:
            continue
        vals = vkb_amounts(m.group(4))
        if len(vals) < 2:
            continue
        d = m.group(1)
        doc = m.group(3)
        key = m.group(2) + doc.split("-", 1)[1] if doc.startswith("FT-") else doc
        out.append((key, f"20{d[4:6]}-{d[2:4]}-{d[0:2]}", round(vals[-2], 2), " ".join(m.group(4).split())))
    return out


def charge_docs(on_statement, statement_date):
    """VKB's own charges (IJB-...: no VAT) and credit notes (KN-..., e.g. the
    cash-purchase incentive "AANSPORINGSKORT KONTANT": VAT as on the line) on
    a statement as documents for the app:
    [{kind, doc_date, amount, reference, description, vat_amount, notes, lines}]."""
    out = []
    for k, day, amount, text in on_statement:
        if not k.startswith(("IJB", "KN-")) or not amount:
            continue
        name = re.sub(r"\s+(MD|ID)$", "", re.split(r"\s+-?\d", text)[0].strip()) or k
        account = next((a for word, a in CHARGE_ACCOUNTS if word in name.upper()), None)
        vals = vkb_amounts(text)
        # A credit note's line: VAT, total, total, balance.
        vat = round(abs(vals[0]), 2) if k.startswith("KN-") and len(vals) >= 4 else 0.0
        out.append({
            "kind": "invoice" if amount > 0 else "credit_note",
            "doc_date": day,
            "amount": abs(amount),
            "reference": k,
            "description": name,
            "vat_amount": vat,
            "notes": (f"VKB's own charge, from the statement of {statement_date} (no invoice)." if k.startswith("IJB")
                      else f"VKB credit note, from the statement of {statement_date}."),
            "lines": [{"description": name, "quantity": None, "excl_amount": round(abs(amount) - vat, 2), "vat_amount": vat,
                       "gl_account": account}],
        })
    return out


def statement_invoices(text):
    """VKB: the invoices on a statement with their items:
    {"PBAH64094": {"reference", "doc_date", "amount", "vat_paid", "items": [{description, quantity, excl_amount, vat_amount}]}}."""
    out = {}
    cur = None

    def item(part, header):
        m = VKB_ITEM.match(" ".join(part.split()))
        if not m:
            return None
        sign = -1 if m["neg"] else 1
        after = vkb_amounts(m["rest"])
        # The invoice's first line also ends with the invoice total and the balance.
        vat = after[0] if len(after) == (3 if header else 1) else 0.0
        return {"description": m["desc"].strip(), "quantity": float(m["qty"]),
                "excl_amount": round(sign * float(m["amt"].replace(" ", "")), 2), "vat_amount": round(vat, 2)}

    for line in text.splitlines():
        if "KONTANTTRANSAKSIES" in line.upper():
            break
        m = VKB_LINE.match(line.strip())
        if m:
            cur = None
            if m.group(3).startswith("FT-"):
                vals = vkb_amounts(m.group(4))
                d = m.group(1)
                ref = m.group(2) + m.group(3).split("-", 1)[1]
                cur = out[ref] = {"reference": ref, "doc_date": f"20{d[4:6]}-{d[2:4]}-{d[0:2]}",
                                  "amount": round(vals[-2], 2) if len(vals) >= 2 else None, "vat_paid": None, "items": []}
                it = item(m.group(4), True)
                if it:
                    cur["items"].append(it)
            continue
        if cur is None:
            continue
        rest = line.strip().lstrip("`").strip()
        if rest.upper().startswith("BTW BETAAL"):
            vals = vkb_amounts(rest)
            cur["vat_paid"] = vals[1] if len(vals) >= 2 else None
            continue
        it = item(rest, False)
        if it:
            cur["items"].append(it)
    return out


def invoice_from_statement(inv, statement_date):
    """A missing invoice as a document for the app, or (None, why not)."""
    excl = round(sum(i["excl_amount"] for i in inv["items"]), 2)
    vat = round(sum(i["vat_amount"] for i in inv["items"]), 2)
    if not inv["items"] or inv["amount"] is None or abs(excl + vat - inv["amount"]) > 0.01:
        return None, f"its lines (R{excl:,.2f} + VAT R{vat:,.2f}) don't add up to its total R{inv['amount'] or 0:,.2f}"
    if inv["vat_paid"] is not None and abs(inv["vat_paid"] - vat) > 0.01:
        return None, f"the VAT on its lines R{vat:,.2f} isn't the VAT paid R{inv['vat_paid']:,.2f}"
    return {
        "kind": "invoice",
        "doc_date": inv["doc_date"],
        "amount": inv["amount"],
        "reference": inv["reference"],
        "vat_amount": vat,
        "description": inv["items"][0]["description"] + (f" + {len(inv['items']) - 1} more" if len(inv["items"]) > 1 else ""),
        "notes": f"RECREATED from VKB's statement of {statement_date} (no invoice PDF): items, amounts and VAT as on the statement.",
        "lines": [{**i, "gl_account": None} for i in inv["items"]],
    }, None


def balance_gaps(text):
    """VKB: follows the statement's running balance line by line; where a
    line's balance isn't the one before + its amount, something between
    wasn't read: [(the document after the gap, date, the gap)]."""
    out = []
    bal = None
    for line in text.splitlines():
        if "KONTANTTRANSAKSIES" in line.upper():
            break
        if "BAL O/B" in line:
            vals = vkb_amounts(line)
            bal = vals[-1] if vals else None
            continue
        m = VKB_LINE.match(line.strip())
        if not m or bal is None:
            continue
        vals = vkb_amounts(m.group(4))
        d = m.group(1)
        day = f"20{d[4:6]}-{d[2:4]}-{d[0:2]}"
        if len(vals) < 2:
            out.append((m.group(3), day, None))
            continue
        if len(vals) >= 3:  # ends with the balance
            gap = round(vals[-1] - (bal + vals[-2]), 2)
            if abs(gap) > 0.01:
                out.append((m.group(3), day, gap))
            bal = vals[-1]
        else:
            bal += vals[-2]
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
        if k.startswith("KW-"):
            log(f"      {k} {day}: R{-amount:,.2f} paid (VKB's receipt -- in the bank payments)")
        elif k.startswith("KN-"):
            listed.add(key(k))
            log(f"      {k} {day}: {text} (VKB credit note -- " + ("in the app)" if key(k) in in_app else "NOT in the app: --add-charges)"))
        elif not k.startswith(("FT", "IJB", "KT")) and "-" in k:
            log(f"      {k} {day}: R{amount:,.2f} {text} (not an invoice or VKB charge -- a payment or journal?)")
        elif k.startswith("IJB") and key(k) in in_app:
            listed.add(key(k))
            charges += amount
            log(f"      {k} {day}: R{amount:,.2f} {text} (VKB's own charge -- in the app)")
        elif not k.startswith(("IJB", "KT")) and key(k) in in_app:
            listed.add(key(k))
            d = in_app[key(k)]
            if abs(float(d["amount"]) - amount) > 0.01:
                log(f"      {k} {day}: R{amount:,.2f} on the statement, R{float(d['amount']):,.2f} in the app")
        elif k.startswith("IJB"):
            charges += amount
            log(f"      {k} {day}: R{amount:,.2f} {text} (VKB's own charge -- not in the app yet: --add-charges)")
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
    flags = {f for f in ("--detail", "--add-charges", "--add-missing", "--dry-run") if f in sys.argv}
    for f in flags:
        sys.argv.remove(f)
    detail, add_charges, dry_run = "--detail" in flags, "--add-charges" in flags, "--dry-run" in flags
    add_missing = "--add-missing" in flags
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
            print(s["name"])
            if add_charges or add_missing:
                add_statement_charges(s, get, headers, dry_run, charges=add_charges, missing=add_missing)
            docs = get("supplier_docs", select="doc_date,kind,amount,reference,status,cash_sale,notes,file_path,file_name",
                       supplier_id=f"eq.{s['id']}", order="doc_date")
            docs = [d for d in docs if "NOTICE" not in (d.get("notes") or "")]
            payments = get("supplier_payments", select="pay_date,amount", supplier_id=f"eq.{s['id']}", order="pay_date")
            statements = [d for d in docs if d["kind"] == "statement"]
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
                    text = read_pdf(app.download(cur["file_path"]))
                    lines = statement_lines(text)
                    for doc, day, gap in balance_gaps(text):
                        print(f"      !! {doc} {day}: " + ("its amount couldn't be read" if gap is None else
                              f"the balance jumps R{gap:,.2f} more than the lines before it -- a line the check didn't read"))
                        # The statement's lines just before it and its own, as printed.
                        rows = text.splitlines()
                        at = next((i for i, r in enumerate(rows) if doc in r), None)
                        if at is not None:
                            for r in rows[max(0, at - 3):at + 8]:
                                print(f"         | {r.strip()}")
                    month = [d for d in docs if prev["doc_date"] < d["doc_date"] <= cur["doc_date"]
                             and d["kind"] in ("invoice", "credit_note") and not d.get("cash_sale")]
                    charges = compare(lines, month)
                    print(f"      VKB's own charges (interest, insurance): R{charges:,.2f}")
                print()
    except Exception as e:
        print(f"PROBLEM: could not read the app ({e}).")
        return 1
    return 0


def add_statement_charges(supplier, get, headers, dry_run, log=print, charges=True, missing=False):
    """--add-charges: VKB's own charges on [supplier]'s statements into the
    app; --add-missing: the invoices on them that aren't in the app."""
    import requests
    from fetch_supplier_docs import App, read_pdf

    app = App(dry_run=dry_run)
    have = {d["reference"]: d["id"] for d in get("supplier_docs", select="id,reference", supplier_id=f"eq.{supplier['id']}", reference="not.is.null")}
    have_keys = {re.sub(r"[^A-Z0-9]", "", r.upper()) for r in have}
    names = {a["code"]: a["name"] for a in get("gl_accounts", select="code,name")}
    accounts = set(names)
    # An account added earlier under another name: its name now.
    for code, name in NEW_ACCOUNTS.items():
        if code in names and names[code] != name and not dry_run:
            r = requests.patch(f"{SUPABASE_URL}/rest/v1/gl_accounts", params={"code": f"eq.{code}"}, json={"name": name},
                               headers={**headers, "Prefer": "return=minimal"}, timeout=30)
            r.raise_for_status()
            log(f"  GL account {code} renamed to {name}.")
    added = 0

    def ensure_account(code):
        if code in NEW_ACCOUNTS and code not in accounts and not dry_run:
            r = requests.post(f"{SUPABASE_URL}/rest/v1/gl_accounts", json={"code": code, "name": NEW_ACCOUNTS[code]},
                              headers={**headers, "Prefer": "return=minimal,resolution=merge-duplicates"}, timeout=30)
            r.raise_for_status()
            accounts.add(code)
            log(f"  Added GL account {code} {NEW_ACCOUNTS[code]}.")

    statements = get("supplier_docs", select="doc_date,file_path", supplier_id=f"eq.{supplier['id']}", kind="eq.statement", order="doc_date")
    for n, st in enumerate(statements):
        if not st.get("file_path"):
            continue
        text = read_pdf(app.download(st["file_path"]))
        docs = charge_docs(statement_lines(text), st["doc_date"]) if charges else []
        # The first statement's invoices are before the account's start in the app (its balance is the opening one).
        if missing and n > 0:
            for ref, inv in statement_invoices(text).items():
                if ref in have_keys:
                    continue
                doc, why = invoice_from_statement(inv, st["doc_date"])
                if doc:
                    docs.append(doc)
                else:
                    log(f"  {ref} {inv['doc_date']}: not added -- {why}")
        for doc in docs:
            line = doc["lines"][0]
            if doc["reference"] in have:
                # Already in the app: its contra, if it has none yet.
                if line["gl_account"]:
                    ensure_account(line["gl_account"])
                    if not dry_run:
                        r = requests.patch(f"{SUPABASE_URL}/rest/v1/supplier_doc_lines", json={"gl_account": line["gl_account"]},
                                           params={"doc_id": f"eq.{have[doc['reference']]}", "gl_account": "is.null"},
                                           headers={**headers, "Prefer": "return=representation"}, timeout=30)
                        r.raise_for_status()
                        if r.json():
                            log(f"  {doc['reference']} {doc['description']}: contra set to {line['gl_account']}")
                continue
            log(f"  {'Would add' if dry_run else 'Adding'} {doc['reference']} {doc['doc_date']}: R{doc['amount']:,.2f} "
                f"{doc['description']}{' (credit note, VAT R%.2f)' % doc['vat_amount'] if doc['kind'] == 'credit_note' else ''}"
                f" -> {line['gl_account'] or 'contra not known: allocate it in Purchases'}")
            if not doc["reference"].startswith(("IJB", "KN-")):
                for i in doc["lines"]:
                    log(f"      {i['quantity']:g} x {i['description']}: R{i['excl_amount']:,.2f} + VAT R{i['vat_amount']:,.2f}")
            added += 1
            if dry_run:
                continue
            if line["gl_account"]:
                ensure_account(line["gl_account"])
            lines = doc.pop("lines")
            have_keys.add(re.sub(r"[^A-Z0-9]", "", doc["reference"].upper()))
            row = {**doc, "supplier_id": supplier["id"], "status": "confirmed",
                   "email_key": f"statement-charge:{supplier['id']}:{doc['reference']}"}
            r = requests.post(f"{SUPABASE_URL}/rest/v1/supplier_docs", json=row, headers={**headers, "Prefer": "return=representation"}, timeout=30)
            if r.status_code == 409:
                continue  # already there
            r.raise_for_status()
            app.add_lines(r.json()[0]["id"], lines)
    log(f"  {added} document(s) {'to add (dry run: nothing added)' if dry_run else 'added'}." if added
        else "  Nothing to add: all already in the app.")


if __name__ == "__main__":
    sys.exit(main())
