"""python -m unittest test_check_multi_account_sales.py (from scripts)"""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from check_multi_account_sales import NAME_RE, sale_numbers, verdict  # noqa: E402
from test_botha_roodt_freshmark import ACCOUNT_SALE  # noqa: E402


class CheckMultiAccountSalesTest(unittest.TestCase):
    def test_the_sales_in_a_file_not_the_previous_one(self):
        self.assertEqual(sale_numbers(ACCOUNT_SALE), ["15060"])
        self.assertEqual(sale_numbers(ACCOUNT_SALE + ACCOUNT_SALE.replace("15060", "15061")), ["15060", "15061"])

    def test_ok_missing_or_wrong(self):
        r = {"gross_total": 204454.0}
        self.assertEqual(verdict(r, None, 0), "MISSING")
        self.assertEqual(verdict(r, {"gross_total": 204454.0}, 204454.0), "OK")
        # Saved as one: the first's gross with every sale's products.
        self.assertEqual(verdict(r, {"gross_total": 204454.0}, 637671.0), "WRONG")
        self.assertEqual(verdict(r, {"gross_total": 637671.0}, 637671.0), "WRONG")

    def test_names_of_account_sales(self):
        for name in ["12683_ACCSALES_PRE.RSA_123.pdf", "Account-Sales_092220_02-11-2026_x.pdf", "1_PRE.BT1_2.pdf"]:
            self.assertTrue(NAME_RE.search(name), name)
        self.assertFalse(NAME_RE.search("092220_001_1_STOCK_EMAIL.pdf"))


if __name__ == "__main__":
    unittest.main()
