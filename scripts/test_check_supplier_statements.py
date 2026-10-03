"""Tests for check_supplier_statements.py (no app needed):

    python -m unittest scripts/test_check_supplier_statements.py
"""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import check_supplier_statements as c  # noqa: E402


class Check(unittest.TestCase):
    def test_month_by_month(self):
        st = [{"doc_date": "2026-07-31", "amount": 16936.54, "kind": "statement"},
              {"doc_date": "2026-08-31", "amount": 29873.45, "kind": "statement"}]
        docs = st + [
            {"doc_date": "2026-08-03", "kind": "invoice", "amount": 12570.95, "status": "confirmed"},
            {"doc_date": "2026-08-06", "kind": "invoice", "amount": 1267.05, "cash_sale": True},  # paid at the till
            {"doc_date": "2026-08-20", "kind": "credit_note", "amount": 0},
        ]
        log = []
        diffs = c.check(st, docs, [], log=log.append)
        # 16 936.54 + 12 570.95 = 29 507.49; the statement says 29 873.45: R365.96 interest and insurance.
        self.assertEqual(diffs, [("2026-08-31", 365.96)])
        self.assertIn("R365.96 more than ours", log[0])
        self.assertIn("1 cash sale(s) R1,267.05 paid at the till", log[2])
        # With a payment in between, all on the account: OK.
        diffs = c.check(st, docs, [{"pay_date": "2026-08-15", "amount": -365.96}], log=lambda *_: None)
        self.assertEqual(diffs, [("2026-08-31", 0.0)])


class Detail(unittest.TestCase):
    def test_vkb_statement_invoice_by_invoice(self):
        text = """` 0699 STAAT VIR DIE PERIODE
`010826 HKAD BAL O/B MAANDREKENING MD 16 936.54 16 936.54
`030826 PBMO FT-153589 TOP LINK FORD S3630 170965 1.00 956.52 MD 143.48 1 370.04 18 306.58 S
` BUSH TOPLINK CAT 1/2 FS353 170965 3.00 78.27 MD 11.74 S
`060826 BKAH FT-143835 BOUT+MOER SKAAR M12X75/KG 010425 0.76 48.48 MD 7.27 1 610.67 19 917.25 S
`150826 HKAD JNL-5501 KREDIET OORPLASING 1 022.64- 1 022.64- 28 894.61
`310826 SKAD IJB-84787 RENTE - MAANDREK 275.22 MD 275.22 29 782.91
`310826 SKAD IJB-84814 KREDIETVERSEKERINGSPREMIE 90.54 MD 90.54 29 873.45
`KONTANTTRANSAKSIES
`060826 ERAH KT-452121 NY INLAS ML PASSTUK 40MM 3.00 28.59 4.29 1 267.05 1 267.05 S
"""
        lines = c.statement_lines(text)
        self.assertEqual([(k, d, a) for k, d, a, _ in lines], [
            ("PBMO153589", "2026-08-03", 1370.04), ("BKAH143835", "2026-08-06", 1610.67),
            ("JNL-5501", "2026-08-15", -1022.64), ("IJB-84787", "2026-08-31", 275.22), ("IJB-84814", "2026-08-31", 90.54)])
        app = [{"reference": "PBMO153589", "doc_date": "2026-08-03", "amount": 1370.04},
               {"reference": "PBAH160040", "doc_date": "2026-08-07", "amount": 704.04},
               {"reference": "PBMO 153589", "doc_date": "2026-08-03", "amount": 1370.04}]
        log = []
        self.assertEqual(c.compare(lines, app, log=log.append), 365.76)
        text = "\n".join(log)
        self.assertIn("BKAH143835 2026-08-06: R1,610.67 on the statement -- NOT in the app", text)
        self.assertIn("PBAH160040 2026-08-07: R704.04 in the app -- NOT on this statement (cash sale?)", text)
        self.assertIn("PBMO 153589 2026-08-03: R1,370.04 is in the app TWICE", text)
        self.assertIn("JNL-5501 2026-08-15: R-1,022.64 KREDIET OORPLASING 1 022.64- 1 022.64- 28 894.61 (not an invoice", text)
        self.assertIn("IJB-84787 2026-08-31: R275.22 RENTE - MAANDREK 275.22 MD 275.22 29 782.91 (VKB's own charge -- not in the app yet", text)

        # --add-charges: interest and credit insurance, each to its contra account, no VAT.
        docs = c.charge_docs(lines, "2026-08-31")
        self.assertEqual([(d["kind"], d["reference"], d["doc_date"], d["amount"], d["description"], d["lines"][0]["gl_account"],
                           d["lines"][0]["vat_amount"]) for d in docs], [
            ("invoice", "IJB-84787", "2026-08-31", 275.22, "RENTE - MAANDREK", "3680/000", 0.0),
            ("invoice", "IJB-84814", "2026-08-31", 90.54, "KREDIETVERSEKERINGSPREMIE", "3850/000", 0.0)])
        # A credit note on the statement: the VAT from its line.
        kn = c.statement_lines("`170626 BKAH KN-637539 AANSPORINGSKORT KONTANT (S) ID 153.27- 1 021.79- 1 021.79- 30 778.28 S")
        d = c.charge_docs(kn, "2026-06-30")[0]
        self.assertEqual((d["kind"], d["amount"], d["vat_amount"], d["description"], d["lines"][0]["excl_amount"], d["lines"][0]["gl_account"]),
                         ("credit_note", 1021.79, 153.27, "AANSPORINGSKORT KONTANT (S)", 868.52, "1954/000"))
        # Once in the app, they count as on the statement.
        app.append({"reference": "IJB-84787", "doc_date": "2026-08-31", "amount": 275.22})
        log.clear()
        self.assertEqual(c.compare(lines, app, log=log.append), 365.76)
        self.assertIn("IJB-84787 2026-08-31: R275.22 RENTE - MAANDREK 275.22 MD 275.22 29 782.91 (VKB's own charge -- in the app)", "\n".join(log))
        self.assertNotIn("IJB-84787 2026-08-31: R275.22 in the app -- NOT", "\n".join(log))


