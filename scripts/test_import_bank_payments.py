"""Tests for import_bank_payments.py (no bank or app needed):

    python -m unittest scripts/test_import_bank_payments.py
"""
import collections
import datetime as dt
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import import_bank_payments as b  # noqa: E402

SUPPLIERS = [
    {"id": "o", "name": "Omnia", "account_no": "32777530", "bank_account_holder": "Omnia Fertilizer"},
    {"id": "e1", "name": "Eskom - 8441635490", "account_no": "8441635490", "bank_account_holder": "Eskom"},
    {"id": "e2", "name": "Eskom - 5851646746", "account_no": "5851646746", "bank_account_holder": "Eskom"},
    {"id": "n", "name": "Noord Tranvaal Boere", "account_no": "C012", "bank_account_holder": "NTB"},
    {"id": "v", "name": "VKB", "account_no": "L0471927", "bank_account_holder": "VKB"},
    {"id": "k", "name": "Kanaan Vervoer", "account_no": "302", "bank_account_holder": "Kanaan Vervoer"},
    {"id": "ov", "name": "Oorvloed Vervoer", "account_no": "302", "bank_account_holder": "Oorvloed Vervoer"},
]

CSV = """Date,Description,Amount,Balance
20260601,MONTHLY ACC FEE  ,-165.00,1000.00
20260603,DIGITAL PAYMENT DT            (     10.00 ) ABSA BANK Eskom 8441635490 ,-1234.56,900.00
20260603,PROOF OF PMT EMAIL            (      1.25 )  ,0.00,900.00
20260608,DIGITAL PAYMENT DT            (     10.00 ) ABSA BANK Oorvloed vervoer ,-2500.00,800.00
20260626,DIGITAL PAYMENT DT            (     10.00 ) ABSA BANK Eskom 58516467468 ,-345.67,700.00
20260703,DIGITAL PAYMENT DT            (     10.00 ) ABSA BANK VKB Januarie ,-987.65,600.00
20260713,DIGITAL PAYMENT DT            (     10.00 ) ABSA BANK NTB ,-5000.00,500.00
20260720,DIGITAL PAYMENT DT            (     10.00 ) ABSA BANK Eskom ,-999.00,450.00
20260801,DIGITAL PAYMENT DT            (     10.00 ) ABSA BANK Wage 73 ,-100.00,400.00
20260802,ACB CREDIT CASHFOCUS VKB PROD UITBETALING ,10.00,410.00
20260926,POS PURCHASE                  (      4.60 ) (EFFEC 25092026) NOORD TRANSVAAL BOE F/ SWART CARD NO.  0702,-50.00,950.00
20260929,DIGITAL PAYMENT DT            (     10.00 ) ABSA BANK Omnia ,-4321.09,300.00
"""


class FakeApp:
    def __init__(self, existing=()):
        self.added = []
        self.have = collections.Counter(existing)

    def suppliers(self):
        return SUPPLIERS

    def existing(self):
        return collections.Counter(self.have)

    invoices = {}  # (supplier id, amount): invoice date

    def invoice_for(self, supplier, day, amount):
        d = self.invoices.get((supplier["id"], amount))
        return d is not None and abs((d - day).days) <= 7

    def add(self, supplier, day, amount, payee):
        self.added.append((supplier["id"], day.isoformat(), amount, payee))
        self.have[(supplier["id"], day.isoformat(), amount)] += 1


