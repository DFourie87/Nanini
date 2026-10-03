"""Tests for fetch_supplier_docs.py (no Gmail or app needed):

    python -m unittest scripts/test_fetch_supplier_docs.py
"""
import datetime as dt
import email.message
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import fetch_supplier_docs as f  # noqa: E402

SUPPLIERS = [
    {"id": "s1", "name": "Agri Supplies", "addresses": f.supplier_addresses("accounts@agri.co.za; Statements@Agri.co.za")},
    {"id": "s2", "name": "Fuel Depot", "addresses": f.supplier_addresses("@fueldepot.com")},
]

INVOICE = """AGRI SUPPLIES (PTY) LTD
TAX INVOICE
Invoice No: INV-20488
Invoice Date: 14/09/2026
Due date: 14/10/2026
Fertiliser 2:3:2 (30) 50kg  10  R 485.00  R 4 850.00
Subtotal R 4 850.00
VAT 15% R 727.50
Total Due R 5 577.50
"""

STATEMENT = """FUEL DEPOT
STATEMENT OF ACCOUNT
Statement date: 30 September 2026
Opening balance 12 000.00
Payment received -12 000.00
Invoice 5531 8 450,75
Closing Balance R 8 450,75
"""


class Guessing(unittest.TestCase):
    def test_addresses_and_matching(self):
        self.assertEqual(SUPPLIERS[0]["addresses"], ["accounts@agri.co.za", "statements@agri.co.za"])
        self.assertEqual(f.match_supplier("Statements@agri.co.za", SUPPLIERS)["id"], "s1")
        self.assertEqual(f.match_supplier("anyone@fueldepot.com", SUPPLIERS)["id"], "s2")
        self.assertIsNone(f.match_supplier("friend@gmail.com", SUPPLIERS))
        self.assertIsNone(f.match_supplier("sales@agri.co.za", SUPPLIERS))  # only the listed addresses
        self.assertIn("from:(accounts@agri.co.za OR fueldepot.com OR statements@agri.co.za)", f.gmail_query(SUPPLIERS, 60))

    def test_invoice(self):
        g = f.guess_all(INVOICE, "Your invoice", "inv.pdf", dt.date(2026, 9, 15))
        self.assertEqual(g, {"kind": "invoice", "doc_date": "2026-09-14", "amount": 5577.50, "reference": "INV-20488", "due_date": "2026-10-14"})

    def test_statement(self):
        g = f.guess_all(STATEMENT, "Statement", "stmt.pdf", dt.date(2026, 10, 1))
        self.assertEqual(g, {"kind": "statement", "doc_date": "2026-09-30", "amount": 8450.75, "reference": None, "due_date": None})

    def test_credit_note_and_money(self):
        self.assertEqual(f.guess_kind("CREDIT NOTE\nCredit note number CN-12"), "credit_note")
        # The file name first: Omnia's "_ci_" is an invoice even if it mentions statements.
        self.assertEqual(f.guess_kind("see your statement", "", "omnia_ci_flvd_email_32777530_OF27LVD005745SIN_53.pdf"), "invoice")
        self.assertEqual(f.guess_kind("", "", "omnia_st_flvd_email_email_32777530_32777530_302.pdf"), "statement")
        self.assertEqual(f.guess_kind("", "", "D1216 DI Staat 31Aug26.PDF"), "statement")
        self.assertEqual(f.guess_kind("", "", "Tax Invoice  INV3408.PDF"), "invoice")
        self.assertTrue(f.IGNORE_NAMES.search("Supplementary Information_20250926.pdf"))
        self.assertFalse(f.IGNORE_NAMES.search("8441635490_844744008199.pdf"))
        self.assertEqual(f.parse_money("R 1 234,56"), 1234.56)
        self.assertEqual(f.parse_money("12,345.67"), 12345.67)
        self.assertEqual(f.parse_money("-300.00"), -300.0)
        # Omnia's statement (as read from the real PDF): the Total of the age analysis.
        omnia = ("Invoice account Business unit Statement date 30/09/2026\n"
                 "08/09/2026 30D 31/10/2026 OF1549290SO OFER817198SDN INV OF27LVD008562SIN 33 636,00 33 636,00 33 636,00\n"
                 "33 636,00 0,00 33 636,00 0,00\nNot due 0,00\nCustomer age analysis\nUnallocated payments 0,00\n"
                 "Payable before Payable now\nDue 33 636,00\nmonth end\n"
                 "Total Not due Current 30 days 60 days 90 days 120 days 150 days 150+ days Settlement discount 0,00\n"
                 "41 200,00 7 564,00 33 636,00 0,00 0,00 0,00 0,00 0,00 0,00 Due by due date 33 636,00\n"
                 "30/09/2026 Settlement PAY OF00129308BSMAV (98 175,95) (3 818,45)\n")
        g = f.guess_all(omnia, "", "omnia_st_flvd_email_email_32777530_32777530_352.pdf", dt.date(2026, 10, 1))
        self.assertEqual((g["kind"], g["doc_date"], g["amount"], g["due_date"]), ("statement", "2026-09-30", 41200.00, None))
        self.assertEqual(f.guess_amount("Current 30 Days 60 Days 90 Days Total\n100.00 50.00 0.00 0.00 150.00", "statement"), 150.00)
        # VKB (Afrikaans): the date below STAATDATUM, the total owing, what's already due.
        vkb = (" PLAAS HAASKRAAL WYK : 32 STAATDATUM VERWYSING L0471927\n"
               " POSBUS 182 VERSPREIDINGSINLIGTING 20260831\n"
               " BLADSY : 1 01/8/2026 TOT 31/8/2026 E-POS JOHAN.VNIEKERK@VKB.CO.ZA\n"
               " ONTLEDING VAN BEDRYFSREKENING DATUM BETAALBAAR\n"
               " MAANDREKENING HUIDIG 12 936.91 30/09/2026\n"
               " 30 DAE 6 454.81 REEDS BETAALBAAR\n"
               " 60-90 DAE 10 481.73 REEDS BETAALBAAR\n"
               " 120 DAE + 0.00 REEDS BETAALBAAR\n"
               " TOTAAL 29 873.45\n"
               " TOTALE BALANS VERSKULDIG OP BEDRYFSREKENINGS 29 873.45\n"
               " TOTALE KREDIET LIMIET 80 000.00\n"
               " SEKURITEIT AANDEELHOUERSLENINGS 3 790.37-\n")
        g = f.guess_all(vkb, "", "L0471927-20260903.pdf", dt.date(2026, 9, 3))
        self.assertEqual(g, {"kind": "statement", "doc_date": "2026-08-31", "amount": 29873.45, "reference": None,
                             "due_date": "2026-09-30", "overdue_amount": 16936.54})
        # Nothing readable: no amount, the email's date.
        g = f.guess_all("", "", "scan.pdf", dt.date(2026, 10, 2))
        self.assertEqual((g["kind"], g["doc_date"], g["amount"]), ("invoice", "2026-10-02", None))


