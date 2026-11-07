"""Each account sale's deductions line by line (for the Xero invoices), and
Green Network's pallets paid for as a minus deduction.

    python -m unittest scripts/test_sales_deductions.py
"""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from import_sales_report import PalletInvoice, _reports_by_category, detect_and_parse  # noqa: E402
from test_botha_roodt_freshmark import ACCOUNT_SALE  # noqa: E402
from test_farmers_trust import BT1  # noqa: E402
from test_green_network import INVOICE, PALLETS  # noqa: E402
from test_wenfam_counts import CLDV  # noqa: E402

# Universal Leaf's tobacco invoice, as pdfplumber reads it (addresses and bank left out).
ULSA = """TAX INVOICE NO: ULSA006667
To Universal Leaf South Africa Pty Ltd
Delivery Date: 9/1/2026 12:00:00 PM Delivery No: 1100002273 Date Of Sale: 9/1/2026 12:00:00 PM
Tobacco Purchases
Kilos Grade Units Price Excluding 15% VAT Total
480.00 F2F 8 76.47 36,705.60 5,505.84 42,211.44
1080.00 F2P 18 74.09 80,017.20 12,002.58 92,019.78
240.00 F2Z 4 78.40 18,816.00 2,822.40 21,638.40
2040.00 F4P 34 51.03 104,101.20 15,615.18 119,716.38
605.60 F6 10 28.99 17,556.34 2,633.45 20,189.80
Total: 4,445.60 74 257,196.34 38,579.45 295,775.80
Deductions
Charge Creditor Excluding 15% VAT Total
Packing Material Universal Leaf South Africa (Pty) Ltd -236.80 -35.52 -272.32
Packing Charges Universal Leaf South Africa (Pty) Ltd -4,723.67 -708.55 -5,432.22
Total Deductions: -4,960.47 -744.07 -5,704.54
Total Net Payment 290,071.26
"""


def rows(report):
    return [(d["label"], d["amount"], d["vat"]) for d in report["deductions"]]


class DeductionLinesTest(unittest.TestCase):
    def test_freshmark_botha_roodt(self):
        self.assertEqual(rows(detect_and_parse([ACCOUNT_SALE])[0]), [
            ("MARKET FEES", 10675.0, 1601.27),
            ("POTATO ADMINISTRATION", 504.09, 75.62),
            ("AGENT COMMISSION", 12810.0, 1921.52),
            ("BANK CHARGES", 12.53, 1.88),
        ])

    def test_farmers_trust_without_the_deduction_heading(self):
        self.assertEqual(rows(detect_and_parse([BT1])[0]), [
            ("MARKET FEES", 4203.5, 630.53),
            ("PROCON LEVY", 247.1, 37.07),
            ("AGENT COMMISSION", 5044.2, 756.63),
            ("BANK CHARGES", 11.57, 1.74),
        ])

    def test_wenpro_family_with_rates_and_thousands(self):
        self.assertEqual(rows(detect_and_parse([CLDV])[0]), [
            ("Market Commission", 6053.15, 908.05),
            ("Agent Commission", 11501.01, 1725.16),
            ("Bank Charges", 20.0, 3.0),
        ])

    def test_universal_leaf_tobacco(self):
        r = detect_and_parse([ULSA])[0]
        self.assertEqual((r["report_number"], r["vat_on_sales"], r["commission_before_vat"]), ("ULSA006667", 38579.45, 4960.47))
        self.assertEqual(rows(r), [("Packing Material", 236.8, 35.52), ("Packing Charges", 4723.67, 708.55)])

    def test_lines_that_dont_add_up_are_left_out(self):
        r = detect_and_parse([CLDV.replace("Bank Charges 20.00 3.00", "Bank Charges 25.00 3.00")])[0]
        self.assertEqual(r["deductions"], [])
        self.assertEqual(r["commission_before_vat"], 17574.16)  # the report itself as before

    def test_green_network_commission_and_its_pallets(self):
        r = detect_and_parse([INVOICE, PALLETS])[0]
        self.assertEqual(rows(r), [
            ("GN Commission @ 10%", 17820.0, 2673.0),
            ("Pallets paid for: 31 PALLET @ R65 INCL (IN160836)", -1752.17, -262.83),
        ])
        self.assertEqual(r["deductions"][1]["kind"], "pallets")

    def test_a_pallet_invoice_on_its_own_carries_its_pallets(self):
        with self.assertRaises(PalletInvoice) as e:
            detect_and_parse([PALLETS])
        (doc_no, date, row), = e.exception.pallets
        self.assertEqual((doc_no, date, row["amount"], row["vat"]), ("IN160836", "2026-10-22", -1752.17, -262.83))

    def test_shared_by_crop_like_the_commission(self):
        detail = {("peppers", "Red", "5kg", "5kg"): {"sold": 10, "value": 750.0},
                  ("butternut", "10kg", None, "10kg"): {"sold": 10, "value": 250.0}}
        deductions = [{"label": "Commission", "amount": 100.0, "vat": 15.0}, {"label": "Bank", "amount": 0.01, "vat": 0.0}]
        reports = _reports_by_category("Wenpro Markagente", "1", "2026-09-01", 1000.0, 100.01, 15.0, 884.99, detail,
                                       "boxes", deductions=deductions)
        by_cat = {r["category"]: rows(r) for r in reports}
        self.assertEqual(by_cat["butternut"], [("Commission", 25.0, 3.75), ("Bank", 0.0, 0.0)])
        self.assertEqual(by_cat["peppers"], [("Commission", 75.0, 11.25), ("Bank", 0.01, 0.0)])
        for r in reports:
            self.assertAlmostEqual(sum(d["amount"] for d in r["deductions"]), r["commission_before_vat"], places=2)


if __name__ == "__main__":
    unittest.main()