class BankPayments(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.csv = pathlib.Path(self.dir.name) / "transactionHistory.csv"
        self.csv.write_text(CSV, encoding="utf-8")

    def tearDown(self):
        self.dir.cleanup()

    def test_matching(self):
        self.assertEqual(b.match_payee("Eskom 58516467468", SUPPLIERS)[0]["id"], "e2")  # a typo'd number still fits
        self.assertEqual(b.match_payee("VKB Augustus 2026", SUPPLIERS)[0]["id"], "v")
        self.assertEqual(b.match_payee("NTB", SUPPLIERS)[0]["id"], "n")
        self.assertEqual(b.match_payee("Oorvloed vervoer", SUPPLIERS)[0]["id"], "ov")
        s, cands = b.match_payee("Eskom", SUPPLIERS)
        self.assertIsNone(s)
        self.assertEqual({c["id"] for c in cands}, {"e1", "e2"})
        self.assertEqual(b.match_payee("Wage 73", SUPPLIERS), (None, []))
        self.assertEqual(b.match_payee("Omniamax Trading", SUPPLIERS), (None, []))  # whole words only

    def test_run_adds_supplier_payments_once(self):
        app = FakeApp(existing=[("o", "2026-09-29", 4321.09)])  # typed in by hand already
        lines = []
        added, already, unsure, others = b.run([self.csv, self.csv], app, log=lines.append)  # the same CSV twice
        self.assertEqual([a[:3] for a in app.added], [
            ("e1", "2026-06-03", 1234.56),
            ("ov", "2026-06-08", 2500.00),
            ("e2", "2026-06-26", 345.67),
            ("v", "2026-07-03", 987.65),
            ("n", "2026-07-13", 5000.00),
        ])
        self.assertEqual((added, already, unsure, others), (5, 1, 1, 1))
        self.assertTrue(any("NOT ADDED" in l and '"Eskom"' in l for l in lines))
        # Again: nothing new.
        self.assertEqual(b.run([self.csv], app, log=lambda *_: None)[:2], (0, 6))

    def test_find_lists_matching_lines(self):
        with tempfile.TemporaryDirectory() as d:
            path = pathlib.Path(d) / "bank.csv"
            path.write_text(CSV)
            said = []
            self.assertEqual(b.find([path], "eskom", log=said.append), 3)
            self.assertIn("01 Jun 2026 to 29 Sep 2026", said[0])
            self.assertIn("ABSA BANK Eskom 8441635490", said[1])

    def test_the_same_payment_in_two_csvs_counts_once(self):
        with tempfile.TemporaryDirectory() as d:
            (pathlib.Path(d) / "absa.csv").write_text("Date,Description,Amount,Balance\n"
                                                      "20260417,DIGITAL PAYMENT DT (10.00) ABSA BANK Omnia ,-82475.20,931373.33\n")
            (pathlib.Path(d) / "from_statement.csv").write_text("Date,Description,Amount,Balance\n"
                                                                "20260417,DIGITAL PAYMENT DT ABSA BANK Omnia,-82475.20,931373.33\n")
            self.assertEqual(len(b.payments_in(sorted(pathlib.Path(d).glob("*.csv")))), 1)

    def test_a_card_purchase_pays_its_invoice(self):
        sups = SUPPLIERS + [{"id": "l", "name": "Laeveld Agrochem", "account_no": "NAN003", "bank_account_holder": None}]
        csv_text = ("Date,Description,Amount,Balance\n"
                    "20260821,POS PURCHASE (4.60) (EFFEC 19082026) LAEVELD AGROCHEM PITER POLOK CARD NO.  4258,-8434.00,100.00\n"
                    "20260822,POS PURCHASE (4.60) (EFFEC 20082026) LAEVELD AGROCHEM PITER POLOK CARD NO.  4258,-99.00,1.00\n")
        with tempfile.TemporaryDirectory() as d:
            path = pathlib.Path(d) / "bank.csv"
            path.write_text(csv_text)
            app = FakeApp()
            app.suppliers = lambda: sups
            app.invoices = {("l", 8434.0): dt.date(2026, 8, 19)}
            added, already, unsure, others = b.run([path], app, log=lambda *_: None)
        # The one with its invoice (19 Aug), on the day bought; not the R99 without one.
        self.assertEqual(app.added, [("l", "2026-08-19", 8434.0, "Card: LAEVELD AGROCHEM PITER POLOK")])

    def test_not_a_bank_csv(self):
        other = pathlib.Path(self.dir.name) / "other.csv"
        other.write_text("Name,Value\nx,1\n", encoding="utf-8")
        self.assertEqual(b.read_csv(other), [])
        self.assertEqual(b.read_csv(self.csv)[1][0], dt.date(2026, 6, 3))
        # The last day the statements cover (any transaction): what's due is as at it.
        self.assertEqual(b.last_bank_day([self.csv, other]), max(r[0] for r in b.read_csv(self.csv)))
        self.assertIsNone(b.last_bank_day([other]))


class MarketReceipts(unittest.TestCase):
    def test_each_payment_to_its_deposit(self):
        d = dt.date
        receipts = [
            (d(2026, 9, 30), "ACB CREDIT WENPRO MARKAGENT 92220", 14606.64),
            (d(2026, 10, 1), "ACB CREDIT DAPPER", 14606.64),
            (d(2026, 10, 2), "DEPOSIT", 500.00),
            (d(2026, 11, 30), "ACB CREDIT RSA", 149282.17),
        ]
        payments = [
            {"id": "w", "pay_date": "2026-09-30", "amount": 14606.64, "name": "Wenpro Markagente"},
            {"id": "x", "pay_date": "2026-09-30", "amount": 14606.64, "name": "Dapper Agencies"},
            {"id": "r", "pay_date": "2026-05-16", "amount": 149282.17, "name": "RSA Markagente"},
        ]
        found = {p["id"]: r[1] for p, r in b.match_receipts(receipts, payments)}
        # Same amount twice: each goes to the deposit naming its agent; RSA's is far too late.
        self.assertEqual(found, {"w": "ACB CREDIT WENPRO MARKAGENT 92220", "x": "ACB CREDIT DAPPER"})


class BuyerDeposits(unittest.TestCase):
    def test_deposits_naming_the_buyer(self):
        d = dt.date
        receipts = [
            (d(2026, 3, 26), "ACB CREDIT EFTBBM8VPBS2P012/PEPPADEW", 2934010.76),
            (d(2026, 4, 24), "ACB CREDIT PEPPADEW", 780002.87),
            (d(2026, 4, 24), "ACB CREDIT UNIVERSAL UNIVERSAL LEAF SA", 154830.48),
            (d(2026, 5, 1), "ACB CREDIT PEPPADEWS", 1.00),  # not the same name
        ]
        peppadew = {"id": "p", "name": "Peppadew", "bank_match": "Peppadew"}
        self.assertEqual([r[2] for _, r in b.buyer_deposits(receipts, [peppadew])], [2934010.76, 780002.87])
        self.assertEqual(b.buyer_deposits(receipts, []), [])


if __name__ == "__main__":
    unittest.main()
