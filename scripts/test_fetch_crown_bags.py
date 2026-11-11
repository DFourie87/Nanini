"""Crown Bag: the potato bags on its tax invoices, for Packaging > Bags/Boxes."""
import unittest

import datetime as dt

from fetch_crown_bags import gmail_query, is_invoice, not_there_yet, read_invoice, rows_for, why_skipped

# As pdfplumber reads Crown Bag's invoice (the item codes run into the text).
INVOICE = """Sales - Tax Invoice
Invoice No. PSI32077
Page 1
25. February 2026
Bill-to Customer: Crown Bag (Pty) Ltd
E-mail admin@crownbag.co.za
Ship-to Customer: Banking Details:
NANINI BOERDERY Bank Absa Bank
No. Description Posted QuantityUnit of Unit PriceDisc. Amount
POTATO- 10kg NANINI - 1 LARGE 25/02/26 35 000Bags 2,59 90 650,00
1P0O-WTAHT0O0-1 10kg NANINI - 1 L/MED 25/02/26 35 000Bags 2,59 90 650,00
10-WH001
POTATO- 10kg NANINI - 1 SMALL 25/02/26 8 000Bags 2,59 20 720,00
1P0O-WTAHT0O0-17-7KG NANINI - 1 MED 25/02/26 17 000Bags 2,44 41 480,00
WH001
POTATO-7-7KG NANINI - 1 S/MED 25/02/26 12 000Bags 2,44 29 280,00
WLEHV0Y0110KGPotato SA Levy - 10KG Bags 25/02/26 78 000Bags 0,2529 19 726,20
LEVY7KG Potato SA Levy - 7KG Bags 25/02/26 29 000Bags 0,17703 5 133,87
TRANS 3rd Party Transport 25/02/26 107 000Bags 0,08 8 560,00
PALLET- PAPER PALETTE 25/02/26 9Each
Total R Excl. VAT 306 200,07
See www.vkb.co.za for Conditions of Sale / Sien www.vkb.co.za vir Verkoopsvoorwaardes
"""


# PSI33313 (Sep 2026): "NANINI BDY - 1 LARGE", and 7kg bags with no grade and a colour.
INVOICE_SEP = """Sales - Tax Invoice
Invoice No. PSI33313
10. September 2026
Bill-to Customer: Crown Bag (Pty) Ltd
E-mail admin@crownbag.co.za
No. Description Posted QuantityUnit of Unit PriceDisc. Amount
POTATO- 10KG NANINI BDY - 1 LARGE 10/09/26 23 700Bags 2,53 59 961,00
1P0O-WTAHT0O0-1 10KG NANINI BDY - 1 L/MED 10/09/26 16 900Bags 2,53 42 757,00
10-WH001
POTATO- 10KG NANINI BDY - 1 SMALL 10/09/26 10 500Bags 2,53 26 565,00
1P0S-TWDH1000R1D10KG BROWN FLAT - C/BAG POTATOES - RED 10/09/26 4 000Bags 2,38 9 520,00
3BFPOT00
POTATO-7 7KG NANINI - MED - GREEN 10/09/26 10 400Bags 2,38 24 752,00
-PWOHT0A0T1O-7 7KG NANINI - S/MED - PERS 10/09/26 5 200Bags 2,38 12 376,00
-WH001
LEVY10KGPotato SA Levy - 10KG Bags 10/09/26 55 100Bags 0,2609 14 375,59
LEVY7KG Potato SA Levy - 7KG Bags 10/09/26 15 600Bags 0,18263 2 849,03
TRANS 3rd Party Transport 10/09/26 70 700Bags 0,12 8 484,00
Total R Excl. VAT 201 639,62
"""


