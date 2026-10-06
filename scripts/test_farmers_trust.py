"""Farmers Trust (BT1, Tshwane market): RSA's Technofresh layout without RSA's name."""
import unittest

from import_sales_report import detect_and_parse, technofresh_agent
from market_statements import parse_statement
from test_market_statements import RSA

# Account sale 351351 (two products of seven; address left out).
BT1 = """AGENT VAT REGISTRATION NUMBER: 4250103472
TAX INVOICE
BT351351 ACCOUNT SALES NO : 351351
PRODUCER : 052228 NANINI BOERDERY DATE : 07/11/2025 Page: 1
DELIVERY NOTE NO : 319095
DATE RECEIVED : 05/11/2025
MARKET GRN : 31909501 QUANTITY RECEIVED : 1430 QUANTITY B/F : 1430
PRODUCT : POWK 1L PP100 T2 POTATO MONDIAL (WASHED) SMAN : STIAN/MIKE
DATE PRICES AVER.PRICE MARKET AVG QUANTITY VALUE
---- ------ ---------- ---------- -------- --------
05/11/2025 65.00 - 65.00 65.00 53.59 1 65.00
06/11/2025 50.00 - 60.00 55.69 53.52 1429 79585.00
---------- -------- --------
55.70 1430 79650.00
QUANTITY OUTSTANDING : 0 AGENT COMM % : 6.00
-----------------------------------------------------------------------------
MARKET GRN : 31909507 QUANTITY RECEIVED : 110 QUANTITY B/F : 110
PRODUCT : POWK 2L PP100 T2 POTATO MONDIAL (WASHED) SMAN : STIAN/MIKE
DATE PRICES AVER.PRICE MARKET AVG QUANTITY VALUE
---- ------ ---------- ---------- -------- --------
06/11/2025 40.00 - 40.00 40.00 45.86 110 4420.00
---------- -------- --------
40.18 110 4420.00
QUANTITY OUTSTANDING : 0 AGENT COMM % : 6.00
-----------------------------------------------------------------------------
** PART PAYMENT ** ** TOTAL SOLD ** 1540
MARKET FEES 4203.50 630.53 4834.03 GROSS AMOUNT 84070.00
PROCON LEVY 247.10 37.07 284.17 LESS COST 10917.20
AGENT COMMISSION 5044.20 756.63 5800.83
---------- ---------- -------- SUB TOTAL 73152.80
9494.80 1424.23 10919.03
BANK CHARGES 11.57 1.74 13.31 BANK CHARGES 13.31
---------- ---------- --------
9506.37 1425.97 10932.34 -----------
---------- ---------- -------- NETT AMOUNT 73137.66
"""


class FarmersTrustTest(unittest.TestCase):
    def test_account_sale(self):
        r = detect_and_parse([BT1])[0]
        self.assertEqual((r["agent"], r["report_number"], r["report_date"], r["nett_amount"]), ("Farmers Trust", "351351", "2025-11-07", 73137.66))
        self.assertEqual(sorted((li["subcategory"], li["class"], li["qty"], li["gross_amount"]) for li in r["line_items"]),
                         [("Large", "Class 1", 1430, 79650.0), ("Large", "Class 2", 110, 4420.0)])

    def test_who_by_vat_number_or_file_name(self):
        self.assertEqual(technofresh_agent(BT1), "Farmers Trust")
        self.assertEqual(technofresh_agent("AGENT VAT REGISTRATION NUMBER: 4660115843"), "RSA Markagente Pretoria")
        self.assertEqual(parse_statement([RSA], "12683_ACCCHEQS_PRE.BT1_20251107_052228-351351.pdf")["agent"], "Farmers Trust")
        self.assertEqual(parse_statement([RSA], "12683_ACCCHEQS_PRE.RSA_20240516.pdf")["agent"], "RSA Markagente Pretoria")


if __name__ == "__main__":
    unittest.main()
