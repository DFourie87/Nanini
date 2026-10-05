#!/usr/bin/env python3
"""
Reads the market agents' afrekeningstate (payment statements): which account
sales an agent paid, when, and how much -- for the customers' accounts.

    python scripts\\market_statements.py "path\\to\\statement.pdf"   # show what is read

Currently read:
  - RSA Markagente (Technofresh download, 12683_ACCCHEQS_...pdf): "PAYMENT
    SUMMARY FOR PAYMENT DATED dd/mm/yyyy", a row per account sale paid:
    ACC/SL, DELIV.NO, SUPPL REFNO, SALES, DEDUCTS, VALUE, QTYPAID, CHEQ/TFER.
"""
import re
import sys

from import_sales_report import ParseError, extract_pages

RSA_PAYMENT_DATE_RE = re.compile(r"PAYMENT SUMMARY FOR PAYMENT DATED\s*:\s*(\d{2})/(\d{2})/(\d{4})")
# 269579 186573 91212 175000.00 25717.83 149282.17 1273 Transfer
RSA_PAYMENT_ROW_RE = re.compile(
    r"^\s*(\d+)\s+(\d+)\s+(\d+)\s+(-?[\d.]+\.\d{2})\s+(-?[\d.]+\.\d{2})\s+(-?[\d.]+\.\d{2})\s+(\d+)\s+(\S+)\s*$",
    re.MULTILINE,
)
# The totals row: sales, deductions, value, quantity.
RSA_PAYMENT_TOTAL_RE = re.compile(r"^\s*(-?[\d.]+\.\d{2})\s+(-?[\d.]+\.\d{2})\s+(-?[\d.]+\.\d{2})\s+(\d+)\s*$", re.MULTILINE)


def parse_rsa_payment(text):
    """RSA's afrekeningstaat: {'agent', 'date', 'paid', 'method', 'sales': [...]},
    each sale {'account_sale', 'delivery', 'sales', 'deductions', 'nett', 'qty'}.
    Raises ParseError when the rows don't add up to the printed total."""
    date_m = RSA_PAYMENT_DATE_RE.search(text)
    if not date_m:
        raise ParseError("No payment date found in this RSA afrekeningstaat.")
    sales = []
    methods = set()
    for m in RSA_PAYMENT_ROW_RE.finditer(text):
        acc, deliv, _ref, gross, deducts, nett, qty, method = m.groups()
        sales.append({
            "account_sale": acc,
            "delivery": deliv,
            "sales": float(gross),
            "deductions": float(deducts),
            "nett": float(nett),
            "qty": int(qty),
        })
        methods.add(method.lower())
    if not sales:
        raise ParseError("No account sales found in this RSA afrekeningstaat.")
    paid = round(sum(s["nett"] for s in sales), 2)
    totals = RSA_PAYMENT_TOTAL_RE.findall(text)
    if totals and abs(float(totals[-1][2]) - paid) > 0.01:
        raise ParseError(f"The account sales add up to R{paid:,.2f} but the statement's total is R{float(totals[-1][2]):,.2f}.")
    return {
        "agent": "RSA Markagente Pretoria",
        "date": f"{date_m.group(3)}-{date_m.group(2)}-{date_m.group(1)}",
        "paid": paid,
        "method": "/".join(sorted(methods)),
        "sales": sales,
    }


def parse_statement(pages):
    """The afrekeningstaat on these pages, or ParseError if it isn't one this reads."""
    text = "\n".join(pages)
    if "AFREKENINGSTAAT" in text and RSA_PAYMENT_DATE_RE.search(text):
        return parse_rsa_payment(text)
    raise ParseError("Not an afrekeningstaat this reads (yet).")


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 1
    st = parse_statement(extract_pages(sys.argv[1]))
    print(f"{st['agent']}: paid {st['date']} R{st['paid']:,.2f} ({st['method']})")
    for s in st["sales"]:
        print(f"  account sale {s['account_sale']}: sales R{s['sales']:,.2f} - deductions R{s['deductions']:,.2f} "
              f"= R{s['nett']:,.2f} ({s['qty']} paid)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
