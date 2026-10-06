"""Wenpro-family rows: counts with a space for thousands read by their arithmetic."""
import unittest

from import_sales_report import detect_and_parse

# CL de Villiers' account sale 56140552 (addresses left out).
CLDV = """CL DE VILLIERS MARKAGENTE (EDMS) BPK
Tax Invoice 56140552
Date: 2026/06/03
To: NANINI 121 BK (NANINI BOERDERY) (92220) Jhb. Fresh Produce Market
Date paid: 2026/06/03
Date received: 2026/05/29 Account Sale no: 56140552
Payment type: Final
Grn nr Product Sent Prev Discar Pay Price Gross Qty
Paid ds now unsold
15453783 BNUT PC070 4 350 861 0 3 489 34.70 121 063.00 0
Total: 4 350 861 0 3 489 34.70 121 063.00 0
VAT Output: 0.00
Deductions Rate Amount VAT
Market Commission 5.00% 6 053.15 908.05
Agent Commission 9.50% 11 501.01 1 725.16
Bank Charges 20.00 3.00
Total Deductions (Excluding VAT) 17 574.16 2 636.21
VAT on Deduction 2 636.21
Total Deductions (Including VAT) 20 210.37 -20 210.37
Nett Amount 100 852.63
"""


class WenfamCountsTest(unittest.TestCase):
    def test_thousands_with_a_space(self):
        r = detect_and_parse([CLDV])[0]
        self.assertEqual([(li["subcategory"], li["qty"], li["gross_amount"]) for li in r["line_items"]], [("7kg", 3489, 121063.0)])

    def test_size_and_class_in_the_descriptor(self):
        text = CLDV.replace("BNUT PC070 4 350 861 0 3 489 34.70 121 063.00 0", "BNUT PC070 CL 1 M 189 0 0 189 35.93 6 790.00 0").replace(
            "Total: 4 350 861 0 3 489 34.70 121 063.00 0", "Total: 189 0 0 189 35.93 6 790.00 0")
        r = detect_and_parse([text])[0]
        self.assertEqual([(li["qty"], li["gross_amount"]) for li in r["line_items"]], [(189, 6790.0)])

    def test_pumpkins_and_watermelons(self):
        text = CLDV.replace("CL DE VILLIERS MARKAGENTE", "DAPPER AGENCIES").replace(
            "15453783 BNUT PC070 4 350 861 0 3 489 34.70 121 063.00 0", "14330728 PKS DC EA040 M 408 0 0 395 80.00 31 600.00 13").replace(
            "Total: 4 350 861 0 3 489 34.70 121 063.00 0", "Total: 408 0 0 395 80.00 31 600.00 13")
        r = detect_and_parse([text])[0]
        self.assertEqual((r["category"], [(li["subcategory"], li["qty"], li["gross_amount"]) for li in r["line_items"]]),
                         ("pumpkin", [("Medium", 395, 31600.0)]))
        r = detect_and_parse([text.replace("PKS DC EA040 M", "MELW EA060 L")])[0]
        self.assertEqual((r["category"], r["line_items"][0]["subcategory"]), ("watermelon", "Large"))


if __name__ == "__main__":
    unittest.main()
