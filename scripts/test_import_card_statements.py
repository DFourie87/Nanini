"""Tests for import_card_statements.py (no PDF or app needed; made-up figures):

    python -m unittest scripts/test_import_card_statements.py
"""
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import import_card_statements as c  # noqa: E402

# As pdfplumber reads ABSA's credit card statement (shortened, made-up amounts).
CREDIT = """Credit card statement for the period
10 Feb 2026 to 11 Mar 2026 (30 days)
Account number:4570-0000-0000-1234NANINI 121 CC Statement date: 11 Mar 2026
Calculation of balance
Description Amount R
Balance from last statement 2 000,00Cr
Transactions 3 000,00
Payments/Credits 1 000,50Cr
Interest 1,39Cr
Service fee 10,00
Balance on this statement 8,11
Account profile
Transactions
Tran Process
date date Reference Description Amount R
18 Feb 18 Feb 74565466049801174516137 ABSA BRANCHES - 008011 3 000,00
(Subtotal) 3 000,00
Payments/credits
14 Feb 14 Feb 74565466045808910120003 Nanini 121 CC 1 000,50Cr
"""

# As pdfplumber reads ABSA's fleet card statement (made-up amounts).
FLEET = """CONTRACTUAL CLIENT INVOICE
ABSA Fleet Card Services
FMS A/C NO : 708283 10 0000 1234 TEL NO : 0861 - 227232
STATEMENT NO : 8 CELL NO : 0861 227232
BALANCE BROUGHT FORWARD 100.00
2026/10/31 DEBIT ORDER PAYMENT 1,100.00-
2026/10/31 EXTERNAL PURCHASE 950.00
2026/10/31 CARD FEE 80.35
TOTAL OWING TO ABSA 30.35
DATE:2026/10/31 NANINI 121 CC PAGE: 1
"""


class CardStatementsTest(unittest.TestCase):
    def test_credit_card(self):
        s = c.parse_statement(CREDIT, "credit")
        self.assertEqual((s["account_no"], s["statement_date"], s["period_from"]), ("1234", "2026-03-11", "2026-02-10"))
        self.assertEqual((s["opening"], s["closing"]), (2000.0, -8.11))
        self.assertEqual([(x["line_date"], x["description"], x["amount"]) for x in s["lines"]], [
            ("2026-02-14", "Nanini 121 CC", 1000.5),
            ("2026-02-18", "ABSA BRANCHES - 008011", -3000.0),
            ("2026-03-11", "Interest", 1.39),
            ("2026-03-11", "Service fee", -10.0),
        ])
        self.assertAlmostEqual(s["opening"] + sum(x["amount"] for x in s["lines"]), s["closing"], places=2)

    def test_credit_card_year_end(self):
        text = CREDIT.replace("10 Feb 2026 to 11 Mar 2026", "10 Dec 2026 to 9 Jan 2027").replace("18 Feb 18 Feb", "18 Dec 18 Dec")
        s = c.parse_statement(text, "credit")
        self.assertEqual(s["lines"][1]["line_date"], "2026-12-18")

    def test_fleet_card(self):
        s = c.parse_statement(FLEET, "fleet")
        self.assertEqual((s["account_no"], s["statement_date"], s["statement_no"]), ("1234", "2026-10-31", 8))
        self.assertEqual((s["opening"], s["closing"]), (-100.0, -30.35))
        self.assertEqual([x["amount"] for x in s["lines"]], [1100.0, -950.0, -80.35])
        self.assertAlmostEqual(s["opening"] + sum(x["amount"] for x in s["lines"]), s["closing"], places=2)
        with self.assertRaises(c.NotAStatement):
            c.parse_statement("TAX INVOICE (VAT)\nFleet Card Services", "fleet")

    def test_files(self):
        with tempfile.TemporaryDirectory() as d:
            root = pathlib.Path(d)
            for p in ["2027/Bank/Credit card/CC_09112026.pdf", "2027/Bank/Fleet Card/30_10_2026 - Statement.pdf", "2027/Bank/Term Loan/x.pdf"]:
                (root / p).parent.mkdir(parents=True, exist_ok=True)
                (root / p).write_bytes(b"%PDF")
            self.assertEqual([(c.card_of(f), f.name) for f in c.statement_files(root)],
                             [("credit", "CC_09112026.pdf"), ("fleet", "30_10_2026 - Statement.pdf")])


if __name__ == "__main__":
    unittest.main()