def make_pdf(text):
    import pymupdf

    doc = pymupdf.open()
    page = doc.new_page()
    page.insert_text((50, 60), text, fontsize=10)
    return doc.tobytes()


def make_email(sender, subject, attachments):
    m = email.message.EmailMessage()
    m["From"] = sender
    m["Subject"] = subject
    m["Date"] = "Thu, 01 Oct 2026 08:30:00 +0200"
    m.set_content("Please find attached.")
    for name, data in attachments:
        m.add_attachment(data, maintype="application", subtype="pdf", filename=name)
    return m.as_bytes()


ESKOM = [
    {"id": "e1", "name": "Eskom", "account_no": "7415912379", "addresses": ["noreply@eskomstatements.co.za"]},
    {"id": "e2", "name": "Eskom", "account_no": "8621974700", "addresses": ["noreply@eskomstatements.co.za"]},
    {"id": "k", "name": "Kanaan Vervoer", "account_no": "302", "addresses": ["accounts@kanaanvervoer.co.za"]},
    {"id": "o", "name": "Oorvloed Vervoer", "account_no": "302", "addresses": ["accounts@kanaanvervoer.co.za"]},
]


class SharedAddresses(unittest.TestCase):
    def test_account_number_or_name_picks_the_supplier(self):
        c = f.match_suppliers("noreply@eskomstatements.co.za", ESKOM)
        self.assertEqual([x["id"] for x in c], ["e1", "e2"])
        bill = "ESKOM TAX INVOICE\nAccount number: 862 197 4700\nCurrent due date: 08 Oct 2026\nAmount due R 3 210.55"
        s, sure = f.pick_supplier(c, bill)
        self.assertEqual((s["id"], sure), ("e2", True))
        self.assertEqual(f.guess_due_date(bill), dt.date(2026, 10, 8))
        self.assertEqual(f.guess_all(bill, "", "", dt.date(2026, 9, 25))["due_date"], "2026-10-08")
        # A due date before the bill's own date is a misread: dropped.
        odd = "ESKOM TAX INVOICE\nInvoice date: 19 Jun 2026\nDue date: 03 Jun 2026\nAmount due R 25 106.61"
        self.assertIsNone(f.guess_all(odd, "", "", dt.date(2026, 6, 19))["due_date"])
        # Eskom: the current due date, not the previous bill's; an unpaid
        # previous bill isn't counted again.
        eskom = ("YOUR ACCOUNT NO 9041537036\nBILLING DATE 2026-09-25\nTAX INVOICE NO 904853674597\n"
                 "BALANCE BROUGHT FORWARD (Due Date 2026-09-21) R 17,765.49\n"
                 "PAYMENT(S) RECEIVED ACB Payment - 2026-09-21 R -7,765.49\n"
                 "0787 CURRENT DUE DATE 2026-10-20 BRANCH CODE: 335645\n"
                 "TOTAL CHARGES FOR BILLING PERIOD R 15,893.09\nVAT RAISED ON ITEMS AT 15% R 2,383.96\n"
                 "28,277.05 TOTAL AMOUNT DUE 28,277.05\n")
        g = f.guess_all(eskom, "", "9041537036_904853674597.pdf", dt.date(2026, 9, 26))
        self.assertEqual((g["doc_date"], g["due_date"], g["amount"], g["reference"]), ("2026-09-25", "2026-10-20", 18277.05, "904853674597"))
        paid = eskom.replace("R -7,765.49", "R -17,765.49").replace("28,277.05", "18,277.05")
        self.assertEqual(f.guess_all(paid, "", "", dt.date(2026, 9, 26))["amount"], 18277.05)
        # Same account number "302": the name decides.
        c = f.match_suppliers("accounts@kanaanvervoer.co.za", ESKOM)
        s, sure = f.pick_supplier(c, "OORVLOED VERVOER\nStatement\nAccount 302")
        self.assertEqual((s["id"], sure), ("o", True))
        # Can't tell: the first, marked to check.
        s, sure = f.pick_supplier(c, "Statement for account 302")
        self.assertFalse(sure)


