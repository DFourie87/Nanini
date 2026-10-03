"""Tests for check_supplier_statements.py (no app needed):

    python -m unittest scripts/test_check_supplier_statements.py
"""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import check_supplier_statements as c  # noqa: E402


class Check(unittest.TestCase):
    def test_month_by_month(self):
        st = [{"doc_date": "2026-07-31", "amount": 16936.54, "kind": "statement"},
              {"doc_date": "2026-08-31", "amount": 29873.45, "kind": "statement"}]
        docs = st + [
            {"doc_date": "2026-08-03", "kind": "invoice", "amount": 12570.95, "status": "confirmed"},
            {"doc_date": "2026-08-06", "kind": "invoice", "amount": 1267.05, "cash_sale": True},  # paid at the till
            {"doc_date": "2026-08-20", "kind": "credit_note", "amount": 0},
        ]
        log = []
        diffs = c.check(st, docs, [], log=log.append)
        # 16 936.54 + 12 570.95 = 29 507.49; the statement says 29 873.45: R365.96 interest and insurance.
        self.assertEqual(diffs, [("2026-08-31", 365.96)])
        self.assertIn("R365.96 more than ours", log[0])
        self.assertIn("1 cash sale(s) R1,267.05 paid at the till", log[2])
        # With a payment in between, all on the account: OK.
        diffs = c.check(st, docs, [{"pay_date": "2026-08-15", "amount": -365.96}], log=lambda *_: None)
        self.assertEqual(diffs, [("2026-08-31", 0.0)])


if __name__ == "__main__":
    unittest.main()
