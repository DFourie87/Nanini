"""Tests for import_term_loan.py (no PDF or app needed; made-up figures):

    python -m unittest scripts/test_import_term_loan.py
"""
import pathlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import import_term_loan as t  # noqa: E402

# As pdfplumber reads an ABSA term loan statement (shortened, made-up amounts).
TEXT = """Statement period: 17 Oct 2026 -17 Nov 2026
NANINI 121 CC
Statement date: 17 Nov 2026
Your Term loan statement
for account number 3053810190 | universal branch code 632 005
Overview Details of Agreement
Principal debt R5 000 000.00
Outstanding balance (incl. interest)
R187 908.66 Annual interest rate 12.65%
Total outstanding balance R187 908.66
Outstanding capital balance R5 050 000.00
12.65% Interest on capital balance R1 335 854.13
Instalment: Capital amount -50 000.00
01 Apr 2027 Interest Portion 50,000.00
Arrear/Advance 5 237 908.66
Amount Payable on01 Apr 2027 (including fees) 1 761 738.57
Interest benefit on prepaid amount 49,385.52
Your transactions
Balance B/F -3 056 228.67
2026/10/20 Transfer debit -100 000.00 5 187 908.66 -3 156 228.67
2026/11/01 Instalment due 50 000.00 5 237 908.66 -3 106 228.67
2026/11/05 Journal credit 1 250.00 5 239 158.66 -3 104 978.67
"""


class TermLoanTest(unittest.TestCase):
    def test_statement(self):
        s = t.parse_statement(TEXT)
        self.assertEqual((s["account_no"], s["statement_date"], s["period_from"], s["period_to"]), ("3053810190", "2026-11-17", "2026-10-17", "2026-11-17"))
        self.assertEqual((s["capital"], s["advance"], s["interest_rate"]), (5050000.0, 5237908.66, 12.65))
        self.assertEqual((s["amount_payable"], s["payable_date"]), (1761738.57, "2027-04-01"))
        self.assertEqual((s["interest_portion"], s["interest_benefit"]), (50000.0, 49385.52))
        self.assertEqual([(x["line_date"], x["description"], x["amount"]) for x in s["lines"]], [
            ("2026-10-20", "Transfer debit", -100000.0),
            ("2026-11-01", "Instalment due", 50000.0),
            ("2026-11-05", "Journal credit", 1250.0),
        ])

    def test_not_a_statement(self):
        with self.assertRaises(t.NotAStatement):
            t.parse_statement("TAX INVOICE\nAccount sale 12345")

    def test_files_in_term_loan_folders(self):
        with tempfile.TemporaryDirectory() as d:
            root = pathlib.Path(d)
            for p in ["2027/Bank/Term Loan/Term Loan 17112026.pdf", "2027/Bank/ABSA/statement.pdf", "2026/Bank/Term Loan/a.pdf"]:
                (root / p).parent.mkdir(parents=True, exist_ok=True)
                (root / p).write_bytes(b"%PDF")
            self.assertEqual([f.name for f in t.statement_files(root)], ["a.pdf", "Term Loan 17112026.pdf"])

    def test_transfers_from_the_bank(self):
        with tempfile.TemporaryDirectory() as d:
            (pathlib.Path(d) / "absa.csv").write_text(
                "Date,Description,Amount,Balance\n"
                "20260401,DIGITAL TRANSF DT 30-5381-0190 ABSA BANK Nanini Term Loan,-1000000.00,10.00\n"
                "20260605,DIGITAL TRANSF DT 30-5381-0190 ABSA BANK Nanini Term Loan,-500000.00,20.00\n"
                "20261020,DIGITAL TRANSF CR 30-5381-0190 ABSA BANK Nanini,100000.00,30.00\n"
                "20260804,ACB DEBIT:EXTERNAL F&I 804486804486019075,-7679.72,40.00\n")
            (pathlib.Path(d) / "copy.csv").write_text(
                "Date,Description,Amount,Balance\n20260605,DIGITAL TRANSF DT 30-5381-0190 ABSA BANK Nanini Term Loan,-500000.00,20.00\n")
            got = t.bank_transfers(d)
        self.assertEqual([(x[0], x[1]) for x in got], [("2026-04-01", 1000000.0), ("2026-06-05", 500000.0), ("2026-10-20", -100000.0)])
        statements = [{"id": "apr", "statement_date": "2026-04-17", "period_from": "2026-03-17", "period_to": "2026-04-17"},
                      {"id": "jun", "statement_date": "2026-06-17", "period_from": "2026-05-17", "period_to": "2026-06-17"},
                      {"id": "nov", "statement_date": "2026-11-17", "period_from": "2026-10-17", "period_to": "2026-11-17"}]
        lines = [{"line_date": "2026-06-05", "amount": 500000}, {"line_date": "2026-10-20", "amount": -100000}]
        todo = t.missing_transfers(got, statements, lines)
        self.assertEqual([(x["statement_id"], x["line_date"], x["amount"], x["manual"]) for x in todo], [("apr", "2026-04-01", 1000000.0, True)])
        self.assertTrue(todo[0]["description"].startswith("Paid into the loan from the ABSA current account"))


if __name__ == "__main__":
    unittest.main()
