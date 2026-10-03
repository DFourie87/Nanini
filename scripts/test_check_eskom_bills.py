"""Tests for check_eskom_bills.py (no app needed):

    python -m unittest scripts/test_check_eskom_bills.py
"""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import check_eskom_bills as c  # noqa: E402


def bill(date, amount, charges, bf, paid):
    return {"doc_date": date, "reference": date, "amount": amount, "purchases_amount": charges, "brought_forward": bf,
            "payments_received": [{"date": d, "amount": a} for d, a in paid]}


class Check(unittest.TestCase):
    def test_ties_up_and_flags(self):
        bank = [{"id": "p1", "pay_date": "2026-08-07", "amount": 1000}, {"id": "p2", "pay_date": "2026-09-10", "amount": 1150},
                {"id": "p3", "pay_date": "2026-10-05", "amount": 900}]
        good = [bill("2026-07-25", 1000, 1000, 900, [("2026-07-10", 900)]),
                bill("2026-08-25", 1150, 1150, 1000, [("2026-08-08", 1000)]),
                bill("2026-09-25", 900, 900, 1150, [("2026-09-10", 1150)])]
        log = []
        # The July bill's payment (900 on 10 Jul) isn't in this bank list: flagged.
        self.assertEqual(c.check_account("Eskom - 1", good, bank, log=log.append), 1)
        self.assertIn("NOT in the bank payments", log[1])
        self.assertTrue(log[3].endswith("OK") and log[4].endswith("OK"))
        # Before the bank payments in the app start: not a problem.
        self.assertEqual(c.check_account("Eskom - 1", good, bank, log=lambda *_: None, bank_from="2026-08-01"), 0)
        self.assertIn("paid since the last bill: R900.00 on 2026-10-05", log[-1])
        # A wrong brought forward and sums that don't add up.
        bad = [bill("2026-07-25", 1000, 1000, 900, []), bill("2026-08-25", 1200, 1150, 1050, [("2026-08-08", 1000)])]
        log = []
        self.assertEqual(c.check_account("Eskom - 1", bad, bank, log=log.append), 2)
        text = "\n".join(log)
        self.assertIn("brought forward R1,050.00 but the previous bill (2026-07-25) was R1,000.00", text)
        self.assertIn("the bill says R1,000.00", text)
        # A credit.
        log = []
        c.check_account("Eskom - 2", [bill("2026-06-01", -58709.12, -58709.03, 32806.10, [("2026-05-29", 32806.19)])],
                        [{"id": "x", "pay_date": "2026-05-29", "amount": 32806.19}], log=log.append)
        self.assertIn("due R58,709.12 in credit  OK", log[1])


if __name__ == "__main__":
    unittest.main()
