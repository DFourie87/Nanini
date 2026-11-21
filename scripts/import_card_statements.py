#!/usr/bin/env python3
"""
Reads ABSA's credit card and fleet card statements (PDF) into the hub:
Financials > Credit card / Fleet card shows the working paper and saves the
lines as a CSV for the card's bank account in Xero.

    py scripts\\import_card_statements.py "D:\\Kliente\\Nanini 121 BK"
    py scripts\\import_card_statements.py "D:\\Kliente\\Nanini 121 BK\\2027\\Bank\\Fleet Card" --dry-run

How it works:
  * Every PDF in a "Credit card" or "Fleet Card" folder under the folder
    given (any year's Bank\\...), or the one file given, is read. Other
    PDFs there (the fleet card's tax invoice and toll report) are skipped.
  * From each statement: its date (and period), the balance brought forward
    and the closing balance, and every line: payments, purchases, interest,
    fees and VAT. Amounts as in Xero's bank account: plus is money into the
    card (a payment, credit interest), minus is spent or charged; a balance
    in credit is plus, one owed to ABSA minus.
  * A statement already in the hub is left alone (its lines may have been
    adjusted or sent to Xero there). Run it again any time: only new
    statements are added.

Needs docs/sql/card_statements.sql run once, and the Supabase secret key
(scripts/supabase_secret_key.txt) like the sales import.
"""
import argparse
import datetime as dt
import pathlib
import re
import sys

MONTHS = {m: i for i, m in enumerate(["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"], 1)}
CC_MONEY = r"\d{1,3}(?: \d{3})*,\d{2}"
CC_LINE_RE = re.compile(rf"^(\d{{1,2}}) (\w{{3}}) \d{{1,2}} \w{{3}} (\d{{6,}}) (.+?) ({CC_MONEY})(Cr)?$")
FLEET_MONEY = r"\d{1,3}(?:,?\d{3})*\.\d{2}"
FLEET_LINE_RE = re.compile(rf"^(\d{{4}})/(\d{{2}})/(\d{{2}}) (.+?) ({FLEET_MONEY})(-)?$")
FOLDERS = {"credit card": "credit", "fleet card": "fleet"}


class NotAStatement(Exception):
    pass


def day(text):
    """'9 Nov 2026' -> date."""
    d, m, y = text.split()
    return dt.date(int(y), MONTHS[m[:3].lower()], int(d))


def cc_money(amount, cr):
    """'17 510,64' and 'Cr' -> 17510.64 (in credit: plus); no Cr -> minus."""
    v = round(float(amount.replace(" ", "").replace(",", ".")), 2)
    return v if cr or v == 0 else -v


def parse_credit_card(text):
    period = re.search(r"Credit card statement for the period\s*(\d{1,2} \w{3} \d{4}) to (\d{1,2} \w{3} \d{4})", text)
    stated = re.search(r"Statement date:\s*(\d{1,2} \w{3} \d{4})", text)
    account = re.search(r"Account number:\s*([\d-]{12,})", text)
    calc = text.find("Calculation of balance")
    if not (period and stated and account and calc >= 0):
        raise NotAStatement("not an ABSA credit card statement")
    start, end = day(period.group(1)), day(period.group(2))
    opening = closing = None
    extras = []
    for raw in text[calc:].splitlines()[1:]:
        m = re.match(rf"^(.+?) ({CC_MONEY})(Cr)?$", raw.strip())
        if not m:
            continue
        what, value = m.group(1).strip(), cc_money(m.group(2), m.group(3))
        if what == "Balance from last statement":
            opening = value
        elif what == "Balance on this statement":
            closing = value
            break
        elif what not in ("Transactions", "Payments/Credits"):
            extras.append({"line_date": end.isoformat(), "description": what, "reference": None, "amount": value})
    if opening is None or closing is None:
        raise NotAStatement("no balances in its Calculation of balance")
    lines = []
    for raw in text.splitlines():
        m = CC_LINE_RE.match(raw.strip())
        if not m:
            continue
        d, mon, ref, what, amount, cr = m.groups()
        month = MONTHS[mon.lower()]
        year = end.year if month <= end.month else end.year - 1
        lines.append({"line_date": dt.date(year, month, int(d)).isoformat(), "description": what.strip(), "reference": ref, "amount": cc_money(amount, cr)})
    digits = re.sub(r"\D", "", account.group(1))
    return {
        "card": "credit",
        "account_no": digits[-4:],
        "statement_date": day(stated.group(1)).isoformat(),
        "period_from": start.isoformat(),
        "period_to": end.isoformat(),
        "statement_no": None,
        "opening": opening,
        "closing": closing,
        "lines": sorted(lines, key=lambda x: x["line_date"]) + extras,
    }


def fleet_money(amount, minus):
    """'1988.56' with '-' (a payment: into the card) -> plus; a charge -> minus."""
    v = round(float(amount.replace(",", "")), 2)
    return v if minus or v == 0 else -v


