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
        self.assertEqual(f.match_supplier("sales@agri.co.za", SUPPLIERS)["id"], "s1")  # another address at the company
        self.assertIsNone(f.match_supplier("sales@agri.com", SUPPLIERS))
        self.assertIn("from:(agri.co.za OR fueldepot.com)", f.gmail_query(SUPPLIERS, 60))
        self.assertEqual(f.supplier_addresses("debtors@agrico.co.za, agrico.co.za"), ["debtors@agrico.co.za", "@agrico.co.za"])
        # A billing service: only the address itself (both municipal accounts' statements).
        self.assertIn("from:(statements@billit.co.za)", f.gmail_query([{"addresses": ["statements@billit.co.za"]}], 60))
        self.assertEqual(f.match_suppliers("other@billit.co.za", [{"id": "m", "addresses": ["statements@billit.co.za"]}]), [])
        # Free mail: only the address itself.
        self.assertIn("from:(ntbswartwater@gmail.com)", f.gmail_query([{"addresses": ["ntbswartwater@gmail.com"]}], 60))
        self.assertIn("newer_than:60d", f.gmail_query(SUPPLIERS, 60))
        self.assertIn('"has:attachment filename:pdf after:2026/03/01 from:(', f.gmail_query(SUPPLIERS, 60, dt.date(2026, 3, 1)))

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
        self.assertTrue(f.IGNORE_NAMES.search("VKB_AANW_58889_20260618.pdf"))
        self.assertFalse(f.IGNORE_NAMES.search("L0471927-20260903.pdf"))
        for leaflet in ["Connect 2026.pdf", "Rooftop Solar PV_Connect_v2.pdf", "Eskom_IT3b_4030725329.pdf"]:
            self.assertTrue(f.IGNORE_NAMES.search(leaflet), leaflet)
        for bill in ["9041537036_904853674597.pdf", "CCF_000553.pdf", "7415912379.pdf", "INV3403.pdf"]:
            self.assertFalse(f.IGNORE_NAMES.search(bill), bill)
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
        # VKB invoice (Afrikaans): TOTAAL not SUBTOTAAL, the date "20260928", the number from the file name.
        vkb_inv = ("BELASTINGFAKTUUR\n0\nNANINI 121 BK\n"
                   "PLAAS HAASKRAAL L0471927 20260928 4840191854 199617 1 0 PIETERSBURG ALGEMENE\n"
                   "ARTIKELKODE BESKRYWING EENHEID HOEV EENH PRYS BRUTO AFSL% NETTO BTW TOTAAL\n"
                   "512268 WYNN'S CHAIN WAX 1.000 249.650 249.65 0.00 249.65 37.45 287.10\n"
                   "KONTROLE MASSA 0.003 T SUBTOTAAL : 889.88\n"
                   "LIMIET VERBRUIK SOOS OM (PLUS) BTW : 110.99\n"
                   "BEHARTIG DEUR:............... TYD 12:06 = 37.94 % TOTAAL : 1000.87\n")
        g = f.guess_all(vkb_inv, "", "PBAH199617.pdf", dt.date(2026, 9, 28))
        self.assertEqual(g, {"kind": "invoice", "doc_date": "2026-09-28", "amount": 1000.87, "reference": "PBAH199617", "due_date": None})
        self.assertNotIn("cash_sale", g)
        cash = f.guess_all("KONTANT BELASTINGFAKTUUR\nPLAAS HAASKRAAL L0471927 20260605 4840191854\n"
                           "6135 DIESEL 50PPM 50.000 30.5400 1527.00 0.00 1527.00 0.00 1527.00\n"
                           "(PLUS) BTW : 0.00 KLEINGELD : 0.00\nTOTAAL : 1527.00 BETALINGSMETODE : KAART\n", "", "BKAH126073.pdf", dt.date(2026, 6, 5))
        self.assertEqual((cash["amount"], cash.get("cash_sale"), cash["doc_date"]), (1527.00, True, "2026-06-05"))
        cn = f.guess_all("KREDIETNOTA\n20260917\nTOTAAL : 120.50-\n", "", "PBMO154938.pdf", dt.date(2026, 9, 17))
        self.assertEqual((g["kind"], cn["kind"], cn["amount"], cn["reference"]), ("invoice", "credit_note", 120.50, "PBMO154938"))
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
        # Eskom: a bill carries the account -- a statement: total due, the
        # unpaid previous bill already due, the current due date (not the
        # previous bill's).
        eskom = ("YOUR ACCOUNT NO 9041537036\nBILLING DATE 2026-09-25\nTAX INVOICE NO 904853674597\n"
                 "BALANCE BROUGHT FORWARD (Due Date 2026-09-21) R 17,765.49\n"
                 "PAYMENT(S) RECEIVED ACB Payment - 2026-09-21 R -7,765.49\n"
                 "0787 CURRENT DUE DATE 2026-10-20 BRANCH CODE: 335645\n"
                 "TOTAL CHARGES FOR BILLING PERIOD R 15,893.09\nVAT RAISED ON ITEMS AT 15% R 2,383.96\n"
                 "28,277.05 TOTAL AMOUNT DUE 28,277.05\n")
        g = f.guess_all(eskom, "", "9041537036_904853674597.pdf", dt.date(2026, 9, 26))
        self.assertEqual(g, {"kind": "statement", "doc_date": "2026-09-25", "amount": 28277.05, "reference": "904853674597",
                             "due_date": "2026-10-20", "overdue_amount": 10000.00})
        paid = eskom.replace("R -7,765.49", "R -17,765.49").replace("28,277.05", "18,277.05")
        g = f.guess_all(paid, "", "", dt.date(2026, 9, 26))
        self.assertEqual((g["kind"], g["amount"], g.get("overdue_amount")), ("statement", 18277.05, None))
        # Eskom's disconnection notice: not an invoice -- shown as a warning.
        notice = ("NANINI 121 CC Date: 2026-09-10\nNOTICE OF DISCONNECTION FOR NON-PAYMENT\nACCOUNT NUMBER: 8441635490\n"
                  "above account. The overdue amount as at the date of this notice is R 8245.02\n"
                  "If you have not paid the full outstanding amount by 2 026-09-23 your electricity supply will be disconnected\n")
        g = f.guess_all(notice, "", "8441635490.pdf", dt.date(2026, 9, 10))
        self.assertEqual((g["kind"], g["doc_date"], g["amount"], g["due_date"]), ("invoice", "2026-09-10", None, None))
        self.assertIn("R8,245.02 overdue -- to be paid by 2026-09-23", g["notice"])
        self.assertNotIn("notice", f.guess_all(bill, "", "", dt.date(2026, 9, 25)))
        # Another address at the supplier's company (Agrico's invoices): it.
        agrico = [{"id": "a", "name": "Agrico", "addresses": ["debtors@agrico.co.za"]},
                  {"id": "n", "name": "NTB", "addresses": ["ntbswartwater@gmail.com"]}]
        self.assertEqual([x["id"] for x in f.match_suppliers("tzaneen@agrico.co.za", agrico)], ["a"])
        # Not someone else on free mail.
        self.assertEqual(f.match_suppliers("someone@gmail.com", agrico), [])
        # Same account number "302": the name decides.
        c = f.match_suppliers("accounts@kanaanvervoer.co.za", ESKOM)
        s, sure = f.pick_supplier(c, "OORVLOED VERVOER\nStatement\nAccount 302")
        self.assertEqual((s["id"], sure), ("o", True))
        # Can't tell: the first, marked to check.
        s, sure = f.pick_supplier(c, "Statement for account 302")
        self.assertFalse(sure)


