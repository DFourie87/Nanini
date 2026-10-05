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

    def test_delivery_note_a_date(self):
        text = """WENPRO MARKAGENTE (EDMS) BPK 2022/11/16
Opsomming van betalings gemaak op 2022/11/14 06:08:48
45321744 5633089 0590 2022/11/01 0 120 4 800.00 843.55 0.00 3 956.45
45404141 5639058 10/11/22 2022/11/10 0 3 300 187 712.00 24 199.42 0.00 163 512.58
45403501 5639807 11/11/22 2022/11/12 0 1 767 96 673.00 12 459.86 0.00 84 213.14
Totaal: 0 5 187 289 185.00 37 502.83 0.00 251 682.17
"""
        st = parse_statement([text])
        self.assertEqual(st["paid"], 251682.17)
        self.assertEqual([(s["delivery"], s["qty"]) for s in st["sales"]], [("0590", 120), ("10/11/22", 3300), ("11/11/22", 1767)])

    def test_dapper_delivery_note_a_date(self):
        st = parse_statement(["""DAPPER AGENCIES (PTY) LTD 2021/03/12
Opsomming van betalings gemaak op 2021/03/10 08:47:36
40128542 5289078 04/03/2021 2021/03/03 0 41 1 750.00 287.85 0.00 1 462.15
Totaal: 0 41 1 750.00 287.85 0.00 1 462.15
"""])
        self.assertEqual((st["agent"], st["paid"], st["sales"][0]["delivery"], st["sales"][0]["sales"]), ("Dapper Agencies", 1462.15, "04/03/2021", 1750.0))

    def test_must_add_up(self):
        with self.assertRaises(ParseError):
            parse_statement([WENPRO.replace("0.00 14 606.64", "0.00 14 606.65")])


# ULSA's invoice (page 1; the bank account line left out).
ULSA = """TAX INVOICE NO: ULSA006606
From Grower: 1193 To Universal Leaf South Africa Pty Ltd
Delivery Date: 7/29/2026 2:40:00 PM Delivery No: 1100002222 Date Of Sale: 7/29/2026 2:40:00 PM
Tobacco Purchases
Kilos Grade Units Price Excluding 15% VAT Total
120.00 F2F 2 76.47 9,176.40 1,376.46 10,552.86
3720.00 F2P 62 74.09 275,614.80 41,342.22 316,957.02
1380.00 F4P 23 51.03 70,421.40 10,563.21 80,984.61
1043.40 F6 17 28.99 30,248.17 4,537.22 34,785.39
Total: 6,263.40 104 385,460.77 57,819.11 443,279.88
Deductions
Total Deductions: -8,471.32 -1,270.70 -9,742.02
Settlement Statement / Bank Transfer:
Total Net Payment 433,537.85
"""


class UlsaSettlementTest(unittest.TestCase):
    def test_invoice_pays_itself(self):
        st = parse_statement([ULSA])
        self.assertEqual((st["agent"], st["date"], st["paid"]), ("Universal Leaf South Africa", "2026-07-29", 433537.85))
        self.assertEqual(st["sales"], [{
            "account_sale": "ULSA006606", "sales": 443279.88, "deductions": 9742.02, "nett": 433537.85, "qty": 6263.4,
        }])


if __name__ == "__main__":
    unittest.main()