def parse_fleet_card(text):
    if "CONTRACTUAL CLIENT INVOICE" not in text or "Fleet Card" not in text:
        raise NotAStatement("not an ABSA fleet card statement (its tax invoice or toll report?)")
    account = re.search(r"FMS A/C NO\s*:\s*([\d ]{8,})", text)
    stated = re.search(r"DATE:\s*(\d{4})/(\d{2})/(\d{2})", text)
    number = re.search(r"STATEMENT NO\s*:\s*(\d+)", text)
    opening = re.search(rf"BALANCE BROUGHT FORWARD\s+({FLEET_MONEY})(-)?", text)
    closing = re.search(rf"TOTAL OWING TO ABSA\s+({FLEET_MONEY})(-)?", text)
    if not (account and stated and opening and closing):
        raise NotAStatement("no account, date or balances")
    lines = []
    for raw in text.splitlines():
        m = FLEET_LINE_RE.match(raw.strip())
        if m:
            y, mo, d, what, amount, minus = m.groups()
            lines.append({"line_date": dt.date(int(y), int(mo), int(d)).isoformat(), "description": what.strip(), "reference": None,
                          "amount": fleet_money(amount, minus)})
    date = dt.date(*(int(x) for x in stated.groups()))
    return {
        "card": "fleet",
        "account_no": re.sub(r"\D", "", account.group(1))[-4:],
        "statement_date": date.isoformat(),
        "period_from": None,
        "period_to": date.isoformat(),
        "statement_no": int(number.group(1)) if number else None,
        "opening": fleet_money(opening.group(1), opening.group(2)),
        "closing": fleet_money(closing.group(1), closing.group(2)),
        "lines": lines,
    }


def parse_statement(text, card):
    return parse_credit_card(text) if card == "credit" else parse_fleet_card(text)


def pdf_text(path):
    import pdfplumber

    with pdfplumber.open(path) as pdf:
        return "\n".join(page.extract_text() or "" for page in pdf.pages)


def card_of(path):
    """'credit' or 'fleet' by the folder a PDF is in; None for others."""
    for part in reversed(pathlib.Path(path).parent.parts):
        if part.lower() in FOLDERS:
            return FOLDERS[part.lower()]
    return None


def statement_files(path):
    p = pathlib.Path(path)
    if p.is_file():
        return [p]
    return sorted((f for f in p.rglob("*.pdf") if card_of(f)), key=lambda f: (card_of(f), str(f)))


def save(statement, file_name):
    """Adds the statement and its lines; 'there' if the hub has it already."""
    import requests

    from import_sales_report import SUPABASE_URL, _auth_headers

    head = {**_auth_headers(), "Content-Type": "application/json"}
    url = f"{SUPABASE_URL}/rest/v1/card_statements"
    found = requests.get(url, headers=head, timeout=30, params={
        "card": f"eq.{statement['card']}", "statement_date": f"eq.{statement['statement_date']}", "select": "id"})
    found.raise_for_status()
    if found.json():
        return "there"
    row = {k: v for k, v in statement.items() if k != "lines"}
    resp = requests.post(url, headers={**head, "Prefer": "return=representation"}, json={**row, "file_name": file_name}, timeout=30)
    resp.raise_for_status()
    sid = resp.json()[0]["id"]
    if statement["lines"]:
        resp = requests.post(f"{SUPABASE_URL}/rest/v1/card_lines", headers=head, timeout=30,
                             json=[{**line, "statement_id": sid} for line in statement["lines"]])
        if resp.status_code >= 400:
            requests.delete(url, headers=head, params={"id": f"eq.{sid}"}, timeout=30)
            resp.raise_for_status()
    return "added"


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("path", help="the client folder (its <year>\\Bank\\Credit card and Fleet Card folders), one of those folders, or one PDF")
    ap.add_argument("--card", choices=["credit", "fleet"], help="for one PDF outside those folders: which card")
    ap.add_argument("--dry-run", action="store_true", help="only show what was read; change nothing")
    args = ap.parse_args(argv)
    files = statement_files(args.path)
    if not files:
        print(f"No card statements (PDFs in a 'Credit card' or 'Fleet Card' folder) under {args.path}")
        return 0
    added = there = failed = 0
    for f in files:
        card = args.card or card_of(f)
        if card is None:
            print(f"{f.name}: skipped (not in a Credit card or Fleet Card folder; give --card)")
            continue
        if card == "fleet" and re.search(r"tax.?invoice|toll", f.name, re.I):
            continue  # the fleet card's tax invoice and toll report go with its statement
        try:
            text = pdf_text(f)
            if not text.strip():
                print(f"{f.name}: NOT read -- no text in it (a 'Print to PDF' or scanned copy). Save the PDF as downloaded from ABSA instead.")
                failed += 1
                continue
            s = parse_statement(text, card)
        except NotAStatement as e:
            print(f"{f.name}: skipped ({e})")
            continue
        except Exception as e:  # a damaged PDF: listed, the rest go on
            print(f"{f.name}: could not read ({e})")
            failed += 1
            continue
        total = round(s["opening"] + sum(x["amount"] for x in s["lines"]), 2)
        check = "" if abs(total - s["closing"]) < 0.005 else f"  -- the lines come to {total:,.2f}, not the closing balance!"
        print(f"{f.name}: {card} card {s['statement_date']}, opening {s['opening']:,.2f}, closing {s['closing']:,.2f}, {len(s['lines'])} line(s){check}")
        for line in s["lines"]:
            print(f"    {line['line_date']}  {line['description'][:40]:<40} {line['amount']:>14,.2f}")
        if args.dry_run:
            continue
        try:
            if save(s, f.name) == "added":
                added += 1
            else:
                there += 1
        except Exception as e:
            print(f"  NOT saved: {e} (run nanini_app/docs/sql/card_statements.sql once?)")
            failed += 1
    if not args.dry_run:
        print(f"\nCards: {added} statement(s) added, {there} already in the hub, {failed} failed.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