VKB_INVOICE = """BELASTINGFAKTUUR
PLAAS HAASKRAAL L0471927 20260928 4840191854 199617 1 0 PIETERSBURG ALGEMENE
ARTIKELKODE BESKRYWING EENHEID HOEV EENH PRYS BRUTO AFSL% NETTO BTW TOTAAL
512268 WYNN'S CHAIN WAX 1.000 249.650 249.65 0.00 249.65 37.45 287.10
375ml KOSPRYS KODE : 07747.405
480840 PROTEK RAT & MOUSE 1.000 52.820 52.82 0.00 52.82 0.00 52.82
WAX BLOCKS 95G KOSPRYS KODE : 54434.68
114916 WYNN'S NUT LOCK 7g 2.000 63.510 127.02 0.00 127.02 19.05 146.07
KOSPRYS KODE : 14933.88
KONTROLE MASSA 0.003 T SUBTOTAAL : 429.49
LIMIET VERBRUIK SOOS OM (PLUS) BTW : 56.50
BEHARTIG DEUR:............... TYD 12:06 = 37.94 % TOTAAL : 485.99
"""


class PurchasesDetails(unittest.TestCase):
    def test_vkb_lines_and_vat(self):
        g = f.guess_full(VKB_INVOICE, "", "PBAH199617.pdf", dt.date(2026, 9, 28))
        self.assertEqual((g["amount"], g["vat_amount"]), (485.99, 56.50))
        self.assertEqual(g["lines"], [
            {"description": "WYNN'S CHAIN WAX 375ml", "quantity": 1.0, "excl_amount": 249.65, "vat_amount": 37.45},
            {"description": "PROTEK RAT & MOUSE WAX BLOCKS 95G", "quantity": 1.0, "excl_amount": 52.82, "vat_amount": 0.0},
            {"description": "WYNN'S NUT LOCK 7g", "quantity": 2.0, "excl_amount": 127.02, "vat_amount": 19.05},
        ])
        self.assertTrue(g["description"].startswith("WYNN'S CHAIN WAX 375ml, PROTEK"))
        # A credit note: the lines go negative.
        cn = f.guess_lines(VKB_INVOICE, "credit_note", 485.99, {})
        self.assertEqual(cn[0]["excl_amount"], -249.65)

    def test_one_line_when_no_items(self):
        g = f.guess_full(INVOICE, "", "inv.pdf", dt.date(2026, 9, 15))
        self.assertEqual(g["vat_amount"], 727.50)
        self.assertEqual(g["lines"], [{"description": None, "quantity": None, "excl_amount": 4850.00, "vat_amount": 727.50}])
        # A statement: no lines (its purchases are on the invoices).
        self.assertEqual(f.guess_full(STATEMENT, "", "stmt.pdf", dt.date(2026, 10, 1))["lines"], [])

    def test_sage_invoice(self):
        oorvloed = ("Tax Invoice\nVAT REG NO: 4320289228\nDate 05/06/2026\nOORVLOED VERVOER\nDocument No INV3403\n"
                    "Account Your Reference Tax Exempt Tax Reference Sales Code\n302 AFLEWERING 03940 N Exclusive\n"
                    "Code Description Quantity Unit Unit Price Disc% Tax Nett Price\n"
                    "1000028 04/06 HFC950L na Pta 3,060.00 20,400.00\n1000999 Overload 0.00 1,000.00\n1000999 Forklift 0.00 1,500.32\n"
                    "Sub Total 22,900.32\nAmount Excl Tax 22,900.32\nTax 3,060.00\n"
                    "Signed___________________ Date__________________ Total 25,960.32\n")
        g = f.guess_full(oorvloed, "", "INV3403.pdf", dt.date(2026, 6, 5))
        self.assertEqual((g["amount"], g["vat_amount"], g["reference"]), (25960.32, 3060.00, "INV3403"))
        self.assertEqual(g["lines"], [
            {"description": "04/06 HFC950L na Pta", "quantity": None, "excl_amount": 20400.00, "vat_amount": 3060.00},
            {"description": "Overload", "quantity": None, "excl_amount": 1000.00, "vat_amount": 0.00},
            {"description": "Forklift", "quantity": None, "excl_amount": 1500.32, "vat_amount": 0.00},
        ])

    def test_omnia_invoice(self):
        omnia = ("Omnia Fertilizer, a division of Omnia Group (Pty) Ltd Tax invoice\nVAT No 4680233469\n"
                 "Order account Invoice account Invoice no OF27LVD008562SIN\nInvoice date 08/09/2026\n0557 0557 Due date 31/10/2026\n"
                 "Product code Product description Product category Customer load reference UOM Quantity Unit price Gross amt (Excl. VAT Net amt (Incl.\n"
                 "VAT) VAT)\n"
                 "OOK/K6970 POTASSIUM SULPHATE GRAN 50KG Factored Goods TN 2.000 15,622.00 31,244.00 0.00 31,244.00\n"
                 "Own transport 2.000 1,040.00 2,080.00 312.00 2,392.00\nTotal 33,324.00 312.00 33,636.00\nTotal 33,324.00 312.00 33,636.00\n")
        g = f.guess_full(omnia, "", "omnia_ci_flvd_email_email_32777530_OF27LVD008562SIN_95.pdf", dt.date(2026, 9, 8))
        self.assertEqual((g["kind"], g["amount"], g["vat_amount"], g["due_date"]), ("invoice", 33636.00, 312.00, "2026-10-31"))
        self.assertEqual(g["lines"], [
            {"description": "POTASSIUM SULPHATE GRAN 50KG Factored Goods", "quantity": 2.0, "excl_amount": 31244.00, "vat_amount": 0.00},
            {"description": "Own transport", "quantity": 2.0, "excl_amount": 2080.00, "vat_amount": 312.00},
        ])

    def test_omnia_cash_discount_lines(self):
        omnia = ("Omnia Fertilizer Invoice\nInvoice no OF26LVD023287SIN\nInvoice date 03/03/2026\n"
                 "OOK/K3675 2:3:4(30)+0,50%Zn 50KG Granulars TN 6.000 10,524.49 63,146.94 0.00 63,146.94\n"
                 "Cash discount 2.00% -210.49 -1,262.94 0.00 -1,262.94\n"
                 "Road transport 6.000 850.00 5,100.00 765.00 5,865.00\nTotal 66,984.00 765.00 67,749.00\n"
                 "Total 66,984.00 765.00 67,749.00\n")
        g = f.guess_full(omnia, "", "omnia_ci_flvd_email_email_32777530_OF26LVD023287SIN_55.pdf", dt.date(2026, 3, 3))
        self.assertEqual((g["amount"], g["vat_amount"]), (67749.00, 765.00))
        self.assertEqual([(l["description"], l["excl_amount"], l["vat_amount"]) for l in g["lines"]],
                         [("2:3:4(30)+0,50%Zn 50KG Granulars", 63146.94, 0.0), ("Cash discount", -1262.94, 0.0), ("Road transport", 5100.00, 765.00)])

    def test_eskom_bill_charges(self):
        bill = ("ESKOM\nYOUR ACCOUNT NO 9041537036\nBILLING DATE 2026-09-25\nACCOUNT MONTH SEPTEMBER 2026\n"
                "BALANCE BROUGHT FORWARD (Due Date 2026-09-21) R 17,765.49\nPAYMENT(S) RECEIVED ACB Payment - 2026-09-21 R -17,765.49\n"
                "CURRENT DUE DATE 2026-10-20\nTOTAL CHARGES FOR BILLING PERIOD R 15,893.09\nVAT RAISED ON ITEMS AT 15% R 2,383.96\n"
                "18,277.05 TOTAL AMOUNT DUE 18,277.05\n")
        g = f.guess_full(bill, "", "9041537036_904853674597.pdf", dt.date(2026, 9, 26))
        self.assertEqual((g["kind"], g["purchases_amount"], g["vat_amount"], g["description"]),
                         ("statement", 18277.05, 2383.96, "Electricity September 2026"))
        self.assertEqual(g["lines"], [{"description": "Electricity September 2026", "quantity": None, "excl_amount": 15893.09, "vat_amount": 2383.96}])

    def test_eskom_bigger_account_bill(self):
        bill = ("ESKOM HOLDINGS SOC LTD\nYOURACCOUNTNO 8441635490\nP O BOX 182 BILLINGDATE 2026-09-28 PO BOX 8610\n"
                "FAUNA PARK TAXINVOICENO 844541920439 DIRECTDEPOSITDETAIL\nLEPHALALE ACCOUNTMONTH SEPTEMBER 2026 BANK: First National Bank\n"
                "0787 CURRENTDUEDATE 2026-10-13 BRANCHCODE: 260148\nARREARS TOTALAMOUNT DUE\n>90DAYS 61-90DAYS 31-60DAYS 16-30DAYS\n"
                "0.00 0.00 8,245.02 0.00\n75,029.57\nTOTAL CHARGES FOR BILLING PERIOD R 57,981.99\n"
                "BALANCE BROUGHT FORWARD (Due Date 2026-09-08) R 63,211.85\nPAYMENT(S) RECEIVED ACB Payment - 2026-09-08 R -54,966.83\n"
                "TOTAL CHARGES FOR BILLING PERIOD R 57,981.99\nADJUSTMENT Interest on overdue account R 14.23\n"
                "ADJUSTMENT Interest on overdue account R 91.03\nVAT RAISED ON ITEMS AT 15% R 8,697.30\nCURRENT\n"
                "66,784.55 TOTALDUE R 75,029.57\nTOTAL CHARGES R 57,981.99\n")
        g = f.guess_full(bill, "", "8441635490_844541920439.pdf", dt.date(2026, 9, 29))
        self.assertEqual((g["kind"], g["amount"], g["overdue_amount"], g["due_date"], g["purchases_amount"], g["vat_amount"], g["description"]),
                         ("statement", 75029.57, 8245.02, "2026-10-13", 66784.55, 8697.30, "Electricity September 2026"))
        self.assertEqual((g["brought_forward"], g["payments_received"]), (63211.85, [{"date": "2026-09-08", "amount": 54966.83}]))
        self.assertEqual(g["lines"], [
            {"description": "Electricity September 2026", "quantity": None, "excl_amount": 57981.99, "vat_amount": 8697.30},
            {"description": "Interest on overdue account", "quantity": None, "excl_amount": 14.23, "vat_amount": 0.0},
            {"description": "Interest on overdue account", "quantity": None, "excl_amount": 91.03, "vat_amount": 0.0},
        ])

    def test_eskom_usage_and_fixed_charges(self):
        bill = ("ESKOM\nYOUR ACCOUNT NO 9041537036\nBILLING DATE 2026-09-25\nACCOUNT MONTH SEPTEMBER 2026\n"
                "READING TYPE: ESTIMATE READING DATES: 2026/08/25 - 2026/09/23 NO OF DAYS: 29 SEASON:\n"
                "TOTAL ENERGY CONSUMED FOR BILLING PERIOD (kWh) 3,144.00\n"
                "Service and Administration Charge @ R26.65 per day for 29 days R 772.85\n"
                "Network Capacity Charge @ R168.93 per day for 29 days R 4,898.97\n"
                "Network Demand Charge 3,144 kWh @ R0.6706 /kWh R 2,108.37\n"
                "Ancillary Service Charge 3,144 kWh @ R0.0045 /kWh R 14.15\n"
                "Generation Capacity Charge @ R15.93 per day for 29 days R 461.97\n"
                "Energy Charge 3,144 kWh @ R2.429 /kWh R 7,636.78\n"
                "Network Capacity Charge 200 kVA @ R56.60 : = R56.60/kVA R 11,320.00\n"
                "TOTAL CHARGES FOR BILLING PERIOD R 15,893.09\n")
        d = f.guess_bill_details(bill)
        self.assertEqual((d["kwh"], d["days"], d["from"], d["to"]), (3144.0, 29, "2026-08-25", "2026-09-23"))
        self.assertEqual(d["reading"], "estimate")
        self.assertEqual([(c["kind"], c["unit"], c["rate"]) for c in d["charges"]], [
            ("fixed", "day", 26.65), ("fixed", "day", 168.93), ("usage", "kWh", 0.6706), ("usage", "kWh", 0.0045),
            ("fixed", "day", 15.93), ("usage", "kWh", 2.429), ("fixed", "kVA", 56.60)])
        self.assertEqual(d["charges"][0]["days"], 29)
        self.assertEqual(d["charges"][-1]["quantity"], 200.0)
        self.assertIsNone(f.guess_bill_details("no charges here"))

    def test_eskom_rebill_credit(self):
        bill = ("ESKOM\nYOUR ACCOUNT NO 9512455247\nBILLING DATE 2026-06-01\nACCOUNT MONTH JUNE 2026\nCURRENT DUE DATE 2026-06-26\n"
                "TOTAL ENERGY CONSUMED FOR BILLING PERIOD (kWh) 12,106.00\n"
                "Service and Administration Charge @ R24.50 per day for 98 days R 2,401.00\n"
                "Service and Administration Charge @ R26.65 per day for 56 days R 1,492.40\n"
                "Network Demand Charge 7,704 kWh @ R0.6166 /kWh R 4,750.29\n"
                "Network Demand Charge 4,402 kWh @ R0.6706 /kWh R 2,951.98\n"
                "REBILLED ADJUSTMENTS (Summary - See attachment for details) R -107,114.59\n"
                "TOTAL CHARGES FOR BILLING PERIOD R - 51,051.33\n"
                "BALANCE BROUGHT FORWARD (Due Date 2026-05-29) R 32,806.10\n"
                "PAYMENT(S) RECEIVED ACB Payment - 2026-05-29 R -32,806.19\n"
                "TOTAL CHARGES FOR BILLING PERIOD R -51,051.33\n"
                "VAT RAISED ON ITEMS AT 15% R -7,657.70\nCURRENT\n"
                "58,709.12- TOTAL AMOUNT DUE 58,709.12CR\n"
                "REBILLED ADJUSTMENTS R -107,114.59\n"
                "Service and Administration Charge @ R24.50 per day for 25 d R -612.50\n"
                "Network Demand Charge 3,080 kWh @ R0.6166 /kWh R -1,899.13\n")
        g = f.guess_full(bill, "", "9512455247_951368867928.pdf", dt.date(2026, 6, 2))
        self.assertEqual((g["kind"], g["amount"], g["purchases_amount"], g["vat_amount"], g.get("overdue_amount")),
                         ("statement", -58709.12, -58709.03, -7657.70, None))
        self.assertEqual(g["lines"][0]["excl_amount"], -51051.33)
        d = g["bill_details"]
        self.assertEqual((d["kwh"], d["days"]), (12106.0, 154))
        self.assertEqual([(c["kind"], c["amount"]) for c in d["charges"]],
                         [("fixed", 2401.00), ("fixed", 1492.40), ("usage", 4750.29), ("usage", 2951.98), ("adjustment", -107114.59)])

    def test_fill_details_for_docs_already_in(self):
        class App:
            dry_run = False

            def __init__(self):
                self.lines, self.updates = {}, {}

            def docs_without_lines(self):
                return [
                    {"id": "d1", "kind": "invoice", "amount": 485.99, "doc_date": "2026-09-28", "reference": "PBAH199617",
                     "file_path": "v/1.pdf", "file_name": "PBAH199617.pdf", "notes": None, "vat_amount": None, "description": None},
                    {"id": "d2", "kind": "invoice", "amount": 0, "doc_date": "2026-09-10", "reference": None,
                     "file_path": "e/2.pdf", "file_name": "8441635490.pdf", "notes": "DISCONNECTION NOTICE ...", "vat_amount": None, "description": None},
                ]

            def download(self, path):
                return make_pdf(VKB_INVOICE)

            def update_doc(self, doc_id, fields):
                self.updates[doc_id] = fields

            def add_lines(self, doc_id, lines):
                self.lines[doc_id] = lines

        app = App()
        self.assertEqual(f.fill_details(app, log=lambda *_: None), (1, 1))
        self.assertEqual(len(app.lines["d1"]), 3)
        self.assertEqual(app.updates["d1"]["vat_amount"], 56.50)


