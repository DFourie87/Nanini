#!/usr/bin/env python3
"""
Reads the market agents' afrekeningstate (payment statements): which account
sales an agent paid, when, and how much -- for the customers' accounts.

    python scripts\\market_statements.py "path\\to\\statement.pdf"   # show what is read

Currently read:
  - RSA Markagente (Technofresh download, 12683_ACCCHEQS_...pdf): "PAYMENT
    SUMMARY FOR PAYMENT DATED dd/mm/yyyy", a row per account sale paid:
    ACC/SL, DELIV.NO, SUPPL REFNO, SALES, DEDUCTS, VALUE, QTYPAID, CHEQ/TFER.
  - Wenpro, Dapper, CL de Villiers, Botha Roodt (one system; ..._Sum.pdf by
    email): "Opsomming van betalings gemaak op yyyy/mm/dd", a row per account
    sale paid: Verkope nr, Mark verw, Afleweringsnota, Datum ontvang,
    Vernietig, Betaal nou, Bruto, Aftrekkings, Lenings, Netto bedrag.
  - Universal Leaf (tobacco): its tax invoice is its settlement statement
    too ("Settlement Statement / Bank Transfer ... Total Net Payment"), so
    each invoice is a payment of itself, on its date of sale.
"""
import re
import sys

from import_sales_report import NUM_DEC, NUM_INT, WENFAM_AGENT_MARKERS, ParseError, parse_tobacco_ulsa, _sa_number, extract_pages

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


WENFAM_PAYMENT_DATE_RE = re.compile(r"(?:Opsomming van betalings gemaak op|Summary of payments made on)\s+(\d{4})/(\d{2})/(\d{2})")
# 56797326 6408845 28586 2026/09/02 0 62 2 480.00 406.48 0.00 2 073.52
WENFAM_PAYMENT_ROW_RE = re.compile(
    r"^(\d+)\s+(\d+)\s+(\d+)\s+(\d{4})/(\d{2})/(\d{2})\s+(" + NUM_INT + r")\s+(" + NUM_INT + r")\s+("
    + NUM_DEC + r")\s+(" + NUM_DEC + r")\s+(" + NUM_DEC + r")\s+(-?" + NUM_DEC + r")\s*$",
    re.MULTILINE,
)
WENFAM_PAYMENT_TOTAL_RE = re.compile(
    r"^(?:Totaal|Total):\s+(" + NUM_INT + r")\s+(" + NUM_INT + r")\s+(" + NUM_DEC + r")\s+(" + NUM_DEC + r")\s+("
    + NUM_DEC + r")\s+(-?" + NUM_DEC + r")\s*$",
    re.MULTILINE,
)


def _signed(s):
    return -_sa_number(s[1:]) if s.startswith("-") else _sa_number(s)


def parse_wenfam_payment(text, agent):
    """The Joburg agents' payment summary, in the same shape as RSA's; each
    sale also has its delivery date ('received') and loans taken off."""
    date_m = WENFAM_PAYMENT_DATE_RE.search(text)
    if not date_m:
        raise ParseError("No payment date found in this payment summary.")
    sales = []
    for m in WENFAM_PAYMENT_ROW_RE.finditer(text):
        acc, _market_ref, deliv, y, mo, d, _destroyed, qty, gross, deducts, loans, nett = m.groups()
        sales.append({
            "account_sale": acc,
            "delivery": deliv,
            "received": f"{y}-{mo}-{d}",
            "sales": _sa_number(gross),
            "deductions": _sa_number(deducts),
            "loans": _sa_number(loans),
            "nett": _signed(nett),
            "qty": int(_sa_number(qty)),
        })
    if not sales:
        raise ParseError("No account sales found in this payment summary.")
    paid = round(sum(s["nett"] for s in sales), 2)
    total_m = WENFAM_PAYMENT_TOTAL_RE.search(text)
    if total_m and abs(_signed(total_m.group(6)) - paid) > 0.01:
        raise ParseError(f"The account sales add up to R{paid:,.2f} but the summary's total is R{_signed(total_m.group(6)):,.2f}.")
    return {
        "agent": agent,
        "date": f"{date_m.group(1)}-{date_m.group(2)}-{date_m.group(3)}",
        "paid": paid,
        "method": "",
        "sales": sales,
    }


def parse_ulsa_settlement(text):
    """A ULSA tobacco invoice as the payment of itself."""
    r = parse_tobacco_ulsa(text)[0]
    return {
        "agent": r["agent"],
        "date": r["report_date"],
        "paid": r["nett_amount"],
        "method": "transfer",
        "sales": [{
            "account_sale": r["report_number"],
            "sales": round(r["gross_total"] + (r["vat_on_sales"] or 0), 2),
            "deductions": round(r["commission_before_vat"] + r["vat"], 2),
            "nett": r["nett_amount"],
            "qty": round(sum(li["qty"] for li in r["line_items"]), 2),
        }],
    }


def parse_statement(pages):
    """The afrekeningstaat on these pages, or ParseError if it isn't one this reads."""
    text = "\n".join(pages)
    if "AFREKENINGSTAAT" in text and RSA_PAYMENT_DATE_RE.search(text):
        return parse_rsa_payment(text)
    agent = next((name for marker, name in WENFAM_AGENT_MARKERS if marker in text), None)
    if agent and WENFAM_PAYMENT_DATE_RE.search(text):
        return parse_wenfam_payment(text, agent)
    if "Settlement Statement" in text and "Universal Leaf South Africa" in text and "Total Net Payment" in text:
        return parse_ulsa_settlement(text)
    raise ParseError("Not an afrekeningstaat this reads (yet).")


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 1
    st = parse_statement(extract_pages(sys.argv[1]))
    method = f" ({st['method']})" if st["method"] else ""
    print(f"{st['agent']}: paid {st['date']} R{st['paid']:,.2f}{method}")
    for s in st["sales"]:
        loans = f"- loans R{s['loans']:,.2f} " if s.get("loans") else ""
        print(f"  account sale {s['account_sale']}: sales R{s['sales']:,.2f} - deductions R{s['deductions']:,.2f} "
              f"{loans}= R{s['nett']:,.2f} ({s['qty']} paid)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
