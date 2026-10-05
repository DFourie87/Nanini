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

    def exists(self, customer_id, date, amount):
        return (customer_id, date, amount) in self.there

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
        self.assertFalse(imp.is_candidate(pathlib.Path("20261002_0278929_Inv.pdf")))

    def test_adds_each_once(self):
        app = FakeApp(there={("r", "2024-05-16", 149282.17)})
        done, t = run(app, WENPRO, "x_Sum.pdf")
        self.assertTrue(done)
        self.assertEqual(app.added, [("w", "2026-09-30", 14606.64, ["56797326", "56843576", "56885275", "56981481"], "x_Sum.pdf")])
        done, t = run(app, RSA, "12683_ACCCHEQS_x.pdf")
        self.assertEqual((done, t["there"], len(app.added)), (True, 1, 1))

    def test_unknown_agent_and_not_a_summary(self):
        app = FakeApp()
        app.customers.pop("Wenpro Markagente")
        done, t = run(app, WENPRO, "x_Sum.pdf")
        self.assertEqual((done, len(t["failed"])), (False, 1))
        done, t = run(app, "WENPRO MARKAGENTE detail page", "x_Sum.pdf")
        self.assertEqual((done, t["other"]), (True, 1))


if __name__ == "__main__":
    unittest.main()
