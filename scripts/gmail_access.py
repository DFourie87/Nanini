#!/usr/bin/env python3
"""
Read-only access to Gmail for fetch_gmail_invoices.py and
fetch_supplier_docs.py.

Two ways in, whichever is set up on this PC:

  * Google sign-in (no 2-Step Verification needed) -- used when
    scripts/gmail_oauth_client.json is there. Access is READ-ONLY
    (gmail.readonly): the scripts can't change, delete, label or send
    anything, and Google shows exactly that when you sign in. Sign in once:

        py scripts\\gmail_access.py

    A browser opens: choose the Gmail account and allow "View your email
    messages and settings". The sign-in is kept in scripts/gmail_token.json.
    To take the access away again: Google Account > Security > "Your
    connections to third-party apps & services" > Nanini office PC > Delete.

  * An app password (needs 2-Step Verification on) in
    scripts/gmail_account.txt: line 1 the Gmail address, line 2 the app
    password. The mailbox is opened read-only.

gmail_oauth_client.json, gmail_token.json and gmail_account.txt stay on this
PC only (.gitignore) -- never commit or share them.
"""
import base64
import imaplib
import pathlib
import re
import sys

SCRIPT_DIR = pathlib.Path(__file__).resolve().parent
ACCOUNT_FILE = SCRIPT_DIR / "gmail_account.txt"
CLIENT_FILE = SCRIPT_DIR / "gmail_oauth_client.json"
TOKEN_FILE = SCRIPT_DIR / "gmail_token.json"
IMAP_HOST = "imap.gmail.com"
SCOPES = ["https://www.googleapis.com/auth/gmail.readonly"]
API = "https://gmail.googleapis.com/gmail/v1/users/me"
SIGN_IN = "py scripts\\gmail_access.py"


class GmailProblem(Exception):
    """Gmail can't be reached or won't let us in -- the message says what to do."""


# ---------------------------------------------------------------------------
# Google sign-in (Gmail API, read-only)
# ---------------------------------------------------------------------------

class ApiGmail:
    """Message ids are Gmail's own (the same numbers as over IMAP, so emails
    handled before are still known)."""

    def __init__(self, session):
        self.session = session

    def _get(self, url, **params):
        try:
            r = self.session.get(url, params=params, timeout=60)
        except Exception as e:
            if type(e).__name__ == "RefreshError":
                raise GmailProblem(f"The Gmail sign-in has run out or was removed. Sign in again: {SIGN_IN}")
            raise
        if r.status_code in (401, 403):
            raise GmailProblem(f"Gmail refused access ({r.status_code}). Sign in again: {SIGN_IN}")
        r.raise_for_status()
        return r.json()

    def search(self, query):
        query = query.strip().strip('"')
        ids, page = [], None
        while True:
            params = {"q": query, "maxResults": 500}
            if page:
                params["pageToken"] = page
            data = self._get(f"{API}/messages", **params)
            ids += [str(int(m["id"], 16)) for m in data.get("messages", [])]
            page = data.get("nextPageToken")
            if not page:
                return ids

    def fetch(self, msg_id):
        data = self._get(f"{API}/messages/{int(msg_id):x}", format="raw")
        raw = data["raw"]
        return base64.urlsafe_b64decode(raw + "=" * (-len(raw) % 4))

    def address(self):
        return self._get(f"{API}/profile").get("emailAddress", "?")

    def close(self):
        pass


def _credentials(interactive):
    from google.auth.exceptions import RefreshError
    from google.auth.transport.requests import Request
    from google.oauth2.credentials import Credentials

    creds = None
    if TOKEN_FILE.exists():
        try:
            creds = Credentials.from_authorized_user_file(str(TOKEN_FILE), SCOPES)
        except ValueError:
            creds = None
    if creds and creds.valid:
        return creds
    if creds and creds.refresh_token:
        try:
            creds.refresh(Request())
            TOKEN_FILE.write_text(creds.to_json(), encoding="utf-8")
            return creds
        except RefreshError:
            creds = None  # removed, expired or the password changed: sign in again
    if not interactive:
        raise GmailProblem(f"Not signed in to Gmail (or the sign-in has run out). Sign in once: {SIGN_IN}")
    from google_auth_oauthlib.flow import InstalledAppFlow

    flow = InstalledAppFlow.from_client_secrets_file(str(CLIENT_FILE), SCOPES)
    creds = flow.run_local_server(port=0, prompt="consent")
    TOKEN_FILE.write_text(creds.to_json(), encoding="utf-8")
    return creds


def _open_api(interactive):
    try:
        from google.auth.transport.requests import AuthorizedSession
    except ImportError:
        raise GmailProblem("The Google sign-in library isn't installed. Run once: py -m pip install google-auth-oauthlib")
    return ApiGmail(AuthorizedSession(_credentials(interactive)))


