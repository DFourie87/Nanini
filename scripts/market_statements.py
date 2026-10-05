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
  - Peppadew (the buyer): its farmer payment advice -- a row per load
    (GRV number) with its value, less deductions = the nett payment. It has no
    date: the email's (the start of the saved file's name), else the last load's.
  - Universal Leaf (tobacco): its tax invoice is its settlement statement
    too ("Settlement Statement / Bank Transfer ... Total Net Payment"), so
    each invoice is a payment of itself, on its date of sale.
"""
import re
import sys

from import_sales_report import WENFAM_AGENT_MARKERS, ParseError, extract_pages, parse_tobacco_ulsa

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
# The market ref and delivery note can be anything ("10/11/22"); after the
# date: destroyed, paid now, gross, deductions, loans, nett.
WENFAM_PAYMENT_ROW_RE = re.compile(r"^(\d+)\s+(.*?)\s*(\d{4})/(\d{2})/(\d{2})\s+([-\d .]+\.\d{2})\s*$", re.MULTILINE)
WENFAM_PAYMENT_TOTAL_RE = re.compile(r"^(?:Totaal|Total):\s+([-\d .]+\.\d{2})\s*$", re.MULTILINE)


def _numbers(tokens, kinds):
    """Every way to read [tokens] as numbers of [kinds] ('i' whole, 'd' with
    cents) where thousands are written with a space ("3 300", "187 712.00"):
    a number is a first token and then tokens of three digits."""
    if not kinds:
        return [[]] if not tokens else []
    out = []
    for n in range(1, len(tokens) + 1):
        part, rest = tokens[:n], tokens[n:]
        first, groups = part[0], part[1:]
        if not re.fullmatch(r"-?\d+(?:\.\d{2})?", first) and not (groups == [] and re.fullmatch(r"-?\d+\.\d{2}", first)):
            break
        if any(not re.fullmatch(r"\d{3}(?:\.\d{2})?", g) for g in groups):
            break
        joined = "".join(part)
        decimal = "." in joined
        if "." in "".join(part[:-1]):
            break
        if decimal == (kinds[0] == "d"):
            for more in _numbers(rest, kinds[1:]):
                out.append([float(joined)] + more)
        if decimal:
            break
    return out


def _split_amounts(tail):
    """(destroyed, paid now, gross, deductions, loans, nett) from the numbers
    after the date -- the reading where gross - deductions - loans = nett."""
    fits = [n for n in _numbers(tail.split(), "iidddd") if abs(n[2] - n[3] - n[4] - n[5]) < 0.01]
    # Older summaries leave loans empty when there are none.
    fits += [n[:4] + [0.0] + n[4:] for n in _numbers(tail.split(), "iiddd") if abs(n[2] - n[3] - n[4]) < 0.01]
    return fits[0] if fits else None


def _split_total(tail):
    """The total's nett: as the row adds up, else its last amount as printed."""
    amounts = _split_amounts(tail)
    if amounts:
        return amounts[5]
    m = re.search(r"(-?\d{1,3}(?: \d{3})*\.\d{2})$", tail.strip())
    return float(m.group(1).replace(" ", "")) if m else None


def parse_wenfam_payment(text, agent):
    """The Joburg agents' payment summary, in the same shape as RSA's; each
    sale also has its delivery date ('received') and loans taken off."""
    date_m = WENFAM_PAYMENT_DATE_RE.search(text)
    if not date_m:
        raise ParseError("No payment date found in this payment summary.")
    sales = []
    for m in WENFAM_PAYMENT_ROW_RE.finditer(text):
        acc, refs, y, mo, d, tail = m.groups()
        amounts = _split_amounts(tail)
        if amounts is None:
            raise ParseError(f"Could not read the amounts of account sale {acc} (gross - deductions - loans isn't the nett).")
        _destroyed, qty, gross, deducts, loans, nett = amounts
        refs = refs.split()
        sales.append({
            "account_sale": acc,
            "delivery": refs[-1] if refs else None,
            "received": f"{y}-{mo}-{d}",
            "sales": gross,
            "deductions": deducts,
            "loans": loans,
            "nett": nett,
            "qty": int(qty),
        })
    if not sales:
        raise ParseError("No account sales found in this payment summary.")
    paid = round(sum(s["nett"] for s in sales), 2)
    total_m = WENFAM_PAYMENT_TOTAL_RE.search(text)
    printed = _split_total(total_m.group(1)) if total_m else None
    if printed is not None and abs(printed - paid) > 0.01:
        raise ParseError(f"The account sales add up to R{paid:,.2f} but the summary's total is R{printed:,.2f}.")
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


