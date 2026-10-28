#!/usr/bin/env python3
"""
Reads the photos of filled-in printed timesheets sent from the phones
(Nanini Capture > TIMESHEET) and puts what is written on them into the
entry, for someone to check and approve in the hub (Employees > Captured).
Nothing goes into the hours until it's approved there.

    py scripts\\read_timesheets.py               # read the photos waiting
    py scripts\\read_timesheets.py --dry-run     # show what it reads, change nothing
    py scripts\\read_timesheets.py --again       # read the waiting photos again (e.g. after a failed read)

How it works:
  * Each page's QR code (printed by the hub's Print timesheets) says which
    farm, month, days and work group the sheet is for, and which workers are
    printed on it, in order. It's read with OpenCV.
  * Claude reads the handwriting: per line the hours in each day's box, and a
    new worker's name and ID/passport number written on an empty line. A box
    it can't read comes back as "?", for the person checking to fix.
  * A new worker whose ID/passport number matches an employee is matched to
    them; otherwise the person checking picks who it is.

Needs (once):
  * py -m pip install anthropic opencv-python numpy requests
  * An Anthropic API key in scripts\\anthropic_api_key.txt (only the key), or
    the ANTHROPIC_API_KEY environment variable. Get one at
    https://console.anthropic.com -> API keys. The file is in .gitignore:
    never commit it or send it to anyone.
  * The Supabase secret key (scripts\\supabase_secret_key.txt), as for the
    sales import, and docs/sql/timesheet_photos.sql run in Supabase.

Runs in run_import_task.bat after the other imports (log:
scripts\\timesheet_log.txt).
"""
import argparse
import base64
import datetime as dt
import json
import os
import pathlib
import sys

from import_sales_report import SUPABASE_URL, _auth_headers

HERE = pathlib.Path(__file__).resolve().parent
ANTHROPIC_KEY_FILE = HERE / "anthropic_api_key.txt"
MODEL = "claude-opus-5-5"
# Claude reads images up to 2576 px on the long edge.
MAX_EDGE = 2576
# Workers per printed page (kTimesheetRows in the app's timesheet_pdf.dart).
ROWS_PER_PAGE = 20
WEEKDAYS = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]


class SheetProblem(Exception):
    """A photo that can't be read: the reason is shown in the hub."""


# --- The QR code -------------------------------------------------------------

def parse_code(text):
    """A page's QR code: NTS2|month|first day|last day|farm|group|page/pages|ids
    (ids shortened to 8 characters, '-' for no group)."""
    parts = (text or "").strip().split("|")
    if len(parts) != 8 or parts[0] != "NTS2":
        raise SheetProblem("The QR code isn't a Nanini timesheet's (print the sheet again from the hub)")
    _, month, first, last, farm, group, page, ids = parts
    try:
        page_no, pages = (int(x) for x in page.split("/"))
        dt.date.fromisoformat(first)
        dt.date.fromisoformat(last)
    except ValueError:
        raise SheetProblem("The QR code couldn't be understood")
    return {
        "month": month,
        "first": first,
        "last": last,
        "farm": farm,
        "group": None if group == "-" else group,
        "page": page_no,
        "pages": pages,
        "ids": [i for i in ids.split(",") if i],
    }


def sheet_days(first, last):
    """The sheet's days, in column order ('YYYY-MM-DD')."""
    d, end = dt.date.fromisoformat(first), dt.date.fromisoformat(last)
    out = []
    while d <= end:
        out.append(d.isoformat())
        d += dt.timedelta(days=1)
    return out