class Reread(unittest.TestCase):
    def test_reread_corrects_amount_and_lines(self):
        bill = ("ESKOM\nYOURACCOUNTNO 8441635490\nBILLINGDATE 2026-09-28\nACCOUNTMONTH SEPTEMBER 2026\nCURRENTDUEDATE 2026-10-13\n"
                "0.00 0.00 8,245.02 0.00\nBALANCE BROUGHT FORWARD (Due Date 2026-09-08) R 63,211.85\n"
                "PAYMENT(S) RECEIVED ACB Payment - 2026-09-08 R -54,966.83\nTOTAL CHARGES FOR BILLING PERIOD R 57,981.99\n"
                "VAT RAISED ON ITEMS AT 15% R 8,697.30\n66,679.29 TOTALDUE R 74,924.31\n")

        class App:
            dry_run = False

            def __init__(self):
                self.updates, self.lines, self.cleared = {}, {}, []

            def docs_of(self, name):
                assert name == "Eskom - 8441635490"
                return [{"id": "b", "kind": "statement", "amount": 57981.99, "doc_date": "2026-09-28", "reference": "844541920439",
                         "file_path": "e/b.pdf", "file_name": "8441635490_844541920439.pdf", "notes": None, "email_date": "2026-09-29",
                         "email_subject": "", "vat_amount": 8697.30, "description": None}]

            def download(self, path):
                return make_pdf(bill)

            def update_doc(self, doc_id, fields):
                self.updates[doc_id] = fields

            def clear_lines(self, doc_id):
                self.cleared.append(doc_id)

            def add_lines(self, doc_id, lines):
                self.lines[doc_id] = lines

        app = App()
        log = []
        self.assertEqual(f.fill_details(app, log=log.append, reread="Eskom - 8441635490"), (1, 0))
        u = app.updates["b"]
        self.assertEqual((u["amount"], u["due_date"], u["overdue_amount"], u["purchases_amount"]), (74924.31, "2026-10-13", 8245.02, 66679.29))
        self.assertEqual(app.cleared, ["b"])
        self.assertEqual(app.lines["b"][0]["excl_amount"], 57981.99)
        self.assertIn("R57,981.99 -> R74,924.31", log[0])


