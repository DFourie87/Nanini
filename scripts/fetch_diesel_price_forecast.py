#!/usr/bin/env python3
"""
Fetches CEF Group's daily "Basic Fuel Price" bulletin PDF and writes the
diesel 0.05% sulphur expected price change -- for the next 1st-Wednesday
price adjustment -- into Supabase, for the app's diesel Reports tab to show
live.

Usage:
    pip install pdfplumber requests
    python3 scripts/fetch_diesel_price_forecast.py

Run this daily (e.g. from the same scheduled task as the sales importer).
CEF publishes a new bulletin most business days at:
    https://cefgroup.co.za/wp-content/uploads/<year>/<month>/Daily-<dd>-<mm>-<yyyy>.pdf
This script tries today's date first, then walks backward up to 10 days to
find the most recently published bulletin -- so weekends/public holidays
(no file published that day) are skipped automatically.

The bulletin's "AVERAGE UNIT OVER/(UNDER) RECOVERY" row gives a running
average, in SA cents/litre, for the pricing period that's still open. A
value in parentheses is an under-recovery (retailers earned less than the
regulated price allows), which the next price adjustment corrects by
raising the price; a plain positive value is an over-recovery, corrected by
lowering it.

Run this from your own computer -- Supabase (and cefgroup.co.za) aren't
reachable from some sandboxed environments (e.g. Claude's own containers).
"""
import datetime as dt
import io
import re

import requests

SUPABASE_URL = "https://nwyizwccmyanbdjmmdds.supabase.co"
SUPABASE_ANON_KEY = "sb_publishable_rJTMVGBh4FleAEBrDPWQzw_QC7c2dxV"

BULLETIN_URL = "https://cefgroup.co.za/wp-content/uploads/{y}/{m:02d}/Daily-{d:02d}-{m:02d}-{y}.pdf"

# "AVERAGE UNIT OVER/(UNDER) RECOVERY <start> - <end> <petrol95> <petrol93> <diesel 0.05%> <diesel 0.005%> <ill. par.>"
RECOVERY_ROW_RE = re.compile(
    r"AVERAGE UNIT OVER/\(UNDER\) RECOVERY\s+"
    r"\d{2}/\d{2}/\d{4}\s*-\s*\d{2}/\d{2}/\d{4}\s+"
    r"([\(\)\d.,-]+)\s+([\(\)\d.,-]+)\s+([\(\)\d.,-]+)\s+([\(\)\d.,-]+)\s+([\(\)\d.,-]+)"
)


def parse_cents(raw):
    """'(271.202)' -> -271.202 (under-recovery); '95.412' -> 95.412 (over-recovery)."""
    raw = raw.strip().replace(",", "")
    if raw.startswith("(") and raw.endswith(")"):
        return -float(raw[1:-1])
    return float(raw)


def find_latest_bulletin(max_days_back=10):
    today = dt.date.today()
    for delta in range(max_days_back):
        d = today - dt.timedelta(days=delta)
        url = BULLETIN_URL.format(y=d.year, m=d.month, d=d.day)
        resp = requests.get(url, timeout=30)
        if resp.status_code == 200 and resp.content[:4] == b"%PDF":
            return d, resp.content
    raise SystemExit(f"No CEF daily bulletin found in the last {max_days_back} days")


def extract_diesel_005_recovery_cents(pdf_bytes):
    import pdfplumber

    with pdfplumber.open(io.BytesIO(pdf_bytes)) as pdf:
        text = "\n".join(page.extract_text() or "" for page in pdf.pages)

    m = RECOVERY_ROW_RE.search(text)
    if not m:
        raise SystemExit(
            "Couldn't find the 'AVERAGE UNIT OVER/(UNDER) RECOVERY' row in the "
            "bulletin -- its layout may have changed"
        )
    # Column order: Petrol 95, Petrol 93, Diesel 0.05%, Diesel 0.005%, Ill. Par.
    return parse_cents(m.group(3))


def next_first_wednesday(from_date):
    """The next 1st Wednesday of a month strictly after from_date (SA fuel prices change on this day)."""

    def first_wednesday_of(year, month):
        d = dt.date(year, month, 1)
        while d.weekday() != 2:  # Monday=0 ... Wednesday=2
            d += dt.timedelta(days=1)
        return d

    candidate = first_wednesday_of(from_date.year, from_date.month)
    if candidate > from_date:
        return candidate
    year, month = from_date.year, from_date.month + 1
    if month > 12:
        year, month = year + 1, 1
    return first_wednesday_of(year, month)


def save_forecast(bulletin_date, next_adjustment_date, expected_change_rand):
    headers = {
        "apikey": SUPABASE_ANON_KEY,
        "Authorization": f"Bearer {SUPABASE_ANON_KEY}",
        "Content-Type": "application/json",
        "Prefer": "resolution=merge-duplicates,return=representation",
    }
    body = {
        "id": 1,
        "fuel_type": "diesel_0_05",
        "bulletin_date": bulletin_date.isoformat(),
        "next_adjustment_date": next_adjustment_date.isoformat(),
        "expected_change_rand": round(expected_change_rand, 2),
    }
    resp = requests.post(
        f"{SUPABASE_URL}/rest/v1/diesel_price_forecast?on_conflict=id",
        json=body,
        headers=headers,
        timeout=30,
    )
    resp.raise_for_status()


def main():
    bulletin_date, pdf_bytes = find_latest_bulletin()
    cents = extract_diesel_005_recovery_cents(pdf_bytes)
    # Under-recovery (negative) -> price rises; over-recovery (positive) -> price falls.
    expected_change_rand = -cents / 100
    adjustment_date = next_first_wednesday(bulletin_date)

    direction = "increase" if expected_change_rand >= 0 else "decrease"
    print(
        f"Bulletin {bulletin_date}: diesel 0.05% expected {direction} of "
        f"R{abs(expected_change_rand):.2f} on {adjustment_date} (next 1st Wednesday)"
    )
    save_forecast(bulletin_date, adjustment_date, expected_change_rand)
    print("Saved to Supabase.")


if __name__ == "__main__":
    main()