# ---------------------------------------------------------------------------
# App password (IMAP, read-only)
# ---------------------------------------------------------------------------

def load_account():
    lines = [l.strip() for l in ACCOUNT_FILE.read_text(encoding="utf-8").splitlines() if l.strip()]
    if len(lines) < 2:
        raise GmailProblem(f"{ACCOUNT_FILE.name} needs two lines: the Gmail address, then the app password.")
    # Google shows app passwords in groups of four ("abcd efgh ijkl mnop").
    return lines[0], lines[1].replace(" ", "")


def find_all_mail(imap):
    """The 'All Mail' folder (its name depends on Gmail's language), so
    archived emails are found too. Falls back to the inbox."""
    typ, folders = imap.list()
    if typ == "OK":
        for raw in folders or []:
            line = raw.decode(errors="replace") if isinstance(raw, bytes) else str(raw)
            if "\\All" in line:
                m = re.search(r'"([^"]+)"\s*$', line) or re.search(r"(\S+)\s*$", line)
                if m:
                    return '"' + m.group(1) + '"'
    return "INBOX"


class ImapGmail:
    def __init__(self, imap, address):
        self.imap = imap
        self._address = address
        self._uids = {}
        # Read-only: nothing in Gmail is changed (BODY.PEEK doesn't even mark as read).
        imap.select(find_all_mail(imap), readonly=True)

    def search(self, query):
        typ, data = self.imap.uid("SEARCH", None, "X-GM-RAW", query)
        uids = data[0].split() if typ == "OK" and data and data[0] else []
        ids = []
        for uid in uids:
            typ, parts = self.imap.uid("FETCH", uid, "(X-GM-MSGID)")
            line = b" ".join(p if isinstance(p, bytes) else p[0] for p in parts or [] if p) if typ == "OK" else b""
            m = re.search(rb"X-GM-MSGID (\d+)", line)
            msg_id = m.group(1).decode() if m else uid.decode()
            self._uids[msg_id] = uid
            ids.append(msg_id)
        return ids

    def fetch(self, msg_id):
        typ, parts = self.imap.uid("FETCH", self._uids[msg_id], "(BODY.PEEK[])")
        if typ != "OK" or not parts or not isinstance(parts[0], tuple):
            raise GmailProblem("Gmail didn't send that email.")
        return parts[0][1]

    def address(self):
        return self._address

    def close(self):
        try:
            self.imap.logout()
        except Exception:
            pass


def _open_imap():
    address, app_password = load_account()
    try:
        imap = imaplib.IMAP4_SSL(IMAP_HOST)
        imap.login(address, app_password)
    except imaplib.IMAP4.error as e:
        raise GmailProblem(
            f"Gmail refused the login ({e}). App passwords stop working when 2-Step Verification is switched off; "
            f"use the Google sign-in instead (see scripts/README.md).")
    return ImapGmail(imap, address)


def open_gmail(interactive=False):
    """Gmail, read-only: the Google sign-in if it's set up, else the app password."""
    try:
        if CLIENT_FILE.exists() or TOKEN_FILE.exists():
            return _open_api(interactive)
        if ACCOUNT_FILE.exists():
            return _open_imap()
    except OSError as e:
        raise GmailProblem(f"could not reach Gmail ({e}). Check this PC's internet connection.")
    raise GmailProblem(f"Gmail isn't set up on this PC: put {CLIENT_FILE.name} in the scripts folder and run {SIGN_IN} "
                       "(see scripts/README.md).")


def _client_from_downloads():
    """The OAuth client file Google Cloud downloads ("client_secret_....json"),
    copied here as gmail_oauth_client.json."""
    found = sorted((pathlib.Path.home() / "Downloads").glob("client_secret_*.json"), key=lambda p: p.stat().st_mtime)
    if found:
        CLIENT_FILE.write_bytes(found[-1].read_bytes())
        print(f"Using {found[-1].name} from Downloads (copied to scripts\\{CLIENT_FILE.name}).")


def main():
    """Sign in once (opens the browser) and check Gmail can be read."""
    if not CLIENT_FILE.exists():
        _client_from_downloads()
    if not CLIENT_FILE.exists():
        print(f"PROBLEM: {CLIENT_FILE} not found. Download the OAuth client (Desktop app) from Google Cloud, "
              f"rename it to {CLIENT_FILE.name} and put it in the scripts folder (see scripts/README.md).")
        return 1
    try:
        gmail = open_gmail(interactive=True)
        address = gmail.address()
        count = len(gmail.search("has:attachment filename:pdf newer_than:7d"))
    except GmailProblem as e:
        print(f"PROBLEM: {e}")
        return 1
    print(f"OK: signed in to {address} (read-only). {count} email(s) with PDFs in the last 7 days.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