class FakeApp:
    def __init__(self):
        self.added = []
        self.keys = set()

    def already_added(self, key):
        return key in self.keys

    def same_doc(self, supplier, guess):
        for name, filename, g, _, _ in self.added:
            if name == supplier["name"] and all(g.get(k) == guess.get(k) for k in ("kind", "doc_date", "amount", "reference")) \
                    and guess.get("amount") is not None:
                return filename
        return None

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

    def test_a_disconnection_notice_is_only_said_not_added(self):
        app = FakeApp()
        notice = ("NANINI 121 CC Date: 2026-09-10\nNOTICE OF DISCONNECTION FOR NON-PAYMENT\nACCOUNT NUMBER: 8441635490\n"
                  "above account. The overdue amount as at the date of this notice is R 8245.02\n")
        raw = make_email("Agri Accounts <accounts@agri.co.za>", "Notice", [("notice.pdf", make_pdf(notice))])
        said = []
        self.assertEqual(f.process_message(raw, "999", SUPPLIERS, app, log=said.append), 0)
        self.assertEqual(app.added, [])
        self.assertIn("DISCONNECTION NOTICE", said[0])
        self.assertIn("not added to the app", said[0])

    def test_another_address_at_the_company_only_clear_invoices(self):
        app = FakeApp()
        letter = make_email("Someone <someone@agri.co.za>", "Facility letter", [("Fasiliteitsbrief.pdf", make_pdf("Dear client, your facility ..."))])
        invoice = make_email("Branch <branch@agri.co.za>", "Invoice", [("INV-20488.pdf", make_pdf(INVOICE))])
        proforma = make_email("Agri Accounts <accounts@agri.co.za>", "Quote", [("PRO-FORMA.pdf", make_pdf(INVOICE))])
        said = []
        self.assertEqual(f.process_message(letter, "1", SUPPLIERS, app, log=said.append), 0)
        self.assertIn("not clearly an invoice", said[0])
        self.assertEqual(f.process_message(invoice, "2", SUPPLIERS, app, log=said.append), 1)
        self.assertEqual(f.process_message(proforma, "3", SUPPLIERS, app, log=said.append), 0)  # a pro-forma: not an invoice

    def test_the_same_pdf_in_another_email_is_not_added_again(self):
        app = FakeApp()
        pdf = make_pdf(INVOICE)
        first = make_email("Agri Accounts <accounts@agri.co.za>", "Invoice INV-20488", [("INV-20488.pdf", pdf)])
        again = make_email("Agri Accounts <accounts@agri.co.za>", "FW: Invoice INV-20488", [("INV-20488.pdf", pdf)])
        self.assertEqual(f.process_message(first, "111", SUPPLIERS, app, log=lambda *_: None), 1)
        said = []
        self.assertEqual(f.process_message(again, "112", SUPPLIERS, app, log=said.append), 0)
        self.assertEqual(len(app.added), 1)
        self.assertIn("already in the app", said[0])

    def test_agrico_invoice_number_from_the_file_name(self):
        self.assertEqual(f.guess_reference("Please quoted ...", "invoice", "", "INV141-067305(NAN005-01-AR)(Agrico)(2026-05-22).pdf"),
                         "INV141-067305")
        self.assertEqual(f.guess_reference("", "invoice", "", "SIN408297(NOVON).pdf"), "SIN408297")