class Recreate(unittest.TestCase):
    def test_invoice_from_the_statement(self):
        text = """`010426 HKAD BAL O/B MAANDREKENING MD 4 328.73 4 328.73
`100426 PBMO FT-150584 DIREK ONDERDELE 170965 2.00 869.56 MD 130.43 1 680.00 8 992.59 S
` SHAREPOINT 7654 3HOLES 170965 3.00 495.66 MD 74.35 S
` BOUT+MOER SKAAR M12X65/KG 170965 1.00 95.65 MD 14.35 S
` BTW BETAAL 1.00 219.13 MD Z
`100426 PBAH FT-64094 LK`S GRID BRAAI BIG BOX S/ST 010384 1.00 923.21 MD 138.48 1 638.09 10 630.68 S
` CP PLANT BAG N5 150X125X300 010384 4.00 164.08 MD 24.61 S
` SUPA KILL ROTGIF 3KG 010384 1.00 387.71 MD N
` BTW BETAAL 1.00 163.09 MD Z
`140426 BKAH FT-112042 STEELCLADD 1L WHITE ALL IN O 010425 1.00 139.57 MD 20.94 1 744.57 12 375.25 S
` MAGN SUPER MAIZE MEAL 12.5KG 010425 6.00 627.06 MD N
` MAGN SUPER BUCKET +MAIZE MEA 010425 6.00 957.00 MD N
` BTW BETAAL 1.00 20.94 MD Z
`300426 SKAD IJB-17221 RENTE - MAANDREK 69.44 MD 69.44 50 068.17
"""
        invs = c.statement_invoices(text)
        self.assertEqual(sorted(invs), ["BKAH112042", "PBAH64094", "PBMO150584"])
        doc, why = c.invoice_from_statement(invs["PBAH64094"], "2026-04-30")
        self.assertIsNone(why)
        self.assertEqual((doc["reference"], doc["doc_date"], doc["amount"], doc["vat_amount"]), ("PBAH64094", "2026-04-10", 1638.09, 163.09))
        self.assertEqual([(l["description"], l["quantity"], l["excl_amount"], l["vat_amount"]) for l in doc["lines"]], [
            ("LK`S GRID BRAAI BIG BOX S/ST", 1.0, 923.21, 138.48),
            ("CP PLANT BAG N5 150X125X300", 4.0, 164.08, 24.61),
            ("SUPA KILL ROTGIF 3KG", 1.0, 387.71, 0.0)])
        self.assertIn("RECREATED from VKB's statement of 2026-04-30", doc["notes"])
        # The first item without VAT: the total and balance aren't taken for VAT.
        doc, why = c.invoice_from_statement(invs["BKAH112042"], "2026-04-30")
        self.assertIsNone(why)
        self.assertEqual(doc["vat_amount"], 20.94)
        # Lines that don't add up: not added.
        invs["PBMO150584"]["items"].pop()
        doc, why = c.invoice_from_statement(invs["PBMO150584"], "2026-04-30")
        self.assertIsNone(doc)
        self.assertIn("don't add up", why)


class Gaps(unittest.TestCase):
    def test_running_balance(self):
        text = """`010626 HKAD BAL O/B MAANDREKENING MD 11 504.37 11 504.37
`030626 PBMO FT-153589 TOP LINK FORD S3630 170965 1.00 956.52 MD 143.48 1 370.04 12 874.41 S
`170626 BKAH KN-637539 AANSPORINGSKORT KONTANT (S) ID 153.27- 1 021.79- 1 021.79- 11 851.77 S
`200626 HKAD KW-490000 KWITANSIE 1 000.00- MD 1 000.00-
`300626 SKAD IJB-48921 RENTE - MAANDREK 170.33 MD 170.33 11 022.10
"""
        # 12 874.41 - 1 021.79 = 11 852.62, the statement says 11 851.77: R0.85 not read.
        self.assertEqual(c.balance_gaps(text), [("KN-637539", "2026-06-17", -0.85)])


if __name__ == "__main__":
    unittest.main()
