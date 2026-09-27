#!/usr/bin/env python3
"""
Checks that the Supabase secret key set up for import_sales_report.py works,
without printing the key or any data.

    python scripts\\check_secret_key.py

It reads the key exactly the way the importer does (SUPABASE_SECRET_KEY, or
scripts/supabase_secret_key.txt), then asks the database for something only
the secret key may see: whether any Nanini user logins exist (the app_users
table is closed to the public key even before the lockdown).
"""
import os
import sys

import requests

from import_sales_report import SECRET_KEY_FILE, SUPABASE_ANON_KEY, SUPABASE_URL, _auth_headers


def main():
    key = os.environ.get("SUPABASE_SECRET_KEY", "").strip()
    source = "the SUPABASE_SECRET_KEY environment variable"
    if not key:
        if not SECRET_KEY_FILE.exists():
            print(f"PROBLEM: no key file found. Expected it at:\n  {SECRET_KEY_FILE}")
            print("Check the name is exactly supabase_secret_key.txt (not ...txt.txt) and it's in this scripts folder.")
            return 1
        key = SECRET_KEY_FILE.read_text(encoding="utf-8").strip()
        source = str(SECRET_KEY_FILE)
    print(f"Key found in {source} ({len(key)} characters, starts with '{key[:10]}...').")

    if not key:
        print("PROBLEM: the key file is empty. Paste the secret key into it and save.")
        return 1
    if key == SUPABASE_ANON_KEY or key.startswith("sb_publishable_"):
        print("PROBLEM: that's the PUBLISHABLE (public) key. Copy the key under 'Secret keys' instead (starts with sb_secret_).")
        return 1
    if " " in key or "\n" in key or key.startswith('"'):
        print("PROBLEM: the key contains spaces, line breaks or quotes. The file must hold only the key itself.")
        return 1
    if not (key.startswith("sb_secret_") or key.startswith("eyJ")):
        print("WARNING: the key doesn't look like a Supabase secret key (sb_secret_... or a legacy eyJ... service_role key).")

    try:
        resp = requests.get(
            f"{SUPABASE_URL}/rest/v1/app_users",
            params={"select": "id", "limit": "1"},
            headers=_auth_headers(),
            timeout=30,
        )
    except requests.RequestException as e:
        print(f"PROBLEM: could not reach Supabase ({e}). Check this PC's internet connection.")
        return 1

    if resp.status_code in (401, 403):
        print(f"PROBLEM: Supabase refused the key (HTTP {resp.status_code}). It's probably mistyped or was revoked -- copy it again.")
        print(f"Details: {resp.text[:200]}")
        return 1
    if resp.status_code != 200:
        print(f"PROBLEM: unexpected answer from Supabase (HTTP {resp.status_code}): {resp.text[:200]}")
        return 1
    if not resp.json():
        print("PROBLEM: the key works but can't see protected data -- it isn't the SECRET key.")
        print("Copy the key under 'Secret keys' (or the legacy 'service_role' key), not the publishable/anon one.")
        return 1

    resp = requests.get(
        f"{SUPABASE_URL}/rest/v1/sales_reports",
        params={"select": "id", "limit": "1"},
        headers=_auth_headers(),
        timeout=30,
    )
    if resp.status_code != 200:
        print(f"PROBLEM: the key works, but reading the Sales tables failed (HTTP {resp.status_code}): {resp.text[:200]}")
        return 1

    print("OK: the secret key works. The sales importer will keep working after the lockdown.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