class Novon(unittest.TestCase):
    def test_invoice(self):
        text = """Novon Retail Company (RF) (Pty) Ltd Telephone (012) 808 1513
Tax Registration 4870205871
Tax Invoice
Account Order No Date Delivery Note SO Number Our Reference
000472 14/08/2026 SO351487 SIN416324
Item Code Item Description Units Price (Ex) Disc % Tax Total (Incl)
000204 ALLBUFF-484SL-20L-ZA 1.0000 R 845.57 R R 845.57
Total (Excl) R 845.57
Your Ref. 000472 Tax R 0.00
Invoice Total R 845.57
"""
        g = f.guess_full(text, "", "SIN416324(000472)(Novon Retail Company (RF) (Pty) Ltd)(2026-08-14).pdf", dt.date(2026, 8, 14))
        self.assertEqual((g["kind"], g["reference"], g["amount"], g["vat_amount"]), ("invoice", "SIN416324", 845.57, 0.0))
        self.assertEqual(g["lines"], [{"description": "ALLBUFF-484SL-20L-ZA", "quantity": 1.0, "excl_amount": 845.57, "vat_amount": 0.0}])
        # A line with discount and VAT.
        self.assertEqual(f.novon_lines("000210 KNAPSACK 16L 2.0000 R 400.00 5 R 114.00 R 874.00"),
                         [{"description": "KNAPSACK 16L", "quantity": 2.0, "excl_amount": 760.0, "vat_amount": 114.0}])


