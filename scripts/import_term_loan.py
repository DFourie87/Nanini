#!/usr/bin/env python3
"""
Reads ABSA's term loan statements (PDF, account 3053810190, FlexiReserve)
into the hub: Financials > Term loan shows the working paper and saves the
lines as a CSV for Xero's TERMLOAN bank account.

    py scripts\\import_term_loan.py "D:\\Kliente\\Nanini 121 BK"
    py scripts\\import_term_loan.py "D:\\Kliente\\Nanini 121 BK\\2027\\Bank\\Term Loan\\Term Loan 17112026.pdf" --dry-run

How it works:
  * Every PDF in a "Term Loan" folder under the folder given (any year's
    Bank\\Term Loan), or the one file given, is read.
  * From each statement: its date and period, the outstanding capital
    balance, the prepaid amount (Arrear/Advance), the interest rate and the
    next instalment -- and its transactions (date, description, amount).
  * A statement already in the hub is left alone (its lines may have been
    adjusted or sent to Xero there). Run it again any time: only new
    statements are added.

Needs docs/sql/term_loan.sql run once, and the Supabase secret key
(scripts/supabase_secret_key.txt) like the sales import.
"""
import argparse
import datetime as dt
import pathlib
import re
import sys

MONEY = r"-?\d{1,3}(?: \d{3})*\.\d{2}"
LINE_RE = re.compile(rf"^\s*(\d{{4}})/(\d{{2}})/(\d{{2}})\s+(.+?)\s+({MONEY})\s+({MONEY})\s+({MONEY})\s*$")
MONTHS = {m: i for i, m in enumerate(["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"], 1)}


class NotAStatement(Exception):
    pass


def money(text):
    return round(float(text.replace(" ", "").replace(",", "")), 2)


def day(text):
    """'17 Nov 2026' -> date."""
    d, m, y = text.split()
    return dt.date(int(y), MONTHS[m[:3].lower()], int(d))


def _find(pattern, text, required=True):
    m = re.search(pattern, text, re.I)
    if not m and required:
        raise NotAStatement(f"no {pattern!r}")
    return m


def parse_statement(text):
    """The statement's figures and transactions, from its text."""
    if "Term loan statement" not in text:
        raise NotAStatement("not an ABSA term loan statement")
    period = _find(r"Statement period:\s*(\d{1,2} \w{3} \d{4})\s*-\s*(\d{1,2} \w{3} \d{4})", text)
    payable = _find(rf"Amount Payable on\s*(\d{{1,2}} \w{{3}} \d{{4}})\s*\(including fees\)\s*({MONEY})", text, required=False)
    rate = _find(r"Annual interest rate\s+(\d+(?:\.\d+)?)%", text, required=False)
    portion = _find(r"Interest Portion\s+(-?[\d, ]+\.\d{2})", text, required=False)
    benefit = _find(r"Interest benefit on prepaid amount\s+(-?[\d, ]+\.\d{2})", text, required=False)
    lines = []
    for raw in text.splitlines():
        m = LINE_RE.match(raw)
        if m:
            y, mo, d, what, amount, _, _ = m.groups()
            lines.append({"line_date": dt.date(int(y), int(mo), int(d)).isoformat(), "description": what.strip(), "amount": money(amount)})
    return {
        "account_no": _find(r"account number\s+(\d{6,})", text).group(1),
        "statement_date": day(_find(r"Statement date:\s*(\d{1,2} \w{3} \d{4})", text).group(1)).isoformat(),
        "period_from": day(period.group(1)).isoformat(),
        "period_to": day(period.group(2)).isoformat(),
        "capital": money(_find(rf"Outstanding capital balance\s+R?({MONEY})", text).group(1)),
        "advance": money(_find(rf"Arrear/Advance\s+({MONEY})", text).group(1)),
        "interest_rate": float(rate.group(1)) if rate else None,
        # The month's interest on the capital, and the interest benefit on the prepaid amount.
        "interest_portion": money(portion.group(1)) if portion else None,
        "interest_benefit": money(benefit.group(1)) if benefit else None,
        "amount_payable": money(payable.group(2)) if payable else None,
        "payable_date": day(payable.group(1)).isoformat() if payable else None,
        "lines": lines,
    }