def find_qr(image):
    """The QR code's text in a photo (an OpenCV image), or None. Tries the
    whole photo, then the top-right corner (where it's printed) enlarged."""
    import cv2

    detector = cv2.QRCodeDetector()
    grey = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if image.ndim == 3 else image
    tries = []
    # As photographed, then turned round (a sheet photographed upside down or
    # sideways): the whole page, then the top-right corner (where it's
    # printed) and the others, each also enlarged.
    for turned in (grey, cv2.rotate(grey, cv2.ROTATE_180), cv2.rotate(grey, cv2.ROTATE_90_CLOCKWISE), cv2.rotate(grey, cv2.ROTATE_90_COUNTERCLOCKWISE)):
        h, w = turned.shape[:2]
        tries.append(turned)
        for c in (turned[: h // 2, w // 2:], turned[h // 2:, : w // 2], turned[: h // 2, : w // 2], turned[h // 2:, w // 2:]):
            tries += [c, cv2.resize(c, None, fx=2, fy=2, interpolation=cv2.INTER_CUBIC)]
    for img in tries:
        for candidate in (img, cv2.threshold(img, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)[1]):
            text, _, _ = detector.detectAndDecode(candidate)
            if text:
                return text
    return None


def decode_photo(data):
    import cv2
    import numpy as np

    image = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
    if image is None:
        raise SheetProblem("The photo couldn't be opened")
    return image


def photo_for_claude(image):
    """The photo as JPEG, no larger than Claude reads (2576 px long edge)."""
    import cv2

    h, w = image.shape[:2]
    scale = min(1.0, MAX_EDGE / max(h, w))
    if scale < 1:
        image = cv2.resize(image, (round(w * scale), round(h * scale)), interpolation=cv2.INTER_AREA)
    ok, jpg = cv2.imencode(".jpg", image, [cv2.IMWRITE_JPEG_QUALITY, 90])
    if not ok:
        raise SheetProblem("The photo couldn't be prepared")
    return jpg.tobytes()


# --- Matching the sheet to the app -------------------------------------------

def _one(prefix, rows, what):
    found = [r for r in rows if r["id"].startswith(prefix)]
    if len(found) != 1:
        raise SheetProblem(f"The {what} on the QR code isn't in the app ({len(found)} found)")
    return found[0]


def employee_name(e):
    return " ".join(x for x in [(e.get("surname") or e.get("last_name") or "").strip(), (e.get("first_name") or "").strip()] if x)


def resolve(code, farms, groups, employees):
    """The sheet's farm, group and printed workers (in order) from the app."""
    farm = _one(code["farm"], farms, "farm")
    group = _one(code["group"], groups, "work group") if code["group"] else None
    printed = []
    for prefix in code["ids"]:
        found = [e for e in employees if e["id"].startswith(prefix)]
        printed.append(found[0] if len(found) == 1 else None)
    return farm, group, printed


def first_row(code):
    """The row number of the page's first line (rows are numbered across pages)."""
    return (code["page"] - 1) * ROWS_PER_PAGE + 1


# --- Asking Claude -----------------------------------------------------------

SCHEMA = {
    "type": "object",
    "properties": {
        "rows": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "row": {"type": "integer"},
                    "surname": {"type": "string"},
                    "name": {"type": "string"},
                    "id_number": {"type": "string"},
                    "hours": {"type": "array", "items": {"type": "string"}},
                    "total": {"type": "string"},
                },
                "required": ["row", "surname", "name", "id_number", "hours", "total"],
                "additionalProperties": False,
            },
        },
        "notes": {"type": "string"},
    },
    "required": ["rows", "notes"],
    "additionalProperties": False,
}

SYSTEM = (
    "You read photographed farm timesheets: printed grids filled in by hand by a foreman. "
    "Accuracy matters more than speed: these hours become the workers' pay. "
    "Read only what is written; never fill in a box from the boxes around it."
)


def prompt_text(code, days, printed):
    start = first_row(code)
    columns = "\n".join(
        f"  {i + 1}. {dt.date.fromisoformat(d).day} {dt.date.fromisoformat(d).strftime('%b')} ({WEEKDAYS[dt.date.fromisoformat(d).weekday()]})"
        for i, d in enumerate(days)
    )
    lines = "\n".join(
        f"  row {start + i}: {employee_name(e) if e else '(a worker no longer in the app)'}" for i, e in enumerate(printed)
    )
    return f"""This photo is page {code['page']} of {code['pages']} of a printed timesheet.

The table's columns: # (row number), Surname, Name, ID / Passport, then one column per day, then Total.
The {len(days)} day columns, left to right:
{columns}

Printed lines on this page:
{lines or '  (none -- only empty lines for new workers)'}
The empty lines after them are for new or temporary workers, written in by hand.

Return one entry for every printed line (even if it has no hours), and one for every empty line that has
something written in it (skip lines that are still empty). For each:
- row: the number in the # column.
- surname, name: as printed, or as written for a new worker.
- id_number: the ID or passport number if written, else "".
- hours: exactly {len(days)} strings, one per day column in the order above: "" for an empty box; the number of
  hours as written for a worked day (use a point for decimals, e.g. "9.5"; "½" is ".5"); "" for a mark that clearly
  means not worked (A, X, a dash); "?" when you can't read it with confidence. If a value is crossed out and
  another written beside it, use the new one.
- total: the total written at the end of the line, as written, else "".

In notes, say briefly which boxes were hard to read, if any, and anything else the person checking should look at
(e.g. a line written in but crossed out). Use "" when there's nothing."""


