import pathlib
import unittest
from unittest import mock

import import_market_payments as imp
from test_market_statements import RSA, WENPRO


class FakeApp(imp.App):
    def __init__(self, there=()):
        self.dry_run = False
        self.customers = {"Wenpro Markagente": {"id": "w", "name": "Wenpro Markagente"},
                          "RSA Markagente Pretoria": {"id": "r", "name": "RSA Markagente"}}
        self.there = set(there)
        self.added = []
        self.bank = {}
        self.attached = []

    def exists(self, customer_id, date, amount):
        return (customer_id, date, amount) in self.there

    def bank_payment_for(self, customer_id, date, amount):
        return self.bank.get((customer_id, amount))

    def add_lines(self, payment_id, st, undo=False, file_name=None):
        self.attached.append((payment_id, [s["account_sale"] for s in st["sales"]], file_name))

    def add(self, customer_id, st, file_name):
        self.added.append((customer_id, st["date"], st["paid"], [s["account_sale"] for s in st["sales"]], file_name))


def run(app, text, name):
    totals = {"added": 0, "there": 0, "other": 0, "unchanged": 0, "failed": []}
    with mock.patch.object(imp, "extract_pages", return_value=[text]):
        done = imp.handle(app, pathlib.Path(name), totals)
    return done, totals


class ImportTest(unittest.TestCase):
    def test_candidates(self):
        self.assertTrue(imp.is_candidate(pathlib.Path("20261002_0278929_Sum.pdf")))
        self.assertTrue(imp.is_candidate(pathlib.Path("12683_ACCCHEQS_PRE.RSA_20240516_052228-269579.pdf")))
        self.assertTrue(imp.is_candidate(pathlib.Path("2026-07-30 halesm01@universalleaf.com ULSA006606 - Nanini 29.07.2026.pdf")))
        self.assertTrue(imp.is_candidate(pathlib.Path("Nanini Boerdery - 6583.pdf")))
        self.assertTrue(imp.is_candidate(pathlib.Path("2026-07-16 fourieh1@universalleaf.com Nanini Boerdery - 6583.pdf")))
        self.assertTrue(imp.is_candidate(pathlib.Path("2026-05-22 marianne.fourie@peppadew.com 30ZZ608.pdf")))
        self.assertFalse(imp.is_candidate(pathlib.Path("20261002_0278929_Inv.pdf")))

    def test_adds_each_once(self):
        app = FakeApp(there={("r", "2024-05-16", 149282.17)})
        done, t = run(app, WENPRO, "x_Sum.pdf")
        self.assertTrue(done)
        self.assertEqual(app.added, [("w", "2026-09-30", 14606.64, ["56797326", "56843576", "56885275", "56981481"], "x_Sum.pdf")])
        done, t = run(app, RSA, "12683_ACCCHEQS_x.pdf")
        self.assertEqual((done, t["there"], len(app.added)), (True, 1, 1))

    def test_peppadew_advice_goes_on_its_bank_deposit(self):
        advice = """GROWER: 30ZZ718 NANINI FARMER PAYMENT ADVICE / TAX INVOICE PEPPADEW INTERNATIONAL PTY LTD
GRV-7133 55843 2026/04/17 07:45 12 2683.21 679.45 280 80% 20% 49% 28% 0% 3% R 4 0,294.94
GRV-7302 56754 2026/05/08 08:01 13 0 0 0 0% 0% 0% 29% 0% 2% R -
TOTAL 60 9783.79 1123 0.59% 0.20% 0.35% 0.00% 0.02% R 40,294.94
TOTAL DEDUCTIONS R -
NETT PAYMENT R 40,294.94
"""
        app = FakeApp()
        app.customers["Peppadew"] = {"id": "p", "name": "Peppadew"}
        app.bank[("p", 40294.94)] = {"id": "bank1", "date": "2026-05-25", "lines": 0}
        done, t = run(app, advice, "2026-05-22 marianne.fourie@peppadew.com 30ZZ718.pdf")
        self.assertEqual((done, t["added"], app.added), (True, 1, []))
        self.assertEqual(app.attached, [("bank1", ["GRV-7133"], "2026-05-22 marianne.fourie@peppadew.com 30ZZ718.pdf")])
        # Its loads already on it: nothing more.
        app.bank[("p", 40294.94)]["lines"] = 1
        done, t = run(app, advice, "2026-05-22 marianne.fourie@peppadew.com 30ZZ718.pdf")
        self.assertEqual((t["there"], len(app.attached)), (1, 1))
        # No deposit yet: a payment of its own.
        app.bank.clear()
        run(app, advice, "2026-05-22 marianne.fourie@peppadew.com 30ZZ718.pdf")
        self.assertEqual(app.added[-1][:3], ("p", "2026-05-22", 40294.94))

    def test_unknown_agent_and_not_a_summary(self):
        app = FakeApp()
        app.customers.pop("Wenpro Markagente")
        app.customers.pop("Peppadew", None)
        done, t = run(app, WENPRO, "x_Sum.pdf")
        self.assertEqual((done, len(t["failed"])), (False, 1))
        # A _Sum it can't read: listed and read again next time, not set aside.
        done, t = run(app, "WENPRO MARKAGENTE detail page", "x_Sum.pdf")
        self.assertEqual((done, len(t["failed"]), t["other"]), (False, 1, 0))
        # Anything else that isn't a summary: set aside.
        done, t = run(app, "WENPRO MARKAGENTE detail page", "ULSA000001.pdf")
        self.assertEqual((done, t["other"]), (True, 1))


if __name__ == "__main__":
    unittest.main()
