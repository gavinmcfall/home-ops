#!/bin/sh
# rom-ingest :: dat-refresh
# Weekly refresh of Logiqx/clrmamepro DAT files into the shared /dats PVC so the
# ingest gate always validates against current data. Two sources:
#   1. libretro-database  metadat/{no-intro,redump}  — cart + optical DATs
#   2. PureDOS/DAT        PureDOSDAT.xml              — DOS games (DOSBox-Pure)
#
# IMPORTANT: this script is intentionally BRACE-FREE (use $VAR, not the
# dollar-brace form). Flux post-build substitution rewrites dollar-brace
# tokens inside the ConfigMap and would blank our shell variables. All config
# comes from the HelmRelease env.
set -u

DEST=/dats
TMP=/tmp/dat-src
STAGE=$DEST/.new

mkdir -p "$DEST"
rm -rf "$STAGE"; mkdir -p "$STAGE"

# --- source 1: libretro (sparse dirs). Use `git -C` — never cd into $TMP,
#     so a later `rm -rf $TMP` can't pull the shell's CWD out from under it.
echo "[dat-refresh] libretro: $LIBRETRO_REPO ($LIBRETRO_SUBDIRS)"
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
  echo "[dat-refresh] PureDOS: $DOS_REPO ($DOS_FILES)"
  rm -rf "$TMP"
  if git clone --depth 1 "$DOS_REPO" "$TMP"; then
    for f in $DOS_FILES; do
      if [ -f "$TMP/$f" ]; then
        base=$(basename "$f" | sed 's/\.[Xx][Mm][Ll]$//')
        cp -f "$TMP/$f" "$STAGE/$base.dat"
      else
        echo "[dat-refresh] WARN: PureDOS file '$f' not found"
      fi
    done
  else
    echo "[dat-refresh] WARN: PureDOS fetch failed (continuing without DOS)"
  fi
  rm -rf "$TMP"
fi

# --- drop non-physical / digital-distribution DATs -----------------------
# These describe multi-file digital packages and contain 0-byte and generic
# component files with well-known hashes that false-match real ROMs (e.g. a
# 0-byte .ARC matching a PSN DLC entry). No use for a physical-dump gate.
for pat in '(PSN)' '(PSX2PSP)' '(UMD Music)' '(UMD Video)' '(Download Play)' '(Digital)' '(Games on Demand)' '(Title Updates)'; do
  find "$STAGE" -name "*$pat*.dat" -type f -delete 2>/dev/null || true
done

# --- swap staged DATs into place -----------------------------------------
found=$(find "$STAGE" -name '*.dat' | wc -l)
echo "[dat-refresh] staged $found DAT(s)"
if [ "$found" -eq 0 ]; then
  echo "[dat-refresh] ERROR: no DATs fetched — leaving existing set untouched"
  rm -rf "$STAGE"; exit 1
fi
rm -f "$DEST"/*.dat 2>/dev/null || true
mv -f "$STAGE"/*.dat "$DEST/" 2>/dev/null || true
rm -rf "$STAGE"

total=$(find "$DEST" -maxdepth 1 -name '*.dat' | wc -l)
echo "[dat-refresh] done — $total DAT(s) available in $DEST"
