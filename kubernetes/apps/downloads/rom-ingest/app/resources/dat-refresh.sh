#!/bin/sh
# rom-ingest :: dat-refresh
# Weekly refresh of Logiqx/clrmamepro DAT files into the shared /dats PVC so the
# ingest gate always validates against current data. Two sources:
#   1. libretro-database  metadat/{no-intro,redump}  — cart + optical DATs
#   2. PureDOS/DAT        PureDOSDAT.xml              — DOS games (DOSBox-Pure)
# All sources are git repos so this stays fully automatic. igir parses Logiqx
# and clrmamepro regardless of file extension; PureDOS's .xml is copied as .dat.
set -u

DEST="/dats"
TMP="/tmp/dat-src"
STAGE="$DEST/.new"

# --- source config (override via env) ------------------------------------
LIBRETRO_REPO="${LIBRETRO_REPO:-https://github.com/libretro/libretro-database.git}"
# metadat/* holds the real hash-bearing No-Intro/Redump DATs (not top-level dat/).
LIBRETRO_SUBDIRS="${LIBRETRO_SUBDIRS:-metadat/no-intro metadat/redump}"
DOS_ENABLED="${DOS_ENABLED:-true}"
DOS_REPO="${DOS_REPO:-https://github.com/PureDOS/DAT.git}"
DOS_FILES="${DOS_FILES:-PureDOSDAT.xml}"

mkdir -p "$DEST"
rm -rf "$STAGE"; mkdir -p "$STAGE"

# --- source 1: libretro (sparse dirs). Use `git -C` — never cd into $TMP,
#     so a later `rm -rf $TMP` can't pull the shell's CWD out from under it.
echo "[dat-refresh] libretro: ${LIBRETRO_REPO} (${LIBRETRO_SUBDIRS})"
rm -rf "$TMP"
if git clone --depth 1 --no-checkout --filter=tree:0 "$LIBRETRO_REPO" "$TMP" \
  && git -C "$TMP" sparse-checkout init --cone \
  && git -C "$TMP" sparse-checkout set $LIBRETRO_SUBDIRS \
  && git -C "$TMP" checkout; then
  for sub in $LIBRETRO_SUBDIRS; do
    [ -d "$TMP/$sub" ] || { echo "[dat-refresh] WARN: missing $sub"; continue; }
    find "$TMP/$sub" -name '*.dat' -exec cp -f {} "$STAGE/" \;
  done
else
  echo "[dat-refresh] ERROR: libretro fetch failed"
fi
rm -rf "$TMP"

# --- source 2: PureDOS (root files, copied as .dat) ----------------------
if [ "$DOS_ENABLED" = "true" ]; then
  echo "[dat-refresh] PureDOS: ${DOS_REPO} (${DOS_FILES})"
  rm -rf "$TMP"
  if git clone --depth 1 "$DOS_REPO" "$TMP"; then
    for f in $DOS_FILES; do
      if [ -f "$TMP/$f" ]; then
        base=$(basename "$f" | sed 's/\.[Xx][Mm][Ll]$//')
        cp -f "$TMP/$f" "$STAGE/${base}.dat"
      else
        echo "[dat-refresh] WARN: PureDOS file '$f' not found"
      fi
    done
  else
    echo "[dat-refresh] WARN: PureDOS fetch failed (continuing without DOS)"
  fi
  rm -rf "$TMP"
fi

# --- swap staged DATs into place -----------------------------------------
found=$(find "$STAGE" -name '*.dat' | wc -l)
echo "[dat-refresh] staged ${found} DAT(s)"
if [ "$found" -eq 0 ]; then
  echo "[dat-refresh] ERROR: no DATs fetched — leaving existing set untouched"
  rm -rf "$STAGE"; exit 1
fi
rm -f "$DEST"/*.dat 2>/dev/null || true
mv -f "$STAGE"/*.dat "$DEST/" 2>/dev/null || true
rm -rf "$STAGE"

total=$(find "$DEST" -maxdepth 1 -name '*.dat' | wc -l)
echo "[dat-refresh] done — ${total} DAT(s) available in ${DEST}"
