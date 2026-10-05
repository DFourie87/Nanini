import unittest

from import_sales_report import ParseError
from market_statements import parse_statement

# RSA's afrekeningstaat as read from the Technofresh download (the bank
# account line left out).
RSA = """INTERACTION MARKET SERVICES TSHWANE (PTY) LTD
T/A RSA MARKET AGENTS AFREKENINGSTAAT
H/A RSA MARKAGENTE
ACCOUNT SALES
PAYMENT SUMMARY FOR PAYMENT DATED : 16/05/2024 8:45:43 AM
ACC/SL DELIV.NO SUPPL REFNO SALES DEDUCTS VALUE QTYPAID CHEQ/TFER
-------------------------------------------------------------------------------------
269579 186573 91212 175000.00 25717.83 149282.17 1273 Transfer
-------------------------------------------------------------------------------------
175000.00 25717.83 149282.17 1273
Page 1/1
"""


class RsaPaymentTest(unittest.TestCase):
    def test_one_sale(self):
        st = parse_statement([RSA])
        self.assertEqual((st["date"], st["paid"], st["method"]), ("2024-05-16", 149282.17, "transfer"))
        self.assertEqual(st["sales"], [
            {"account_sale": "269579", "delivery": "186573", "sales": 175000.0, "deductions": 25717.83, "nett": 149282.17, "qty": 1273},
        ])

    def test_several_sales(self):
        text = RSA.replace(
            "269579 186573 91212 175000.00 25717.83 149282.17 1273 Transfer\n",
            "269579 186573 91212 175000.00 25717.83 149282.17 1273 Transfer\n"
            "270276 186900 91212 1000.00 150.00 850.00 10 Transfer\n",
        ).replace("175000.00 25717.83 149282.17 1273\n", "176000.00 25867.83 150132.17 1283\n")
        st = parse_statement([text])
        self.assertEqual([s["account_sale"] for s in st["sales"]], ["269579", "270276"])
        self.assertEqual(st["paid"], 150132.17)

    def test_rows_must_add_up(self):
        with self.assertRaises(ParseError):
            parse_statement([RSA.replace("175000.00 25717.83 149282.17 1273\n", "175000.00 25717.83 149999.99 1273\n")])

    def test_not_a_statement(self):
        with self.assertRaises(ParseError):
            parse_statement(["WENPRO MARKAGENTE\nVerkope nr: 1"])


if __name__ == "__main__":
    unittest.main()