class CrownBagTest(unittest.TestCase):
    def test_the_bags_on_an_invoice(self):
        number, kind, lines = read_invoice(INVOICE)
        self.assertEqual((number, kind), ("PSI32077", "tax"))
        self.assertEqual([(l["item"], l["qty"]) for l in lines],
                         [("large10", 35000), ("largemed10", 35000), ("small10", 8000), ("med7", 17000), ("smallmed7", 12000)])
        self.assertEqual({l["date"] for l in lines}, {"2026-02-25"})

    def test_each_line_once(self):
        number, _, lines = read_invoice(INVOICE)
        rows = rows_for(number, lines, "x")
        self.assertEqual([r["source_key"] for r in rows][:2], ["crownbag:PSI32077:large10:35000", "crownbag:PSI32077:largemed10:35000"])
        self.assertEqual(sum(r["qty"] for r in rows), 107000)  # as the transport line
        self.assertTrue(all(r["produce"] == "potato" for r in rows))

    def test_baby_uses_the_small_bag_and_every_second_grade_the_brown_bag(self):
        text = INVOICE.replace("1 LARGE", "1 BABY").replace("1 L/MED", "2 L/MED").replace("1 SMALL", "2 LARGE")
        _, _, lines = read_invoice(text)
        self.assertEqual([l["item"] for l in lines][:3], ["small10", "brown10", "brown10"])
        _, _, lines = read_invoice(INVOICE.replace("1 LARGE", "3 MED"))
        self.assertEqual(lines[0]["item"], "brown10")  # 3rd grade: the brown bag too

    def test_a_brown_generic_bag(self):
        text = INVOICE.replace("POTATO- 10kg NANINI - 1 SMALL 25/02/26 8 000Bags", "BROWN10 10kg BROWN POTATO BAG 25/02/26 5 000Bags")
        _, _, lines = read_invoice(text)
        brown = [l for l in lines if l["item"] == "brown10"]
        self.assertEqual([(l["qty"], l["date"]) for l in brown], [(5000, "2026-02-25")])
        self.assertIn("BROWN", brown[0]["description"])
        # The levy and transport lines are never bags, brown or not.
        self.assertEqual(len(lines), 5)

    def test_a_credit_note_takes_bags_off(self):
        text = INVOICE.replace("Sales - Tax Invoice", "Sales - Credit Memo").replace("Invoice No. PSI32077", "Credit Memo No. PSCR1234")
        number, kind, lines = read_invoice(text)
        self.assertEqual((number, kind), ("PSCR1234", "credit"))
        self.assertEqual(lines[0]["qty"], -35000)

    def test_not_an_invoice(self):
        self.assertIsNone(is_invoice(INVOICE.replace("Sales - Tax Invoice", "Sales Quote")))
        self.assertIsNone(is_invoice(INVOICE.replace("Crown Bag (Pty) Ltd", "Someone else").replace("crownbag", "else")))
        self.assertIsNone(read_invoice("Crown Bag Statement of account PSI32077 352 130,08"))

    def test_an_unknown_bag_is_reported_not_added(self):
        _, _, lines = read_invoice(INVOICE.replace("7KG NANINI - 1 MED", "7KG NANINI - 2 MED"))
        self.assertIsNone(lines[3]["item"])
        self.assertEqual(len(rows_for("PSI32077", lines, "x")), 4)


    def test_the_september_wording_bdy_and_no_grade(self):
        number, kind, lines = read_invoice(INVOICE_SEP)
        self.assertEqual(number, "PSI33313")
        self.assertEqual([(l["item"], l["qty"]) for l in lines],
                         [("large10", 23700), ("largemed10", 16900), ("small10", 10500), ("brown10", 4000), ("med7", 10400), ("smallmed7", 5200)])
        self.assertEqual(sum(l["qty"] for l in lines), 70700)  # as the transport line

    def test_the_10kg_medium_green_bag(self):
        _, _, lines = read_invoice(INVOICE_SEP.replace("10KG NANINI BDY - 1 SMALL", "10KG NANINI - MED - GREEN"))
        self.assertEqual(lines[2]["item"], "med10")

    def test_a_line_already_in_the_app_is_not_added_again(self):
        number, _, lines = read_invoice(INVOICE_SEP)
        rows = rows_for(number, lines, "x")
        # The first run read only the brown bags (numbered line 1 then).
        existing = [{"reference": "PSI33313", "item": "brown10", "qty": 4000, "purchase_date": "2026-09-10"}]
        new = not_there_yet(rows, existing)
        self.assertEqual([r["item"] for r in new], ["large10", "largemed10", "small10", "med7", "smallmed7"])
        self.assertEqual(not_there_yet(rows, existing + new), [])

    def test_why_a_pdf_was_left_out(self):
        self.assertEqual(why_skipped("Crown Bag (Pty) Ltd  Statement  Balance 352 130,08"), "a statement")
        self.assertEqual(why_skipped("Crown Bag Sales Quote SQ1234"), "a quote")
        no_bags = INVOICE.replace("NANINI", "OTHER").replace("Potato SA", "") + "Payment Terms Cash on delivery"
        self.assertEqual(why_skipped(no_bags), "an invoice with no NANINI or brown potato bags on it")
        self.assertEqual(why_skipped("Someone else's invoice"), "not from Crown Bag")

    def test_the_gmail_search_is_one_quoted_string(self):
        q = gmail_query(dt.date(2025, 2, 1))
        self.assertEqual(q, '"has:attachment filename:pdf after:2025/02/01 from:(crownbag.co.za OR annekevdm@vkb.co.za)"')


if __name__ == "__main__":
    unittest.main()
