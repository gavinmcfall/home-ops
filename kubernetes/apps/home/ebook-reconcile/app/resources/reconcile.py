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
# In the CWA image `/usr/bin/calibredb` is a symlink created by s6 at runtime; a
# command-override container (no s6 init) won't have it, so point at the real binary.
CALIBREDB = os.environ.get("CALIBREDB", "calibredb")
# DRY_RUN=1 prints the plan and writes nothing. Always dry-run before a bulk
# session: this job creates folders and can replace files in the live tree.
DRY = os.environ.get("DRY_RUN", "") == "1"
# Overwriting a curated tree file with Calibre's copy is a judgement about
# which edition is better, so it is opt-in rather than a silent side effect.
ALLOW_REPLACE = os.environ.get("ALLOW_REPLACE", "") == "1"
FIELDS = f"id,title,authors,series,series_index,{GENRE_FIELD},formats"


def calibredb(*args):
    return subprocess.run(
        [CALIBREDB, "--with-library", LIB, *args],
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


def _norm(s):
    """Compare titles ignoring case, punctuation and spacing.

    The tree is hand-curated and inconsistent with Calibre's strings:
    'Beyond The Veil' vs 'Beyond the Veil', 'as Told by the Boys' vs
    'As Told By The Boys'. Exact comparison would call these different books.
    """
    return re.sub(r"[^a-z0-9]+", "", (s or "").lower())


def _index_prefix(b):
    """Folder index prefix -- FALLBACK ONLY, for a book that has no folder yet.

    The old rule was int(float(idx)) zero-padded, which truncated every
    fractional index: 1.5 -> '01', and 8.0/8.5/8.6 all collapsed to '08'. The
    curated tree actually holds '1.5 - ', '5.5 - ', '8.5 - ', '8.6 - ' (yet
    '0.5' as '00 - '), so NO generated rule can reproduce it. That is precisely
    why an existing folder always wins over this.
    """
    try:
        f = float(b.get("series_index") or 0)
    except (TypeError, ValueError):
        f = 0.0
    return f"{int(f):02d}" if f == int(f) else f"{f:g}"


def _match_child(parent_abs, title, want_dir=True):
    """Return the existing child of parent_abs whose name means `title`, else None.

    Book folders are '<index> - <Title>'; the index prefix is stripped before
    comparing so a differing prefix never masks a book we already own.
    """
    want = _norm(title)
    try:
        entries = sorted(os.listdir(parent_abs))
    except OSError:
        return None
    for e in entries:
        full = os.path.join(parent_abs, e)
        if want_dir and not os.path.isdir(full):
            continue
        if not want_dir and not e.lower().endswith(".epub"):
            continue
        name = e if want_dir else os.path.splitext(e)[0]
        m = re.match(r"^\s*\d+(?:\.\d+)?\s*-\s*(.+)$", name)
        if _norm(m.group(1) if m else name) == want:
            return e
    return None


def rel_path(b):
    """Prefer the folder/file this book ALREADY occupies; only invent a path
    when it genuinely has none. Generating a path unconditionally is what
    scattered 16 duplicate folders -- a book whose generated name disagreed with
    its real one was silently treated as new rather than as an error."""
    genre = sanitize(b.get(GENRE_FIELD) or "")
    author = sanitize(b.get("authors") or "")
    title = sanitize(b.get("title") or "")
    series = (b.get("series") or "").strip()
    if not (genre and author and title):
        return None
    parts = [genre, author] + ([sanitize(series)] if series else [])
    parent_abs = os.path.join(DEST, *parts)
    folder = _match_child(parent_abs, title) or (
        f"{_index_prefix(b)} - {title}" if series else title)
    fname = _match_child(os.path.join(parent_abs, folder), title,
                         want_dir=False) or f"{title}.epub"
    return os.path.join(*parts, folder, fname)


def epub_of(b):
    for p in (b.get("formats") or []):
        if p.lower().endswith(".epub"):
            return p
    return None


def main():
    books = json.loads(calibredb(
        "list", "--search", f'tag:"{TAG}"', "--fields", FIELDS, "--for-machine") or "[]")
    state = load_state()
    linked = relinked = moved = skipped = ok = conflicts = 0

    for b in books:
        bid, rp, src = str(b["id"]), rel_path(b), epub_of(b)
        if not rp or not src or not os.path.exists(src):
            print(f"SKIP id={bid} '{b.get('title')}' (missing genre/author/title/epub) -> review")
            skipped += 1
            continue
        dst = os.path.join(DEST, rp)
        prev = state.get(bid)

        if prev and prev != dst and os.path.lexists(prev):       # metadata moved the path
            if not DRY:
                os.remove(prev)
                try:
                    os.removedirs(os.path.dirname(prev))
                except OSError:
                    pass
            moved += 1
            print(f"MOVED id={bid}: removed stale {prev}"
                  f"{'  (DRY RUN - not removed)' if DRY else ''}")

        if not os.path.lexists(dst):
            colocated = os.path.isdir(os.path.dirname(dst))
            tag = 'colocated' if colocated else 'NEW FOLDER'
            print(f"LINK   id={bid} -> {rp}  [{tag}]")
            if not DRY:
                os.makedirs(os.path.dirname(dst), exist_ok=True)
                os.link(src, dst)
            linked += 1
        elif os.stat(dst).st_ino != os.stat(src).st_ino:
            dsz, ssz = os.stat(dst).st_size, os.stat(src).st_size
            # Two very different situations, previously indistinguishable because
            # generated paths never landed on a curated file:
            #   prev == dst -> WE linked this before and Calibre's file changed
            #                  (re-convert / embed). Re-linking is correct.
            #   otherwise   -> a file WE NEVER PLACED already occupies this path.
            #                  It is the curated tree copy, and which edition is
            #                  better is a human judgement, not a cronjob's.
            if prev == dst or ALLOW_REPLACE:
                print(f"RELINK id={bid} (file changed) -> {rp}  "
                      f"tree={dsz:,}B calibre={ssz:,}B"
                      f"{'  (DRY RUN - not written)' if DRY else ''}")
                if not DRY:
                    os.remove(dst)
                    os.link(src, dst)
                relinked += 1
            else:
                print(f"CONFLICT id={bid} -> {rp}  tree={dsz:,}B calibre={ssz:,}B"
                      f"  — pre-existing file not placed by us; left untouched "
                      f"(set ALLOW_REPLACE=1 to overwrite)")
                conflicts += 1
                continue          # do NOT record state for a path we did not write
        else:
            ok += 1
            print(f"OK     id={bid} (current)")
        state[bid] = dst

    if not DRY:
        save_state(state)
    print(f"\ndone{' (DRY RUN — nothing written)' if DRY else ''}: {len(books)} {TAG} book(s) | "
          f"linked={linked} relinked={relinked} moved={moved} ok={ok} "
          f"skipped={skipped} conflicts={conflicts}")


if __name__ == "__main__":
    main()