# A transfer between the ABSA current account and the loan on the bank statement:
# "DIGITAL TRANSF DT 30-5381-0190 ABSA BANK Nanini Term Loan".
LOAN_RE = re.compile(r"30-?5381-?0190|3053810190|\bterm\s*loan\b", re.I)


def bank_transfers(root):
    """The transfers to and from the loan in the ABSA current account's CSVs
    under [root] (any folder), each once: [(date, amount for the loan, description)]
    -- paid into the loan is plus (minus on the current account)."""
    from import_bank_payments import read_csv

    p = pathlib.Path(root)
    paths = [p] if p.is_file() else sorted(f for f in p.rglob("*") if f.suffix.lower() == ".csv")
    seen, out = set(), []
    for path in paths:
        for day, desc, amount, balance in read_csv(path):
            if not LOAN_RE.search(desc):
                continue
            # The same transaction in two CSVs: the same day, amount and balance after it.
            key = (day, amount, balance) if balance else (day, desc, amount)
            if key in seen:
                continue
            seen.add(key)
            out.append((day.isoformat(), round(-amount, 2), " ".join(desc.split())))
    return sorted(out)


def missing_transfers(transfers, statements, lines):
    """The bank's transfers no statement shows: each goes on the statement whose
    period has its day, unless a line of the same amount is within 3 days
    (on the statement, or added before). Transfers after the last statement
    wait for theirs. [statements]: id, period_from, period_to, statement_date;
    [lines]: line_date, amount."""
    def near(a, b):
        return abs((dt.date.fromisoformat(a) - dt.date.fromisoformat(b)).days) <= 3

    out = []
    for day, amount, desc in transfers:
        if any(abs(float(l["amount"]) - amount) < 0.005 and near(l["line_date"], day) for l in lines):
            continue
        covering = [s for s in statements if (s.get("period_from") or s["statement_date"]) <= day <= (s.get("period_to") or s["statement_date"])]
        if not covering:
            continue
        s = min(covering, key=lambda x: x["statement_date"])
        what = "Paid into the loan from the ABSA current account" if amount > 0 else "Drawn into the ABSA current account"
        out.append({"statement_id": s["id"], "line_date": day, "description": f"{what} (bank statement: {desc})", "amount": amount, "manual": True})
    return out


def add_missing_transfers(root, dry_run=False):
    """Adds the bank's transfers the statements left out; how many."""
    import requests

    from import_sales_report import SUPABASE_URL, _auth_headers

    transfers = bank_transfers(root)
    if not transfers:
        return 0
    head = {**_auth_headers(), "Content-Type": "application/json"}
    st = requests.get(f"{SUPABASE_URL}/rest/v1/term_loan_statements", headers=head, timeout=30,
                      params={"select": "id,statement_date,period_from,period_to"})
    st.raise_for_status()
    ln = requests.get(f"{SUPABASE_URL}/rest/v1/term_loan_lines", headers=head, timeout=30, params={"select": "line_date,amount"})
    ln.raise_for_status()
    todo = missing_transfers(transfers, st.json(), ln.json())
    for t in todo:
        print(f"  From the bank statement: {t['line_date']}  {t['amount']:>14,.2f}  {t['description']}")
    if todo and not dry_run:
        requests.post(f"{SUPABASE_URL}/rest/v1/term_loan_lines", headers=head, json=todo, timeout=30).raise_for_status()
    return len(todo)


def pdf_text(path):
    import pdfplumber

    with pdfplumber.open(path) as pdf:
        return "\n".join(page.extract_text() or "" for page in pdf.pages)


