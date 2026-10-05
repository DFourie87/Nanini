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


if __name__ == "__main__":
    unittest.main()
