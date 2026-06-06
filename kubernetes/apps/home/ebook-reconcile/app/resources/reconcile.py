#!/usr/bin/env python3
"""Reconcile curated ebooks from a Calibre library into the AudiobookShelf
folder structure via HARDLINKS — idempotent.

For every book tagged `→abs` (the review gate), compute its ABS path
(`<Genre>/<Author>/<Series>/<NN - Title>/<Title>.epub`) and hardlink Calibre's
epub there. Same dataset → nlink=2, one physical copy, zero extra bytes, and
Calibre retains the book.

- New book          -> link
- File replaced     -> inode mismatch -> re-link  (re-convert/re-embed in Calibre)
- In-place edit     -> same inode -> ABS already current, no action
- Metadata path move-> state says old path -> remove old hardlink, link new
- Unchanged         -> skip

Reads metadata via `calibredb` (handles locking + custom columns + format
paths). Keeps its own state file (book id -> last dst) so it never writes to
Calibre's metadata.db.

Env: LIB, DEST, STATE (default /state/abs_paths.json), TAG (default →abs).
"""
import json
import os
import re
import subprocess

LIB = os.environ["LIB"]
DEST = os.environ["DEST"]
STATE = os.environ.get("STATE", "/state/abs_paths.json")
TAG = os.environ.get("TAG", "→abs")
GENRE_FIELD = os.environ.get("GENRE_FIELD", "*genre")
FIELDS = f"id,title,authors,series,series_index,{GENRE_FIELD},formats"


def calibredb(*args):
    return subprocess.run(
        ["calibredb", "--with-library", LIB, *args],
        capture_output=True, text=True, check=True,
    ).stdout


def sanitize(s):
    """Filesystem-safe, matching how the existing folders are named."""
    s = re.sub(r'[/:*?"<>|]', "_", s)
    return re.sub(r"\s+", " ", s).strip()


def load_state():
    try:
        with open(STATE) as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def save_state(st):
    os.makedirs(os.path.dirname(STATE) or ".", exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(st, f, indent=2, ensure_ascii=False)
    os.replace(tmp, STATE)


def rel_path(b):
    genre = sanitize(b.get(GENRE_FIELD) or "")
    author = sanitize(b.get("authors") or "")
    title = sanitize(b.get("title") or "")
    series = (b.get("series") or "").strip()
    if not (genre and author and title):
        return None
    if series:
        s = sanitize(series)
        nn = f'{int(float(b.get("series_index") or 0)):02d}'
        return os.path.join(genre, author, s, f"{nn} - {title}", f"{title}.epub")
    return os.path.join(genre, author, title, f"{title}.epub")


def epub_of(b):
    for p in (b.get("formats") or []):
        if p.lower().endswith(".epub"):
            return p
    return None


def main():
    books = json.loads(calibredb(
        "list", "--search", f'tag:"{TAG}"', "--fields", FIELDS, "--for-machine") or "[]")
    state = load_state()
    linked = relinked = moved = skipped = ok = 0

    for b in books:
        bid, rp, src = str(b["id"]), rel_path(b), epub_of(b)
        if not rp or not src or not os.path.exists(src):
            print(f"SKIP id={bid} '{b.get('title')}' (missing genre/author/title/epub) -> review")
            skipped += 1
            continue
        dst = os.path.join(DEST, rp)
        prev = state.get(bid)

        if prev and prev != dst and os.path.lexists(prev):       # metadata moved the path
            os.remove(prev)
            try:
                os.removedirs(os.path.dirname(prev))
            except OSError:
                pass
            moved += 1
            print(f"MOVED id={bid}: removed stale {prev}")

        if not os.path.lexists(dst):
            colocated = os.path.isdir(os.path.dirname(dst))
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            os.link(src, dst)
            linked += 1
            print(f"LINK   id={bid} -> {rp}  [{'colocated' if colocated else 'new folder'}]")
        elif os.stat(dst).st_ino != os.stat(src).st_ino:
            os.remove(dst)
            os.link(src, dst)
            relinked += 1
            print(f"RELINK id={bid} (file changed) -> {rp}")
        else:
            ok += 1
            print(f"OK     id={bid} (current)")
        state[bid] = dst

    save_state(state)
    print(f"\ndone: {len(books)} {TAG} book(s) | "
          f"linked={linked} relinked={relinked} moved={moved} ok={ok} skipped={skipped}")


if __name__ == "__main__":
    main()