class NovonStatement(unittest.TestCase):
    def test_balance_not_the_amount_due_now(self):
        text = """Novon Retail Company (RF) (Pty) Ltd
Statement
Account 000472
Statement Date 2026/06/30
FAUNAPARK
0787 Acc Balance 6 312.94
Date Reference Description Allocated To Debit Credit Balance
2026/06/01 Balance Brought Forward 31 072.03 31 072.03
2026/06/03 NRC028657 PAYMENT RECEIVED 30 226.29 845.74
2026/06/18 SIN413699 Sales Order 5 467.20 6 312.94
180 Days 150 Days 120 Days 90 Days 60 Days 30 Days Jun-26
0.00 0.00 0.00 0.00 0.70 845.04 5 467.20 6 312.94
Amount due on 2026/06/30 845.74
"""
        g = f.guess_full(text, "", "Statement_000472_2026-06-30.pdf", dt.date(2026, 7, 1))
        # Not "30 845.74" (the date's day and the amount).
        self.assertEqual((g["kind"], g["doc_date"], g["amount"], g["overdue_amount"]), ("statement", "2026-06-30", 6312.94, 845.74))


class NtbStatement(unittest.TestCase):
    def test_dated_for_the_month_of_its_transactions_not_the_bf(self):
        text = """Swartwater Boerebesonderhede BK h/a
NOORD TRANVAAL BOERE
Customer Acc Info
Account Number: C012
SWARTWATER Opening Balance 176,816.66
Closing Balance 44,807.18
Last Paid Date: 07-Sept-26
Date Transaction # Transaction Type Order No. Debit Credit X Amount
2026/08/31 0B6:/5F4:16 Balance B/F 176,816.66 176,816.66
2026/09/01 0A8:C15C:10202-70795 Account 1,028.00 177,844.66
2026/09/07 1A1:C44C:P23AYMENT1934831 Account Payment -176,816.66 1,028.00
2026/09/28 1A2:C30C:35974402 Account DEL 28/09/2026 9,013.94 44,807.18
0.00 0.00 0.00 0.00 0.00 0.00 R 44,807.18 R 44,807.18
"""
        g = f.guess_full(text, "", "S_C012.pdf", dt.date(2026, 10, 2))
        self.assertEqual((g["kind"], g["doc_date"], g["amount"]), ("statement", "2026-09-30", 44807.18))


class Municipality(unittest.TestCase):
    def test_polokwane_account(self):
        text = """TAX INVOICE
Tax Invoice / Statement
Account Number 0011672129 Vat Registration No. 4700193560
Account Date Erf No. Market Value
30 SEP 2026 LS-000000624-000177-0000 880,000.00
DATE CODE DESCRIPTION UNITS TARIFF VALUE
OPENING BALANCE 413.65
30/09/2026 100014 RATES AGRICULTURAL 880000 .00184 134.93
009009 INTEREST 3.93
009008 VAT 0.00
Total Subsidy 0.00
Sub Total 138.86
120 DAYS + 90 DAYS 60 DAYS 30 DAYS CURRENT Total
0.00 0.00 183.29 230.36 138.86 552.51
Total Due 552.51
Total Due on or before 26/10/2026 00001167212900000000003
"""
        g = f.guess_full(text, "", "0011672129-20260930-55155.pdf", dt.date(2026, 10, 2))
        self.assertEqual((g["kind"], g["doc_date"], g["amount"], g["due_date"], g["overdue_amount"], g["purchases_amount"]),
                         ("statement", "2026-09-30", 552.51, "2026-10-26", 413.65, 138.86))
        self.assertEqual([(l["description"], l["excl_amount"], l["vat_amount"]) for l in g["lines"]],
                         [("Rates Agricultural", 134.93, 0.0), ("Interest", 3.93, 0.0)])


