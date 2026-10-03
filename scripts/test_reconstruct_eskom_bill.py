"""Tests for reconstruct_eskom_bill.py (no app needed):

    python -m unittest scripts/test_reconstruct_eskom_bill.py
"""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import reconstruct_eskom_bill as r  # noqa: E402


class Reconstruct(unittest.TestCase):
    def test_works_back_the_missing_bill(self):
        prev = {"doc_date": "2026-04-21", "amount": 7584.81, "brought_forward": 8543.17,
                "bill_details": {"from": "2026-03-12", "to": "2026-04-13", "charges": []}}
        nxt = {"doc_date": "2026-06-19", "amount": 7734.47, "brought_forward": 9121.36,
               "payments_received": [{"date": "2026-06-16", "amount": 9121.36}],
               "bill_details": {"from": "2026-05-12", "to": "2026-06-10", "charges": [
                   {"description": "Service and Administration Charge", "kind": "fixed", "unit": "day", "rate": 26.65},
                   {"description": "Network Capacity Charge", "kind": "fixed", "unit": "day", "rate": 67.66},
                   {"description": "Network Demand Charge", "kind": "usage", "unit": "kWh", "rate": 0.6706},
                   {"description": "Ancillary Service Charge", "kind": "usage", "unit": "kWh", "rate": 0.0045},
                   {"description": "Energy Charge", "kind": "usage", "unit": "kWh", "rate": 2.429},
               ]}}
        payments = [{"pay_date": "2026-05-06", "amount": 7584.81}, {"pay_date": "2026-06-16", "amount": 9121.36}]
        row = r.reconstruct(prev, nxt, payments, "2026-05")
        self.assertEqual((row["amount"], row["purchases_amount"], row["vat_amount"], row["brought_forward"]), (9121.36, 9121.36, 1189.74, 7584.81))
        self.assertEqual(row["payments_received"], [{"date": "2026-05-06", "amount": 7584.81}])  # the June one is on the June bill
        d = row["bill_details"]
        self.assertEqual((d["days"], d["from"], d["to"], d["reading"]), (29, "2026-04-13", "2026-05-12", "reconstructed"))
        fixed = sum(c["amount"] for c in d["charges"] if c["kind"] == "fixed")
        usage = sum(c["amount"] for c in d["charges"] if c["kind"] == "usage")
        self.assertAlmostEqual(fixed, 29 * (26.65 + 67.66), places=2)
        self.assertAlmostEqual(fixed + usage, 7931.62, places=2)  # the charges excl. VAT exactly
        self.assertEqual(d["kwh"], round((7931.62 - fixed) / (0.6706 + 0.0045 + 2.429)))
        self.assertIn("RECONSTRUCTED", row["notes"])
        self.assertEqual((row["doc_date"], row["reference"]), ("2026-05-19", "RECONSTRUCTED-2026-05"))

    def test_needs_the_bills_read(self):
        with self.assertRaises(ValueError):
            r.reconstruct({"doc_date": "2026-04-21", "amount": 1}, {"doc_date": "2026-06-19", "amount": 1}, [], "2026-05")


if __name__ == "__main__":
    unittest.main()
