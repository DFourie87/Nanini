"""Puts buffalo photos on the animals in the Buffalo app.

Each photo is named by the animal's tag ("PO20.jpg", "Tag 65.jpg"), as in
Buffalo_photos.zip. It goes to the "game-photos" storage bucket and is kept
with the animal's photos (game_photos); it becomes the animal's own photo
(the one the bloodline book shows) when it has none yet, or when it's good
enough -- at least 600 px on its short side, or about as good as the current
one (at least 80% of its size), the latest winning -- as in the app. A tag not in the register yet is added as an ancestor
(not on the farm). A photo already added (the same file) is skipped, so
this can be run again. Needs docs/sql/game_animals.sql run first.

    py scripts\\upload_buffalo_photos.py "C:\\Users\\...\\Downloads\\Buffalo_photos.zip"
"""
import argparse
import hashlib
import pathlib
import re
import struct
import sys
import zipfile

import requests

from import_sales_report import SUPABASE_URL, _auth_headers

BUCKET = "game-photos"
SPECIES = "Buffalo"
TYPES = {".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png"}
GOOD_SIDE = 600  # as GameBreedingRepository.goodPhotoSide


def image_size(data):
    """(width, height) of a JPEG or PNG from its header; (None, None) if unreadable."""
    if data[:8] == b"\x89PNG\r\n\x1a\n":
        return struct.unpack(">II", data[16:24])
    if data[:2] != b"\xff\xd8":
        return None, None
    i = 2
    while i + 9 < len(data):
        if data[i] != 0xFF:
            i += 1
            continue
        marker = data[i + 1]
        if marker in (0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
            h, w = struct.unpack(">HH", data[i + 5:i + 9])
            return w, h
        if marker == 0xFF:
            i += 1
            continue
        i += 2 + struct.unpack(">H", data[i + 2:i + 4])[0]
    return None, None


def better(w, h, old):
    """As GameBreedingRepository.betterPhoto: good enough for the book, or about as good as the current one."""
    if not old or not old.get("width") or not old.get("height"):
        return True
    if not w or not h:
        return False
    side = min(w, h)
    return side >= GOOD_SIDE or side >= 0.8 * min(old["width"], old["height"])


def storage_path(tag, data, ext):
    """Letters, digits and "-" only, plus the file's own hash: the same photo
    keeps its place, a different one gets its own."""
    safe = re.sub(r"[^A-Za-z0-9-]+", "_", tag)
    return f"{SPECIES}/{safe}-{hashlib.sha1(data).hexdigest()[:10]}{'.png' if ext == '.png' else '.jpg'}"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("folder", help="Buffalo_photos.zip, or the folder with the photos")
    ap.add_argument("--source", help='where the photos come from (kept with them), e.g. "Nanini bloodline book Oct 2026"')
    args = ap.parse_args()

    # (name, bytes) of each photo: from the folder (and folders in it), or
    # straight from Buffalo_photos.zip.
    src = pathlib.Path(args.folder)
    if not src.exists() and src.with_suffix(".zip").exists():
        src = src.with_suffix(".zip")
    if not src.exists():
        # Saved by the browser under another name ("Buffalo_photos_Eljuro (1).zip",
        # no ".zip", or unzipped to a folder): the newest one like it, in the same place.
        stem = src.stem if src.suffix.lower() == ".zip" else src.name
        like = [p for p in src.parent.glob(f"{stem}*") if p.is_dir() or p.suffix.lower() in ("", ".zip")] \
            if src.parent.is_dir() else []
        if like:
            src = max(like, key=lambda p: p.stat().st_mtime)
            print(f"Using {src}")
    photos = []
    if src.is_file() and zipfile.is_zipfile(src):
        with zipfile.ZipFile(src) as z:
            photos = [(pathlib.PurePosixPath(n).name, z.read(n)) for n in sorted(z.namelist())
                      if pathlib.PurePosixPath(n).suffix.lower() in TYPES]
    elif src.is_dir():
        photos = [(p.name, p.read_bytes()) for p in sorted(src.rglob("*")) if p.is_file() and p.suffix.lower() in TYPES]
    if not photos:
        sys.exit(f"No photos (.jpg/.png) found in {src}" + ("" if src.exists() else " -- there's no such folder or file. "
                 "Give the path of Buffalo_photos.zip or of the unzipped folder."))
    print(f"{len(photos)} photos in {src}")
    source = args.source or src.stem.replace("_", " ")

    headers = _auth_headers()
    r = requests.get(f"{SUPABASE_URL}/rest/v1/game_animals", params={"species": f"eq.{SPECIES}", "select": "id,tag,photo"},
                     headers=headers, timeout=30)
    if r.status_code == 404 or (r.status_code == 400 and "photo" in r.text):
        sys.exit("The herd register isn't ready: run docs/sql/game_animals.sql in Supabase first.")
    r.raise_for_status()
    by_tag = {a["tag"].lower(): a for a in r.json()}
    r = requests.get(f"{SUPABASE_URL}/rest/v1/game_photos", params={"species": f"eq.{SPECIES}", "select": "path,width,height"},
                     headers=headers, timeout=30)
    if r.status_code in (400, 404):
        sys.exit("The photo list isn't there yet: run the latest docs/sql/game_animals.sql in Supabase first.")
    r.raise_for_status()
    known = {p["path"]: p for p in r.json()}

    saved = used = added = again = 0
    failed = []
    for name, data in photos:
        tag, ext = pathlib.PurePath(name).stem.strip(), pathlib.PurePath(name).suffix.lower()
        animal = by_tag.get(tag.lower())
        tag = animal["tag"] if animal else tag
        path = storage_path(tag, data, ext)
        if path in known:
            again += 1
            continue
        w, h = image_size(data)
        try:
            up = requests.post(f"{SUPABASE_URL}/storage/v1/object/{BUCKET}/{path}", data=data,
                               headers={**headers, "Content-Type": TYPES[ext], "x-upsert": "true"}, timeout=120)
            if up.status_code in (400, 404) and "Bucket not found" in up.text:
                sys.exit("The photo store isn't there yet: run docs/sql/game_animals.sql in Supabase first.")
            up.raise_for_status()
            requests.post(f"{SUPABASE_URL}/rest/v1/game_photos",
                          json={"species": SPECIES, "tag": tag, "path": path, "width": w, "height": h, "source": source},
                          headers={**headers, "Prefer": "return=minimal"}, timeout=30).raise_for_status()
            known[path] = {"path": path, "width": w, "height": h}
            saved += 1
            current = animal.get("photo") if animal else None
            shown = better(w, h, known.get(current) if current else None)
            if shown:
                if animal:
                    res = requests.patch(f"{SUPABASE_URL}/rest/v1/game_animals", params={"id": f"eq.{animal['id']}"},
                                         json={"photo": path, "photo_focus_x": None, "photo_focus_y": None},
                                         headers={**headers, "Prefer": "return=minimal"}, timeout=30)
                    animal["photo"] = path
                else:
                    res = requests.post(f"{SUPABASE_URL}/rest/v1/game_animals",
                                        json={"species": SPECIES, "tag": tag, "on_farm": False, "photo": path},
                                        headers={**headers, "Prefer": "return=minimal"}, timeout=30)
                    by_tag[tag.lower()] = {"tag": tag, "photo": path, "id": None}
                    added += 1
                res.raise_for_status()
                used += 1
            print(f"  {tag}: saved" + ("" if shown else " (its current photo is better: kept)"))
        except requests.RequestException as e:
            failed.append(name)
            print(f"  {tag}: NOT saved -- {e}")

    print(f"\n{saved} photos saved, {used} now shown on their animal" + (f" ({added} new ancestors added)" if added else "")
          + (f", {saved - used} kept with the animal's other photos" if saved > used else "")
          + (f", {again} were already there" if again else "")
          + (f", NOT saved: {', '.join(failed)}" if failed else "") + ".")


if __name__ == "__main__":
    main()
