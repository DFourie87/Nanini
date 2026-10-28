"""Green Network Fresh Produce: its supplier-invoice copy per load (into Sales).

    python -m unittest scripts/test_green_network.py
"""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from import_sales_report import AgentDocument, ParseError, detect_and_parse  # noqa: E402

# A page as pdfplumber reads it (address and bank lines left out).
INVOICE = """Copy Supp. Inv
Date 22/10/26
Page 1
Document No IN160835
Green Network Fresh Produce (Pty) Ltd.
Deliver to
Nanini Boerdery
Account Your Reference Tax Exempt Tax Reference Sales Code
NAN001 26107 N Exclusive
Code Description Quantity Unit Unit Price Disc% Tax Nett Price
POTC1LM10 Potato Class 1 Large Med 10kg 1,760 50.00 0.00% 88,000.00
POTC1L10 Potato Class 1 Large 10kg 1,540 55.00 0.00% 84,700.00
POTC2L10 Potato Class 2 Large 10kg 110 50.00 0.00% 5,500.00
0180410 GN Commission @ 10% 15.00% -17,820.00
LOADED ON FARM
R6.50 DEDUCTED FOR TRSP
Sub Total 160,380.00
Discount @ 0.00% 0.00
Amount Excl Tax 160,380.00
Received in good order
Tax -2,673.00
Signed___________________ Date__________________ Total 157,707.00
"""

PALLETS = """Copy Supp. Inv
Date 22/10/26
Document No IN160836
Green Network Fresh Produce (Pty) Ltd.
NAN001 26107-PAL N Exclusive
Code Description Quantity Unit Unit Price Disc% Tax Nett Price
0196100 31 PALLET @ R65 INCL 15.00% 1,752.17
Sub Total 1,752.17
Amount Excl Tax 1,752.17
Tax 262.83
Signed___________________ Date__________________ Total 2,015.00
"""


class GreenNetworkTest(unittest.TestCase):
    def test_a_load_into_sales(self):
        reports = detect_and_parse([INVOICE, PALLETS])
        self.assertEqual(len(reports), 1)  # the pallet invoice isn't a sale
        r = reports[0]
        self.assertEqual(
            (r["category"], r["agent"], r["report_number"], r["report_date"], r["gross_total"], r["commission_before_vat"], r["vat"], r["nett_amount"]),
            ("potatoes", "Grow Green Network", "IN160835", "2026-10-22", 178200.0, 17820.0, 2673.0, 157707.0),
        )
        lines = {(li["subcategory"], li["class"]): (li["qty"], li["gross_amount"]) for li in r["line_items"]}
        self.assertEqual(lines, {
            ("Large/Medium", "Class 1"): (1760, 88000.0),
            ("Large", "Class 1"): (1540, 84700.0),
            ("Large", "Class 2"): (110, 5500.0),
        })

    def test_only_the_pallet_invoice_is_not_a_sale(self):
        with self.assertRaises(AgentDocument):
            detect_and_parse([PALLETS])

    def test_an_unknown_product_is_named_not_guessed(self):
        with self.assertRaises(ParseError) as e:
            detect_and_parse([INVOICE.replace("POTC2L10 Potato", "BNUT07 Butternut")])
        self.assertIn("BNUT07", str(e.exception))

    def test_totals_that_dont_add_up_are_not_imported(self):
        with self.assertRaises(ParseError):
            detect_and_parse([INVOICE.replace("Total 157,707.00", "Total 157,000.00")])


if __name__ == "__main__":
    unittest.main()
