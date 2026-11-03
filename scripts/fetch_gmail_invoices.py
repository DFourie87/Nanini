#!/usr/bin/env python3
"""
Downloads market-agent account sales that arrive by email (Gmail) into the
client folder, so the daily sales import picks them up.

    python scripts\\fetch_gmail_invoices.py "D:\\Kliente\\Nanini 121 BK"
    python scripts\\fetch_gmail_invoices.py "D:\\Kliente\\Nanini 121 BK" --days 365   # look further back
    python scripts\\fetch_gmail_invoices.py "D:\\Kliente\\Nanini 121 BK" --days 120 --from fourieh1@universalleaf.com
      (only that sender's emails, each PDF listed with what it was taken for)

How it works:
  * Reads Gmail READ-ONLY through scripts/gmail_access.py: the Google
    sign-in (py scripts\\gmail_access.py once), or an app password in
    scripts/gmail_account.txt. Those files stay on this PC (.gitignore) --
    never commit or share them.
  * Looks at emails from the last --days days (default 60) that have PDF
    attachments, and reads each PDF with the same code as
    import_sales_report.py. Only PDFs it recognises as a market-agent account
    sale are saved -- statements, quotes, newsletters etc. are ignored.
  * Saves them to <folder>\\<tax year>\\BTW\\Gmail\\<YYYYMM>\\ (tax year runs
    March to February, like the existing year folders), where the importer's
    "--only-folder BTW" scan finds them.
  * A PDF from an address on a customer's Emails field (Customers app; an
    agent's statements from its system, e.g. Botha Roodt's from
    data@freshmarksystems.co.za) is kept even when its layout isn't known
    yet -- the importer then lists it under NEEDS A LOOK.
  * Remembers which emails it has already handled (scripts/gmail_seen.json),
    so each run only looks at new mail. An email whose PDFs were all passed
    by is looked at again once the importer changes (a new agent's layout).
    Nothing in Gmail is changed: the mailbox is opened read-only.
"""
import argparse
import datetime as dt
import email
import email.policy
import email.utils
import json
import pathlib
import re
import sys
import tempfile

from gmail_access import GmailProblem, open_gmail
from import_sales_report import AgentDocument, NotTracked, ParseError, detect_and_parse, extract_pages, parser_version

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
SEEN_FILE = SCRIPT_DIR / "gmail_seen.json"


def tax_year(day):
    """South African tax year, named for the year it ends in (March-February)."""
    return day.year + 1 if day.month >= 3 else day.year


def safe_name(text):
    return re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", text).strip(" .")[:120] or "attachment.pdf"


def load_seen(entries, version):
    """gmail_seen.json's emails: (handled, passed by with this importer). An
    email whose PDFs were all passed by is kept as "<id>|v:<version>": looked
    at again once the importer changes."""
    handled, passed = set(), set()
    for e in entries:
        msg_id, _, v = e.partition("|v:")
        if not v:
            handled.add(msg_id)
        elif v == version:
            passed.add(msg_id)
    return handled, passed


def dump_seen(handled, passed, version):
    return sorted(handled) + sorted(f"{m}|v:{version}" for m in passed - handled)


def customer_addresses():
    """Each customer's name and the addresses on its Emails field (as for
    suppliers: an address, or "@domain"); [] when the app can't be reached."""
    try:
        import requests

        from fetch_supplier_docs import supplier_addresses
        from import_sales_report import SUPABASE_URL, _auth_headers

        resp = requests.get(f"{SUPABASE_URL}/rest/v1/customers", headers=_auth_headers(), params={"select": "name,emails"}, timeout=30)
        resp.raise_for_status()
        return [{"name": c["name"], "addresses": supplier_addresses(c.get("emails"))} for c in resp.json()]
    except Exception as e:  # the app or its key unavailable: only recognised account sales are kept
        print(f"Note: the customers' email addresses couldn't be read ({e}).")
        return []


def listed_customer(sender, customers):
    """The customer whose Emails field lists [sender] (or its "@domain"), else None."""
    sender = (sender or "").strip().lower()
    domain = "@" + sender.split("@", 1)[-1]
    return next((c["name"] for c in customers if sender in c["addresses"] or domain in c["addresses"]), None)


