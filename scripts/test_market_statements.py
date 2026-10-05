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


WENPRO = """WENPRO MARKAGENTE (EDMS) BPK 2026/10/02
Opsomming van betalings gemaak op 2026/09/30 06:24:46
NANINI 121 BK (NANINI BOERDERY) (92220)
Verkope Mark Aflewerings Datum Vernie Betaal Bruto Aftrekkings Lenings Netto Bedrag
nr verw nota ontvang tig nou
56797326 6408845 28586 2026/09/02 0 62 2 480.00 406.48 0.00 2 073.52
56843576 6412680 28587 2026/09/09 0 39 1 180.00 172.66 0.00 1 007.34
56885275 6416694 28588 2026/09/16 0 42 3 480.00 510.83 0.00 2 969.17
56981481 6423727 28589 2026/09/29 0 56 10 020.00 1 463.39 0.00 8 556.61
Totaal: 0 199 17 160.00 2 553.36 0.00 14 606.64
Bladsy 1 van 1
"""


class WenproPaymentTest(unittest.TestCase):
    def test_summary(self):
        st = parse_statement([WENPRO])
        self.assertEqual((st["agent"], st["date"], st["paid"]), ("Wenpro Markagente", "2026-09-30", 14606.64))
        self.assertEqual([s["account_sale"] for s in st["sales"]], ["56797326", "56843576", "56885275", "56981481"])
        self.assertEqual(st["sales"][3], {
            "account_sale": "56981481", "delivery": "28589", "received": "2026-09-29",
            "sales": 10020.0, "deductions": 1463.39, "loans": 0.0, "nett": 8556.61, "qty": 56,
        })

    def test_must_add_up(self):
        with self.assertRaises(ParseError):
            parse_statement([WENPRO.replace("0.00 14 606.64", "0.00 14 606.65")])


if __name__ == "__main__":
    unittest.main()