class DeliveryNote(unittest.TestCase):
    def test_a_scanned_delivery_note_with_the_invoice_is_skipped(self):
        app = FakeApp()
        said = []
        raw = make_email("Agri Accounts <accounts@agri.co.za>", "Invoice INV-20488",
                         [("INV-20488.pdf", make_pdf(INVOICE)), ("CCF_000553.pdf", make_pdf("Load 34 t maize, signed"))])
        self.assertEqual(f.process_message(raw, "1", SUPPLIERS, app, log=said.append), 1)
        self.assertEqual([a[1] for a in app.added], ["INV-20488.pdf"])
        self.assertIn("CCF_000553.pdf skipped", "".join(said))
        # On its own, a document saying it's a delivery note.
        raw = make_email("Agri Accounts <accounts@agri.co.za>", "POD", [("scan.pdf", make_pdf("DELIVERY NOTE 4411\nReceived by"))])
        self.assertEqual(f.process_message(raw, "2", SUPPLIERS, app, log=said.append), 0)


class ValuationLetter(unittest.TestCase):
    def test_valuation_letters_are_not_added(self):
        self.assertEqual(f.guess_letter("POLOKWANE MUNICIPALITY\nNOTICE OF GENERAL VALUATION ROLL\nMarket value R 880 000.00"), "a valuation letter")
        self.assertEqual(f.guess_letter("Dear owner", "Valuation_0011672129.pdf"), "a valuation letter")
        account = "Tax Invoice / Statement\nOPENING BALANCE 413.65\nSub Total 138.86\nMarket Value 880,000.00\nvaluation roll"
        self.assertIsNone(f.guess_letter(account))  # an account: not a letter
        app = FakeApp()
        said = []
        muni = [{"id": "m", "name": "Polokwane Municipality - 0011672129", "account_no": "0011672129", "addresses": ["statements@billit.co.za"]}]
        raw = make_email("Billit <statements@billit.co.za>", "Valuation", [("0011672129.pdf", make_pdf(
            "Account Number 0011672129\nNOTICE OF GENERAL VALUATION ROLL\nMarket value R 880 000.00\n"))])
        self.assertEqual(f.process_message(raw, "1", muni, app, log=said.append), 0)
        self.assertEqual(app.added, [])
        self.assertIn("valuation letter", said[0])


class OtherAccount(unittest.TestCase):
    def test_a_second_account_not_in_the_app_is_flagged(self):
        muni = [{"id": "m", "name": "Polokwane Municipality - 0011672129", "account_no": "0011672129", "addresses": ["billingc@polokwane.gov.za"]}]
        self.assertIsNone(f.other_account(muni[0], "Account Number 0011672129 Vat Registration No. 4700193560"))
        self.assertEqual(f.other_account(muni[0], "Account Number 0011999999 Vat Registration No. 4700193560"), "0011999999")
        app = FakeApp()
        said = []
        raw = make_email("Billing <billingc@polokwane.gov.za>", "Account", [("0011999999-20260930.pdf", make_pdf(
            "Tax Invoice / Statement\nAccount Number 0011999999\nTotal Due 120.00\n"))])
        f.process_message(raw, "1", muni, app, log=said.append)
        self.assertIn("for account 0011999999", said[0])


class Kalkor(unittest.TestCase):
    def test_invoice_lines(self):
        text = """Tax Invoice
Kalkor (Pty) Ltd VAT Registration4160116838
Account Date Loading Number OOrrddeerr NNuummbbeerr Invoice Number
NAN003 31/07/2026 P07055 K68160 INV99794
Item Code Item Description Delivery Note Ordered Units Price (Ex) Disc VAT R Total (Incl) R
B2848lo Phokeng Gips / Gypsum Bulk ton 34.60 395.00 0.00 0.00 13,667.00
TRANS Vervoer / Transport ton 34.60 515.00 0.00 2,672.85 20,491.85
XXX Dankie vir u ondersteuning ton
Total (Excl) R 31,486.00
VAT R 2,672.85
Total (Incl) R 34,158.85
"""
        g = f.guess_full(text, "", "INV99794(NAN003)(Kalkor (Pty) Ltd)(2026-07-31)  K68160 - P07055.pdf", dt.date(2026, 7, 31))
        self.assertEqual((g["reference"], g["amount"], g["vat_amount"]), ("INV99794", 34158.85, 2672.85))
        self.assertEqual([(l["description"], l["quantity"], l["excl_amount"], l["vat_amount"]) for l in g["lines"]], [
            ("Phokeng Gips / Gypsum Bulk", 34.6, 13667.0, 0.0), ("Vervoer / Transport", 34.6, 17819.0, 2672.85)])


