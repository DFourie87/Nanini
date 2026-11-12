"""Grow Boland Agents (Cape Town market): Technofresh's account sale layout
(as RSA / Farmers Trust), told apart by the agent's VAT number."""
import unittest

import import_sales_report as m

# As pdfplumber reads account sale 103593 (shortened; a made-up email address).
SALE = """SUPPLIER : 012089 FROM : GROW BOLAND AGENTS
EMAIL ADD. : farmer@example.com ,,
NANINI BOERDERY RUN ON : 30/10/2026
AGENT VAT REGISTRATION NUMBER: 4490116417
TAX INVOICE
U103593 ACCOUNT SALES NO : 103593
PRODUCER : 012089 NANINI BOERDERY DATE : 30/10/2026 Page: 1
LEPHALALE DELIVERY NOTE NO : 770334
REFNO : 26107
PREVIOUS ACCOUNT SALES NO : 0
MARKET GRN : 77033401 QUANTITY RECEIVED : 1760 QUANTITY B/F : 1760
PRODUCT : POWW 1Z PP100 A1 POTATO (WASHED) OTHER SMAN : POTS FLIPPIE
DATE PRICES AVER.PRICE QUANTITY VALUE
26/10/2026 75.00 - 85.00 75.52 1760 132924.00
75.53 1760 132924.00
QUANTITY OUTSTANDING : 0 AGENT COMM % : 5.00
MARKET GRN : 77033402 QUANTITY RECEIVED : 1540 QUANTITY B/F : 1540
PRODUCT : POWW 1L PP100 A1 POTATO (WASHED) OTHER SMAN : POTS FLIPPIE
DATE PRICES AVER.PRICE QUANTITY VALUE
26/10/2026 90.00 - 95.00 90.56 117 10595.00
27/10/2026 85.00 - 90.00 86.49 1423 123070.00
86.80 1540 133665.00
QUANTITY OUTSTANDING : 0 AGENT COMM % : 5.00
MARKET GRN : 77033403 QUANTITY RECEIVED : 110 QUANTITY B/F : 110
PRODUCT : POWW 2L PP100 A1 POTATO (WASHED) OTHER SMAN : POTS FLIPPIE
DATE PRICES AVER.PRICE QUANTITY VALUE
26/10/2026 80.00 - 80.00 80.00 110 8800.00
80.00 110 8800.00
QUANTITY OUTSTANDING : 0 AGENT COMM % : 5.00
VAT (OUTPUT) COLLECTED 0.00
** FINAL PAYMENT ** ** TOTAL SOLD ** 3410
COSTS CURRENT SALES
DEDUCTION AMOUNT VAT (INPUT) TOTAL
MARKET FEES 13769.45 2065.43 15834.88 GROSS AMOUNT 275389.00
POTATO ADMINISTRATION 498.53 74.77 573.30 LESS COST 32243.06
AGENT COMMISSION 13769.45 2065.43 15834.88
—————————— —————————— ———————— SUB TOTAL 243145.94
28037.43 4205.63 32243.06
BANK CHARGES 9.65 1.45 11.10 BANK CHARGES 11.10
—————————— —————————— ———————— ———————————
28047.08 4207.08 32254.16 ———————————
—————————— —————————— ———————— NETT AMOUNT 243134.84
Dankie vir u ondersteuning
"""


class GrowBolandTest(unittest.TestCase):
    def test_account_sale(self):
        [r] = m.detect_and_parse([SALE])
        self.assertEqual((r["agent"], r["report_number"], r["report_date"]), ("Grow Boland Kaapstad", "103593", "2026-10-30"))
        self.assertEqual((r["gross_total"], r["commission_before_vat"], r["vat"], r["nett_amount"]), (275389.0, 28047.08, 4207.08, 243134.84))
        self.assertEqual(sorted((li["subcategory"], li["class"], li["qty"], li["gross_amount"]) for li in r["line_items"]),
                         [("Large", "Class 1", 1540, 133665.0), ("Large", "Class 2", 110, 8800.0), ("Large/Medium", "Class 1", 1760, 132924.0)])
        self.assertEqual([d["label"] for d in r["deductions"]], ["MARKET FEES", "POTATO ADMINISTRATION", "AGENT COMMISSION", "BANK CHARGES"])


if __name__ == "__main__":
    unittest.main()
