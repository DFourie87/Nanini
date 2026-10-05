"""Peppadew: a grading report per load (into Sales), the payment advice (onto its account)."""
import unittest

from import_sales_report import AgentDocument, detect_and_parse
from market_statements import parse_statement

GRADING = """PEPPADEW INTERNATIONAL (Pty) Ltd
GRADING REPORT - Accepted
SUPPLIER: FOURIE THYS (NANINI) PIQUANTE RECEIVING NUMBER: GRV-4996
Supplier Number: 30ZZ608 Delivery Note No: 52461
Fruit: Piquante Peppers Number of Bins: 24
Date Received: 2026/02/05 14:05:28 Released by: MARIANNE
Anthracnosis 0 g 0% 0kg Class 1 1628 g 78,05% 5 116,96kg
Calyx removed 33,8 g 1,62% 106,21kg Class 2 25,2 g 1,21% 79,33kg
Chemical spray 0 g 0% 0kg Class 4 0 g 0% 0kg
Total Value R90 522,50
Class 1 R89 546,77
Class 2 R975,73
Mealiebug 0 g 0% 0kg Class 3 R0,00
Mechanical damage 77,2 g 3,7% 242,57kg Class 4 R0,00
Total Rejected Fruit 432,6 g 20,73% 1 359,07kg
"""

ADVICE = """GROWER: 30ZZ608 NANINI FARMER PAYMENT ADVICE / TAX INVOICE PEPPADEW INTERNATIONAL PTY LTD
GRV-7135 55844 2026/04/17 07:50 12 2412.51 876.64 274 73% 27% 39% 31% 0% 3% R 3 5,318.44
GRV-7141 55845 2026/04/17 16:59 10 2423.03 532.98 296 82% 18% 39% 40% 0% 3% R 3 4,643.02
GRV-7217 41689 2026/04/29 07:15 10 0 0 0 0% 0% 27% 39% 0% 4% R -
TOTAL 22 4835.54 1409 0.57% 0.34% 0.34% 0.00% 0.04% R 69,961.46
BINS & SUGAR BAGS R 720.00
TOTAL DEDUCTIONS R 720.00
TOTAL R 69,241.46
NETT PAYMENT R 69,241.46
"""


class PeppadewTest(unittest.TestCase):
    def test_grading_report_into_sales(self):
        r = detect_and_parse([GRADING])[0]
        self.assertEqual((r["category"], r["agent"], r["report_number"], r["report_date"], r["nett_amount"]),
                         ("peppadew", "Peppadew", "GRV-4996", "2026-02-05", 90522.5))
        self.assertEqual([(li["subcategory"], li["class"], li["qty"], li["gross_amount"]) for li in r["line_items"]], [
            ("Red", "Class 1", 5116.96, 89546.77),
            ("Red", "Class 2", 79.33, 975.73),
            ("Red", "Rejected", 1359.07, 0.0),
        ])

    def test_yellow_by_supplier_number(self):
        r = detect_and_parse([GRADING.replace("30ZZ608", "30ZZ718")])[0]
        self.assertEqual({li["subcategory"] for li in r["line_items"]}, {"Yellow"})

    def test_advice_is_not_a_sale_but_a_payment(self):
        with self.assertRaises(AgentDocument):
            detect_and_parse([ADVICE])
        st = parse_statement([ADVICE], "2026-05-22 marianne.fourie@peppadew.com 30ZZ608.pdf")
        self.assertEqual((st["agent"], st["date"], st["paid"]), ("Peppadew", "2026-05-22", 69241.46))
        # GRV-7217 not valued yet: paid on a later advice.
        self.assertEqual([(s["account_sale"], s["nett"]) for s in st["sales"]], [("GRV-7135", 35318.44), ("GRV-7141", 34643.02)])


    def test_advice_with_dates_as_dd_mm_yyyy(self):
        st = parse_statement(["""GROWER: 30ZZ608 NANINI FARMER PAYMENT ADVICE / TAX INVOICE PEPPADEW INTERNATIONAL PTY LTD
GRV-5491 52474 17-02-2026 09:10 24 5186.79 1536.87 280 77% 23% 76% 2% 0% 0% R 90 199.06
GRV-5516 52475 17-02-2026 15:43 24 5152.47 1608.87 282 76% 24% 76% 0% 0% 0% R 89 836.75
TOTAL 48 10339.26 3145 0.84% 0.81% 0.03% 0.00% 0.00% R 180 035.81
TOTAL DEDUCTIONS R 4 480.00
NETT PAYMENT R 175 555.81
"""], "2026-03-27 marianne.fourie@peppadew.com 30ZZ608.pdf")
        self.assertEqual((st["date"], st["paid"]), ("2026-03-27", 175555.81))
        self.assertEqual([(s["account_sale"], s["received"], s["nett"]) for s in st["sales"]],
                         [("GRV-5491", "2026-02-17", 90199.06), ("GRV-5516", "2026-02-17", 89836.75)])


    def test_first_advices_dates_with_slashes_no_rejected_weight(self):
        st = parse_statement(["""GROWER: 30ZZ608 NANINI FARMER PAYMENT ADVICE / TAX INVOICE PEPPADEW INTERNATIONAL PTY LTD
GRV-4718 52459 29/01/2026 08:34 24 6556 273 78% 72% 6% 0% 0% R 86,842.62
GRV-4996 52461 05/02/2026 14:05 24 6556 273 79% 78% 1% 0% 0% R 90,522.50
TOTAL 48 13112 546 0.75% 0.72% 0.03% 0.00% 0.00% R 177,365.12
SEEDLINGS - 69501100 R 77,365.12
TOTAL DEDUCTIONS R 77,365.12
NETT PAYMENT R 100,000.00
"""], "2026-03-03 marianne.fourie@peppadew.com 30ZZ608.pdf")
        self.assertEqual(st["paid"], 100000.0)
        self.assertEqual([(s["account_sale"], s["received"], s["nett"]) for s in st["sales"]],
                         [("GRV-4718", "2026-01-29", 86842.62), ("GRV-4996", "2026-02-05", 90522.5)])


if __name__ == "__main__":
    unittest.main()
