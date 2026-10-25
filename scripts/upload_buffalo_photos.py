"""Puts a folder of buffalo photos on the animals in the Buffalo app.

Each photo is named by the animal's tag ("PO20.jpg", "Tag 65.jpg"), as in
Buffalo_photos.zip. It goes to the "game-photos" storage bucket and onto
that animal in the herd register (game_animals); a tag not in the register
yet is added as an ancestor (not on the farm). Animals that already have a
photo keep it, unless --replace. Needs docs/sql/game_animals.sql run first.

    py scripts\\upload_buffalo_photos.py "C:\\Users\\...\\Buffalo_photos"
"""
import argparse
import hashlib
import pathlib
import re
import sys

import requests

from import_sales_report import SUPABASE_URL, _auth_headers

BUCKET = "game-photos"
SPECIES = "Buffalo"
TYPES = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png"}


def storage_path(tag, ext):
    """Letters, digits and "-" only, plus a short hash so "Tag 65" and
    "Tag_65" stay apart."""
    safe = re.sub(r"[^A-Za-z0-9-]+", "_", tag)
    short = hashlib.sha1(tag.encode("utf-8")).hexdigest()[:6]
    return f"{SPECIES}/{safe}-{short}{'.png' if ext == '.png' else '.jpg'}"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folder", help="the folder with the photos (unzipped Buffalo_photos.zip)")
    ap.add_argument("--replace", action="store_true", help="also replace photos animals already have")
    args = ap.parse_args()

    folder = pathlib.Path(args.folder)
    files = sorted(p for p in folder.iterdir() if p.suffix.lower() in TYPES) if folder.is_dir() else []
    if not files:
        sys.exit(f"No photos (.jpg/.png) found in {folder}")

    headers = _auth_headers()
    r = requests.get(f"{SUPABASE_URL}/rest/v1/game_animals", params={"species": f"eq.{SPECIES}", "select": "id,tag,photo"},
                     headers=headers, timeout=30)
    if r.status_code == 404 or (r.status_code == 400 and "photo" in r.text):
        sys.exit("The herd register isn't ready: run docs/sql/game_animals.sql in Supabase first.")
    r.raise_for_status()
    by_tag = {a["tag"].lower(): a for a in r.json()}

    saved = kept = added = 0
    failed = []
    for f in files:
        tag = f.stem.strip()
        animal = by_tag.get(tag.lower())
        if animal and animal.get("photo") and not args.replace:
            kept += 1
            continue
        path = storage_path(animal["tag"] if animal else tag, f.suffix.lower())
        try:
            up = requests.post(f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{path}", data=f.read_bytes(),
                               headers={**headers, "Content-Type": TYPES[f.suffix.lower()], "x-upsert": "true"}, timeout=120)
            if up.status_code in (400, 404) and "Bucket not found" in up.text:
                sys.exit("The photo store isn't there yet: run docs/sql/game_animals.sql in Supabase first.")
            up.raise_for_status()
            if animal:
                res = requests.patch(f"{SUPABASE_URL}/rest/v1/game_animals", params={"id": f"eq.{animal['id']}"},
                                     json={"photo": path}, headers={**headers, "Prefer": "return=minimal"}, timeout=30)
            else:
                res = requests.post(f"{SUPABASE_URL}/rest/v1/game_animals",
                                    json={"species": SPECIES, "tag": tag, "on_farm": False, "photo": path},
                                    headers={**headers, "Prefer": "return=minimal"}, timeout=30)
                added += 1
            res.raise_for_status()
            # An older photo of this animal under another name: no longer needed.
            old = animal.get("photo") if animal else None
            if old and old != path:
                requests.delete(f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{old}", headers=headers, timeout=30)
            saved += 1
            print(f"  {tag}: saved")
        except requests.RequestException as e:
            failed.append(f.name)
            print(f"  {tag}: NOT saved -- {e}")

    print(f"\n{saved} photos saved" + (f" ({added} new ancestors added)" if added else "")
          + (f", {kept} animals already had a photo (kept; --replace to change them)" if kept else "")
          + (f", NOT saved: {', '.join(failed)}" if failed else "") + ".")


if __name__ == "__main__":
    main()