# GRV-7135 55844 2026/04/17 07:50 12 2412.51 876.64 274 73% 27% 39% 31% 0% 3% R 3 5,318.44
# (Earlier advices: the date as 17-02-2026 or 29/01/2026, and no rejected weight.)
PEPPADEW_ROW_RE = re.compile(
    r"^(GRV-\d+)\s+(\S+)\s+(\d{4}/\d{2}/\d{2}|\d{2}[-/]\d{2}[-/]\d{4})\s+\d{1,2}:\d{2}\s+\d+\s+([\d.]+)\s+([\d.]+)\s+.*?R\s*([\d ,.]+|-)\s*$",
    re.MULTILINE,
)


def _peppadew_date(s):
    """2026/04/17, 17-04-2026 or 17/04/2026 -> 2026-04-17."""
    parts = re.split(r"[-/]", s)
    return "-".join(parts if len(parts[0]) == 4 else reversed(parts))


def _rands(s):
    """'3 5,318.44' (as printed, spaces anywhere) -> 35318.44; '-' -> 0."""
    s = s.strip()
    return 0.0 if s in ("", "-") else float(re.sub(r"[ ,]", "", s))


def parse_peppadew_advice(text, name=None):
    """Peppadew's payment advice, in the same shape as the agents' summaries:
    each load (GRV) with a value paid; the payment is the nett after deductions."""
    sales = []
    for m in PEPPADEW_ROW_RE.finditer(text):
        grv, note, day, accepted, rejected, value = m.groups()
        v = _rands(value)
        if not v:
            continue  # weighed but not valued yet: paid on a later advice
        sales.append({
            "account_sale": grv,
            "delivery": note,
            "received": _peppadew_date(day),
            "sales": v,
            "deductions": 0.0,
            "nett": v,
            "qty": float(accepted),
        })
    if not sales:
        raise ParseError("No loads found in this Peppadew payment advice.")
    total_m = re.search(r"^TOTAL\s+\d+\s+[\d.]+.*?R\s*([\d ,.]+)\s*$", text, re.MULTILINE)
    rows = round(sum(s["nett"] for s in sales), 2)
    if total_m and abs(_rands(total_m.group(1)) - rows) > 0.01:
        raise ParseError(f"The loads add up to R{rows:,.2f} but the advice's total is R{_rands(total_m.group(1)):,.2f}.")
    nett_m = re.search(r"NETT PAYMENT\s*R\s*([\d ,.]+|-)", text)
    deductions_m = re.search(r"TOTAL DEDUCTIONS\s*R\s*([\d ,.]+|-)", text)
    paid = _rands(nett_m.group(1)) if nett_m else rows
    if deductions_m and abs(rows - _rands(deductions_m.group(1)) - paid) > 0.01:
        raise ParseError(f"The loads (R{rows:,.2f}) less deductions aren't the nett payment (R{paid:,.2f}).")
    day = re.match(r"(\d{4}-\d{2}-\d{2}) ", name or "")
    return {
        "agent": "Peppadew",
        "date": day.group(1) if day else max(s["received"] for s in sales),
        "paid": round(paid, 2),
        "method": "transfer",
        "sales": sales,
    }


def parse_statement(pages, name=None):
    """The afrekeningstaat on these pages, or ParseError if it isn't one this
    reads. [name]: the PDF's file name (a Peppadew advice's date is in it)."""
    text = "\n".join(pages)
    if "FARMER PAYMENT ADVICE" in text and "PEPPADEW" in text.upper():
        return parse_peppadew_advice(text, name)
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