def ask_claude(jpeg, code, days, printed, api_key):
    import anthropic

    client = anthropic.Anthropic(api_key=api_key)
    response = client.beta.messages.create(
        model=MODEL,
        max_tokens=16000,
        betas=["server-side-fallback-2026-07-01"],
        fallbacks="default",
        output_config={"effort": "high", "format": {"type": "json_schema", "schema": SCHEMA}},
        system=SYSTEM,
        messages=[{
            "role": "user",
            "content": [
                {"type": "image", "source": {"type": "base64", "media_type": "image/jpeg", "data": base64.standard_b64encode(jpeg).decode("ascii")}},
                {"type": "text", "text": prompt_text(code, days, printed)},
            ],
        }],
    )
    if response.stop_reason == "refusal":
        raise SheetProblem("The reader declined this photo -- check the hours by hand")
    if response.stop_reason == "max_tokens":
        raise RuntimeError("The answer was cut off (max_tokens) -- try again")
    text = next((b.text for b in response.content if b.type == "text"), None)
    if text is None:
        raise RuntimeError("No answer from the reader")
    return json.loads(text)


# --- What goes into the entry ------------------------------------------------

def _clean(cell):
    t = (cell or "").strip().replace(",", ".")
    return "" if t in ("-", "A", "X", "x", "a") else t


def build_read(answer, code, farm, group, printed, employees, days):
    """The entry's 'read': the sheet and each line, with printed lines matched
    to their workers and written-in ones to an employee with that ID number."""
    start = first_row(code)
    by_id_number = {}
    for e in employees:
        number = (e.get("id_or_passport") or "").replace(" ", "").upper()
        if number:
            by_id_number.setdefault(number, []).append(e)
    notes = [answer.get("notes", "").strip()] if answer.get("notes", "").strip() else []
    rows = []
    seen = set()
    for r in sorted(answer.get("rows", []), key=lambda r: r.get("row", 0)):
        row = int(r.get("row", 0))
        if row in seen:
            notes.append(f"row {row} read twice -- the first kept")
            continue
        seen.add(row)
        hours = [_clean(h) for h in r.get("hours", [])]
        if len(hours) != len(days):
            notes.append(f"row {row}: {len(hours)} boxes read for {len(days)} days -- check the line")
            hours = (hours + [""] * len(days))[: len(days)]
        entry = {"row": row, "hours": hours, "total": (r.get("total") or "").strip()}
        index = row - start
        if 0 <= index < len(printed):
            e = printed[index]
            entry["employee_id"] = e["id"] if e else None
            entry["name"] = employee_name(e) if e else "(no longer in the app)"
        else:
            written = " ".join(x for x in [(r.get("surname") or "").strip(), (r.get("name") or "").strip()] if x)
            number = (r.get("id_number") or "").replace(" ", "").upper()
            match = by_id_number.get(number, []) if number else []
            entry["employee_id"] = match[0]["id"] if len(match) == 1 else None
            entry["written_name"] = written
            entry["id_number"] = (r.get("id_number") or "").strip()
            if entry["employee_id"]:
                entry["name"] = employee_name(match[0])
        rows.append(entry)
    # A printed worker the reader left out: an empty line, so they're still shown.
    for i, e in enumerate(printed):
        if e and start + i not in seen:
            rows.append({"row": start + i, "employee_id": e["id"], "name": employee_name(e), "hours": [""] * len(days), "total": ""})
    rows.sort(key=lambda r: r["row"])
    return {
        "farm_id": farm["id"],
        "farm_name": farm["name"],
        "group_id": group["id"] if group else None,
        "group_name": group["name"] if group else None,
        "month": code["month"],
        "page": f"{code['page']}/{code['pages']}",
        "days": days,
        "rows": rows,
        "notes": "; ".join(notes),
        "read_at": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "model": MODEL,
    }


