"""python -m unittest test_import_seen.py (from scripts)"""
import pathlib
import sys
import unittest

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from import_sales_report import parser_version, seen_current, seen_entry  # noqa: E402


class ImportSeen(unittest.TestCase):
    def test_passed_by_pdfs_read_again_after_the_importer_changes(self):
        account_sale = seen_entry("100:5", False, "v1")
        passed_by = seen_entry("100:5", True, "v1")
        self.assertTrue(seen_current(account_sale, "100:5", "v2"))  # dealt with: never again
        self.assertTrue(seen_current(passed_by, "100:5", "v1"))
        self.assertFalse(seen_current(passed_by, "100:5", "v2"))  # importer changed: read again
        self.assertFalse(seen_current(account_sale, "200:6", "v1"))  # the file changed
        self.assertFalse(seen_current(None, "100:5", "v1"))

    def test_the_version_follows_the_importer(self):
        self.assertEqual(parser_version(), parser_version())
        self.assertEqual(len(parser_version()), 12)


if __name__ == "__main__":
    unittest.main()