def statement_files(path):
    p = pathlib.Path(path)
    if p.is_file():
        return [p]
    return sorted(f for f in p.rglob("*.pdf") if any(part.lower() == "term loan" for part in f.parent.parts))


def save(statement, file_name):
    """Adds the statement and its lines; 'there' if the hub has it already."""
    import requests

    from import_sales_report import SUPABASE_URL, _auth_headers

    head = {**_auth_headers(), "Content-Type": "application/json"}
    url = f"{SUPABASE_URL}/rest/v1/term_loan_statements"
    found = requests.get(url, headers=head, timeout=30, params={
        "account_no": f"eq.{statement['account_no']}", "statement_date": f"eq.{statement['statement_date']}", "select": "id,interest_portion"})
    found.raise_for_status()
    if found.json():
        # Read before these figures were kept: added now (its lines stay as they are).
        if found.json()[0].get("interest_portion") is None and statement.get("interest_portion") is not None:
            requests.patch(url, headers=head, timeout=30, params={"id": f"eq.{found.json()[0]['id']}"},
                           json={"interest_portion": statement["interest_portion"], "interest_benefit": statement["interest_benefit"]}).raise_for_status()
        return "there"
    row = {k: v for k, v in statement.items() if k != "lines"}
    resp = requests.post(url, headers={**head, "Prefer": "return=representation"}, json={**row, "file_name": file_name}, timeout=30)
    resp.raise_for_status()
    sid = resp.json()[0]["id"]
    if statement["lines"]:
        resp = requests.post(f"{SUPABASE_URL}/rest/v1/term_loan_lines", headers=head, timeout=30,
                             json=[{**line, "statement_id": sid} for line in statement["lines"]])
        if resp.status_code >= 400:
            requests.delete(url, headers=head, params={"id": f"eq.{sid}"}, timeout=30)
            resp.raise_for_status()
    return "added"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path", help="the client folder (its <year>\\Bank\\Term Loan folders), a folder of statements, or one PDF")
    ap.add_argument("--dry-run", action="store_true", help="only show what was read; change nothing")
    args = ap.parse_args(argv)
    files = statement_files(args.path)
    if not files:
        print(f"No term loan statements (PDFs in a 'Term Loan' folder) under {args.path}")
        return 0
    added = there = failed = 0
    for f in files:
        try:
            s = parse_statement(pdf_text(f))
        except NotAStatement as e:
            print(f"{f.name}: skipped ({e})")
            continue
        except Exception as e:  # a damaged PDF: listed, the rest go on
            print(f"{f.name}: could not read ({e})")
            failed += 1
            continue
        balance = round(s["advance"] - s["capital"], 2)
        print(f"{f.name}: {s['statement_date']}, capital {s['capital']:,.2f}, prepaid {s['advance']:,.2f}, "
              f"balance {balance:,.2f}, interest {s['interest_portion'] or 0:,.2f} less benefit {s['interest_benefit'] or 0:,.2f}, {len(s['lines'])} line(s)")
        for line in s["lines"]:
            print(f"    {line['line_date']}  {line['description']:<20} {line['amount']:>14,.2f}")
        if args.dry_run:
            continue
        try:
            if save(s, f.name) == "added":
                added += 1
            else:
                there += 1
        except Exception as e:
            print(f"  NOT saved: {e} (run nanini_app/docs/sql/term_loan.sql once?)")
            failed += 1
    # Payments into the loan and drawings the statements left out, from the ABSA current account's CSVs.
    if pathlib.Path(args.path).is_dir():
        try:
            n = add_missing_transfers(args.path, dry_run=args.dry_run)
            if n:
                print(f"{n} transfer(s) from the bank statements {'to add' if args.dry_run else 'added'}.")
        except Exception as e:
            print(f"Bank statements not checked for transfers: {e}")
    if not args.dry_run:
        print(f"\nTerm loan: {added} statement(s) added, {there} already in the hub, {failed} failed.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