class SageStatement(unittest.TestCase):
    def test_credit_in_brackets(self):
        text = """Statement
Kalkor (Pty) Ltd Telephone (011) 721 3141
Robindale, Randburg Date 30/06/2026
Amount Due (897.81)
NAN003
Date Reference Description Allocated To Debit Credit Balance
01/04/2026 Balance Brought Forward 2,203.71 (2,203.71)
08/06/2026 Payment Received 35,821.29 (38,025.00)
23/06/2026 INV98986 Nanini 121 - K67627 37,127.19 (897.81)
180 Days 150 Days 120 Days 90 Days 60 Days 30 Days Current Amount Due
0.00 0.00 0.00 0.00 0.00 0.00 (897.81) (897.81)
"""
        g = f.guess_full(text, "", "Statement_NAN003_2026-06-30.pdf", dt.date(2026, 7, 1))
        self.assertEqual((g["kind"], g["doc_date"], g["amount"]), ("statement", "2026-06-30", -897.81))
        self.assertEqual(f.amounts_in("(2,203.71) 1,000.00 (10.00)"), [-2203.71, 1000.0, -10.0])
        # The invoice number from the file name, not our account number in the text.
        self.assertEqual(f.guess_reference("Tax Invoice No: NAN003", "invoice", "",
                                           "INV98096(NAN003)(Kalkor (Pty) Ltd)(2026-03-31)   K67054 - P06827.pdf"), "INV98096")


class GmailAccess(unittest.TestCase):
    """Both ways into Gmail give the same message numbers and raw emails."""

    def test_google_sign_in_api(self):
        import base64
        import gmail_access as g

        raw = make_email("accounts@agri.co.za", "Invoice", [("a.pdf", b"%PDF-1.4")])

        class Resp:
            def __init__(self, data, code=200):
                self.data, self.status_code = data, code

            def json(self):
                return self.data

            def raise_for_status(self):
                pass

        class Session:
            def __init__(self):
                self.calls = []

            def get(self, url, params=None, timeout=None):
                self.calls.append((url, dict(params or {})))
                if url.endswith("/messages") and "pageToken" not in params:
                    return Resp({"messages": [{"id": "18f0a1b2c3d4e5f6"}], "nextPageToken": "p2"})
                if url.endswith("/messages"):
                    return Resp({"messages": [{"id": "ff"}]})
                if url.endswith("/profile"):
                    return Resp({"emailAddress": "fourie05@gmail.com"})
                return Resp({"raw": base64.urlsafe_b64encode(raw).decode().rstrip("=")})

        session = Session()
        gm = g.ApiGmail(session)
        ids = gm.search('"has:attachment filename:pdf newer_than:7d from:(agri.co.za)"')
        # Gmail's ids are hex; kept as the same decimal numbers IMAP gave.
        self.assertEqual(ids, [str(0x18f0a1b2c3d4e5f6), "255"])
        self.assertEqual(session.calls[0][1]["q"], "has:attachment filename:pdf newer_than:7d from:(agri.co.za)")
        self.assertEqual(gm.fetch(ids[0]), raw)
        self.assertTrue(session.calls[-1][0].endswith("/messages/18f0a1b2c3d4e5f6"))
        self.assertEqual(session.calls[-1][1], {"format": "raw"})
        self.assertEqual(gm.address(), "fourie05@gmail.com")
        # Access taken away: a clear message.
        session.get = lambda *a, **k: Resp({}, 401)
        with self.assertRaises(g.GmailProblem):
            gm.search("x")

    def test_app_password_imap(self):
        import gmail_access as g

        raw = b"From: a@b.c\r\n\r\nhi"

        class Imap:
            def list(self):
                return "OK", [b'(\\HasNoChildren \\All) "/" "[Gmail]/All Mail"']

            def select(self, box, readonly=False):
                assert box == '"[Gmail]/All Mail"' and readonly

            def uid(self, cmd, *args):
                if cmd == "SEARCH":
                    return "OK", [b"7 9"]
                if args[1] == "(X-GM-MSGID)":
                    return "OK", [b"1 (X-GM-MSGID 1790000000000000%s UID %s)" % (args[0], args[0])]
                assert args[1] == "(BODY.PEEK[])"
                return "OK", [(b"1 (BODY[] {10}", raw), b")"]

        gm = g.ImapGmail(Imap(), "x@gmail.com")
        ids = gm.search("anything")
        self.assertEqual(ids, ["17900000000000007", "17900000000000009"])
        self.assertEqual(gm.fetch(ids[1]), raw)


class AddPdf(unittest.TestCase):
    def test_a_bill_from_this_pc(self):
        import tempfile

        bill = ("ESKOM\nYOUR ACCOUNT NO 8621974700\nBILLING DATE 2026-05-19\nACCOUNT MONTH MAY 2026\nCURRENT DUE DATE 2026-06-13\n"
                "BALANCE BROUGHT FORWARD (Due Date 2026-05-16) R 7,584.81\nPAYMENT(S) RECEIVED ACB Payment - 2026-05-06 R -7,584.81\n"
                "TOTAL CHARGES FOR BILLING PERIOD R 7,931.62\nVAT RAISED ON ITEMS AT 15% R 1,189.74\n9,121.36 TOTAL AMOUNT DUE 9,121.36\n")

        class App(FakeApp):
            dry_run = False

            def suppliers(self):
                return ESKOM

        app = App()
        with tempfile.TemporaryDirectory() as d:
            path = pathlib.Path(d) / "eskom_may.pdf"
            path.write_bytes(make_pdf(bill))
            self.assertTrue(f.add_pdf(path, app, log=lambda *_: None))  # account number in it: e2
            self.assertEqual(app.added[0][0], "Eskom")
            self.assertEqual(app.added[0][2]["amount"], 9121.36)
            self.assertFalse(f.add_pdf(path, app, log=lambda *_: None))  # twice: no
            self.assertFalse(f.add_pdf(path, app, supplier_name="Nobody", log=lambda *_: None))


if __name__ == "__main__":
    unittest.main()