def classify_pdf(data):
    """'sale' for a market-agent account sale (readable or not), 'not_tracked'
    for a crop no longer grown, None for anything else."""
    with tempfile.NamedTemporaryFile(suffix=".pdf", delete=False) as tmp:
        tmp.write(data)
        tmp_path = pathlib.Path(tmp.name)
    try:
        detect_and_parse(extract_pages(str(tmp_path)))
        return "sale"
    except NotTracked:
        return "not_tracked"
    except AgentDocument:
        # The agent's detail / summary pages, daily lists, afrekeningstate:
        # saved with the account sales (the importer passes them by).
        return "sale"
    except ParseError as e:
        # A known agent's layout it couldn't fully read still belongs with the
        # account sales -- the importer lists it under NEEDS A LOOK.
        return None if str(e).startswith("Don't recognise") else "sale"
    except Exception:
        return None  # not a readable PDF
    finally:
        tmp_path.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("folder", help="The client folder, e.g. D:\\Kliente\\Nanini 121 BK")
    parser.add_argument("--days", type=int, default=60, help="How far back to look in Gmail (default 60 days).")
    parser.add_argument("--rescan", action="store_true", help="Check emails again even if an earlier run already handled them.")
    parser.add_argument("--from", dest="sender", metavar="ADDRESS",
                        help="Only emails from this address (or @domain), each PDF listed with what it was taken for.")
    args = parser.parse_args()
    sys.stdout.reconfigure(line_buffering=True)

    root = pathlib.Path(args.folder)
    if not root.is_dir():
        print(f"PROBLEM: {root} doesn't exist. If it's on an external, USB or network drive, check it's connected.")
        return 1

    version = parser_version()
    try:
        handled, passed = (set(), set()) if args.rescan else load_seen(json.loads(SEEN_FILE.read_text(encoding="utf-8")), version)
    except (OSError, ValueError):
        handled, passed = set(), set()

    saved = ignored = already = 0
    customers = customer_addresses()
    gmail = None
    try:
        gmail = open_gmail()
        query = f'"has:attachment filename:pdf newer_than:{args.days}d{f" from:{args.sender}" if args.sender else ""}"'
        ids = gmail.search(query)
        print(f"{len(ids)} email(s) with PDF attachments in the last {args.days} days{f' from {args.sender}' if args.sender else ''}.")

        for msg_id in ids:
            if (msg_id in handled or msg_id in passed) and not args.sender:
                already += 1
                continue
            raw = gmail.fetch(msg_id)
            kept = False

            msg = email.message_from_bytes(raw, policy=email.policy.default)
            try:
                sent = email.utils.parsedate_to_datetime(msg["Date"]).date()
            except (TypeError, ValueError):
                sent = dt.date.today()
            sender = email.utils.parseaddr(msg.get("From", ""))[1] or "unknown"

            # Every part, also inline ones and those in a forwarded email.
            for part in msg.walk():
                if part.is_multipart():
                    continue
                name = part.get_filename() or ""
                if part.get_content_type() != "application/pdf" and not name.lower().endswith(".pdf"):
                    continue
                pdf = part.get_payload(decode=True) or b""
                kind = classify_pdf(pdf)
                # From a customer's own address: kept even if not recognised (yet).
                customer = listed_customer(sender, customers)
                if kind is None and customer:
                    kind = "sale"
                    print(f"  From {customer} ({sender}), layout not known yet: kept for the import to list -- {name or '(no name)'}")
                if args.sender:
                    print(f"  {sent.isoformat()} {sender}: {name or '(no name)'} -- "
                          f"{'an account sale' if kind == 'sale' else 'not an account sale' if kind is None else kind}")
                if kind != "sale":
                    ignored += 1
                    continue
                kept = True
                dest_dir = root / str(tax_year(sent)) / "BTW" / "Gmail" / sent.strftime("%Y%m")
                dest_dir.mkdir(parents=True, exist_ok=True)
                dest = dest_dir / safe_name(f"{sent.isoformat()} {sender} {name or 'invoice.pdf'}")
                if dest.exists() and dest.read_bytes() == pdf:
                    continue
                if dest.exists():
                    dest = dest.with_name(f"{dest.stem} ({msg_id}){dest.suffix}")
                dest.write_bytes(pdf)
                saved += 1
                print(f"  Saved {dest}")
            (handled if kept else passed).add(msg_id)
    except GmailProblem as e:
        print(f"PROBLEM: {e}")
        return 1
    finally:
        if gmail:
            gmail.close()
        SEEN_FILE.write_text(json.dumps(dump_seen(handled, passed, version)), encoding="utf-8")

    print(
        f"Done: {saved} account sale PDF(s) saved, {ignored} other PDF(s) ignored, "
        f"{already} email(s) already handled on an earlier run."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