class FakeApp:
    def __init__(self):
        self.added = []
        self.keys = set()

    def already_added(self, key):
        return key in self.keys

    def add(self, supplier, pdf, filename, guess, sender, subject, sent, key, note=None):
        self.keys.add(key)
        self.added.append((supplier["name"], filename, guess, sender, key))


class Emails(unittest.TestCase):
    def test_supplier_email_pdfs_added_others_ignored(self):
        app = FakeApp()
        raw = make_email("Agri Accounts <accounts@agri.co.za>", "Invoice INV-20488",
                         [("INV-20488.pdf", make_pdf(INVOICE)), ("not-a-pdf.pdf", b"hello")])
        self.assertEqual(f.process_message(raw, "111", SUPPLIERS, app, log=lambda *_: None), 1)
        supplier, name, guess, sender, key = app.added[0]
        self.assertEqual((supplier, name, sender, key), ("Agri Supplies", "INV-20488.pdf", "accounts@agri.co.za", "gmail:111:INV-20488.pdf"))
        self.assertEqual(guess["amount"], 5577.50)
        self.assertEqual(guess["kind"], "invoice")
        # The same email again: nothing added twice.
        self.assertEqual(f.process_message(raw, "111", SUPPLIERS, app, log=lambda *_: None), 0)
        # Someone who isn't a supplier: ignored.
        other = make_email("friend@gmail.com", "Photos", [("x.pdf", make_pdf(INVOICE))])
        self.assertEqual(f.process_message(other, "222", SUPPLIERS, app, log=lambda *_: None), 0)
        # A statement from the supplier's domain.
        st = make_email("noreply@fueldepot.com", "Your September statement", [("stmt.pdf", make_pdf(STATEMENT))])
        self.assertEqual(f.process_message(st, "333", SUPPLIERS, app, log=lambda *_: None), 1)
        self.assertEqual(app.added[-1][2]["kind"], "statement")
        self.assertEqual(app.added[-1][2]["amount"], 8450.75)


if __name__ == "__main__":
    unittest.main()