# --- The app -----------------------------------------------------------------

def _get(path, params):
    import requests

    resp = requests.get(f"{SUPABASE_URL}/rest/v1/{path}", headers=_auth_headers(), params=params, timeout=60)
    resp.raise_for_status()
    return resp.json()


def _save(entry_id, payload):
    import requests

    resp = requests.patch(
        f"{SUPABASE_URL}/rest/v1/capture_entries",
        headers={**_auth_headers(), "Content-Type": "application/json", "Prefer": "return=minimal"},
        # Only while it still waits: never change an entry already approved or rejected.
        params={"id": f"eq.{entry_id}", "status": "eq.pending"},
        data=json.dumps({"payload": payload}),
        timeout=60,
    )
    resp.raise_for_status()


def anthropic_key():
    key = os.environ.get("ANTHROPIC_API_KEY", "").strip()
    if not key and ANTHROPIC_KEY_FILE.exists():
        key = ANTHROPIC_KEY_FILE.read_text(encoding="utf-8").strip()
    return key


def read_entry(entry, farms, groups, employees, api_key):
    """The entry's payload with 'read' (or 'read_error') filled in."""
    payload = {k: v for k, v in (entry.get("payload") or {}).items() if k not in ("read", "read_error")}
    photos = _get("capture_photos", {"entry_id": f"eq.{entry['id']}", "select": "data"})
    try:
        if not photos:
            raise SheetProblem("The photo hasn't arrived from the phone")
        image = decode_photo(base64.b64decode(photos[0]["data"]))
        text = find_qr(image)
        if not text:
            raise SheetProblem("No QR code found -- take the photo again: the whole page, flat, sharp, in good light")
        code = parse_code(text)
        farm, group, printed = resolve(code, farms, groups, employees)
        days = sheet_days(code["first"], code["last"])
        answer = ask_claude(photo_for_claude(image), code, days, printed, api_key)
        payload["read"] = build_read(answer, code, farm, group, printed, employees, days)
    except SheetProblem as e:
        payload["read_error"] = str(e)
    return payload


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dry-run", action="store_true", help="Show what it reads; change nothing.")
    parser.add_argument("--again", action="store_true", help="Read the waiting photos again, also those read before.")
    args = parser.parse_args()

    api_key = anthropic_key()
    if not api_key:
        print("No Anthropic API key: put it in scripts\\anthropic_api_key.txt (see the top of this script).", file=sys.stderr)
        return 1
    entries = _get("capture_entries", {"module": "eq.timesheet", "status": "eq.pending", "select": "id,payload,device_name,captured_at", "order": "captured_at"})
    todo = [e for e in entries if args.again or not ({"read", "read_error"} & set((e.get("payload") or {}).keys()))]
    if not todo:
        print("No timesheet photos waiting.")
        return 0
    farms = _get("farms", {"select": "id,name"})
    groups = _get("employee_groups", {"select": "id,name,farm_id"})
    employees = _get("employees", {"select": "id,first_name,last_name,surname,id_or_passport,farm_id"})
    for entry in todo:
        when = entry.get("captured_at", "")[:16].replace("T", " ")
        try:
            payload = read_entry(entry, farms, groups, employees, api_key)
        except Exception as e:  # an API or network problem: tried again on the next run
            print(f"{when} {entry.get('device_name')}: not read this time ({e})")
            continue
        if "read_error" in payload:
            print(f"{when} {entry.get('device_name')}: {payload['read_error']}")
        else:
            r = payload["read"]
            print(f"{when} {entry.get('device_name')}: {r['farm_name']} {r['month']} page {r['page']} -- {len(r['rows'])} lines"
                  + (f" ({r['notes']})" if r["notes"] else ""))
        if not args.dry_run:
            _save(entry["id"], payload)
    return 0


if __name__ == "__main__":
    sys.exit(main())
