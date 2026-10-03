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

    def test_not_a_bank_csv(self):
        other = pathlib.Path(self.dir.name) / "other.csv"
        other.write_text("Name,Value\nx,1\n", encoding="utf-8")
        self.assertEqual(b.read_csv(other), [])
        self.assertEqual(b.read_csv(self.csv)[1][0], dt.date(2026, 6, 3))
        # The last day the statements cover (any transaction): what's due is as at it.
        self.assertEqual(b.last_bank_day([self.csv, other]), max(r[0] for r in b.read_csv(self.csv)))
        self.assertIsNone(b.last_bank_day([other]))


if __name__ == "__main__":
    unittest.main()
