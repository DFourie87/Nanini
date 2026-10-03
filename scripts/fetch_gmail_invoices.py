#!/usr/bin/env python3
"""
Downloads market-agent account sales that arrive by email (Gmail) into the
client folder, so the daily sales import picks them up.

    python scripts\\fetch_gmail_invoices.py "D:\\Kliente\\Nanini 121 BK"
    python scripts\\fetch_gmail_invoices.py "D:\\Kliente\\Nanini 121 BK" --days 365   # look further back

How it works:
  * Reads Gmail READ-ONLY through scripts/gmail_access.py: the Google
    sign-in (py scripts\gmail_access.py once), or an app password in
    scripts/gmail_account.txt. Those files stay on this PC (.gitignore) --
    never commit or share them.
  * Looks at emails from the last --days days (default 60) that have PDF
    attachments, and reads each PDF with the same code as
    import_sales_report.py. Only PDFs it recognises as a market-agent account
    sale are saved -- statements, quotes, newsletters etc. are ignored.
  * Saves them to <folder>\\<tax year>\\BTW\\Gmail\\<YYYYMM>\\ (tax year runs
    March to February, like the existing year folders), where the importer's
    "--only-folder BTW" scan finds them.
  * Remembers which emails it has already handled (scripts/gmail_seen.json),
    so each run only looks at new mail. Nothing in Gmail is changed: the
    mailbox is opened read-only.
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
from import_sales_report import NotTracked, ParseError, detect_and_parse, extract_pages

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
SEEN_FILE = SCRIPT_DIR / "gmail_seen.json"


def tax_year(day):
    """South African tax year, named for the year it ends in (March-February)."""
    return day.year + 1 if day.month >= 3 else day.year


def safe_name(text):
    return re.sub(r'[<>:"/\\|?*\x00-\x1f]', "_", text).strip(" .")[:120] or "attachment.pdf"


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
    args = parser.parse_args()
    sys.stdout.reconfigure(line_buffering=True)

    root = pathlib.Path(args.folder)
    if not root.is_dir():
        print(f"PROBLEM: {root} doesn't exist. If it's on an external, USB or network drive, check it's connected.")
        return 1

    try:
        seen = set() if args.rescan else set(json.loads(SEEN_FILE.read_text(encoding="utf-8")))
    except (OSError, ValueError):
        seen = set()

    saved = ignored = already = 0
    gmail = None
    try:
        gmail = open_gmail()
        query = f'"has:attachment filename:pdf newer_than:{args.days}d"'
        ids = gmail.search(query)
        print(f"{len(ids)} email(s) with PDF attachments in the last {args.days} days.")

        for msg_id in ids:
            if msg_id in seen:
                already += 1
                continue
            raw = gmail.fetch(msg_id)

            msg = email.message_from_bytes(raw, policy=email.policy.default)
            try:
                sent = email.utils.parsedate_to_datetime(msg["Date"]).date()
            except (TypeError, ValueError):
                sent = dt.date.today()
            sender = email.utils.parseaddr(msg.get("From", ""))[1] or "unknown"

            for part in msg.iter_attachments():
                name = part.get_filename() or ""
                if part.get_content_type() != "application/pdf" and not name.lower().endswith(".pdf"):
                    continue
                pdf = part.get_payload(decode=True) or b""
                kind = classify_pdf(pdf)
                if kind != "sale":
                    ignored += 1
                    continue
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
            seen.add(msg_id)
    except GmailProblem as e:
        print(f"PROBLEM: {e}")
        return 1
    finally:
        if gmail:
            gmail.close()
        SEEN_FILE.write_text(json.dumps(sorted(seen)), encoding="utf-8")

    print(
        f"Done: {saved} account sale PDF(s) saved, {ignored} other PDF(s) ignored, "
        f"{already} email(s) already handled on an earlier run."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
