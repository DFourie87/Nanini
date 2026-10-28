"""Tests for fetch_gmail_invoices.py (no Gmail or app needed):

    python -m unittest scripts/test_fetch_gmail_invoices.py
"""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

import fetch_gmail_invoices as f  # noqa: E402
from fetch_supplier_docs import supplier_addresses  # noqa: E402
from import_sales_report import wenfam_agent  # noqa: E402

CUSTOMERS = [
    {"name": "Botha Roodt Johannesburg", "addresses": supplier_addresses("elmarie@botharoodt.com, data@freshmarksystems.co.za")},
    {"name": "Wenpro Markagente", "addresses": supplier_addresses("@wenpro.co.za")},
]


class CustomerSenders(unittest.TestCase):
    def test_a_customers_address_or_domain(self):
        self.assertEqual(f.listed_customer("Data@FreshmarkSystems.co.za", CUSTOMERS), "Botha Roodt Johannesburg")
        self.assertEqual(f.listed_customer("accounts@wenpro.co.za", CUSTOMERS), "Wenpro Markagente")

    def test_others_at_a_shared_system_are_not_a_customer(self):
        # Freshmark sends for other agents too: only the listed address counts.
        self.assertIsNone(f.listed_customer("support@freshmarksystems.co.za", CUSTOMERS))
        self.assertIsNone(f.listed_customer("someone@gmail.com", CUSTOMERS))
        self.assertIsNone(f.listed_customer("", CUSTOMERS))


class AgentNames(unittest.TestCase):
    def test_botha_roodt_by_any_of_its_names(self):
        for text in ["BOTHA ROODT JOHANNESBURG", "Grow Botha Roodt Jhb", "GROW BOTHA ROODT JHB (PTY) LTD"]:
            self.assertEqual(wenfam_agent(f"Opsomming van betalings\n{text}\n"), "Botha Roodt Johannesburg")
        self.assertEqual(wenfam_agent("Wenpro Markagente"), "Wenpro Markagente")
        self.assertIsNone(wenfam_agent("RSA Markagente"))


if __name__ == "__main__":
    unittest.main()
