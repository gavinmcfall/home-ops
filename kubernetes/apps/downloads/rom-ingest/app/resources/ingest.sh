#!/bin/sh
# rom-ingest :: ingest gate
# Validate freshly-downloaded ROMs against DATs BEFORE they enter the RomM
# library. Matched files are promoted into roms/<slug>/; everything else is
# quarantined for manual review. RomM's filesystem-change watch imports the
# promoted files automatically.
set -u

# BRACE-FREE (use $VAR, not the dollar-brace form): Flux post-build
# substitution rewrites dollar-brace tokens inside the ConfigMap.
# IGIR_VERSION/DISCORD_WEBHOOK come from env.
DATS_GLOB="/dats/*.dat"
LIBRARY="/media/Library/Emulation/roms"
BASE="/media/Downloads/rom-ingest"
WORK="$BASE/work"
QUARANTINE="$BASE/quarantine"
STAGING="/media/Downloads/sabnzbd/complete/roms /media/Downloads/qbittorrent/complete/roms"
WEBHOOK="$DISCORD_WEBHOOK"

log() { echo "[rom-ingest] $*"; }

notify() {
  [ -z "$WEBHOOK" ] && return 0
  msg=$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g')
  wget -q -O- --header="Content-Type: application/json" \
    --post-data="{\"username\":\"ROM Gate\",\"content\":\"$msg\"}" \
    "$WEBHOOK" >/dev/null 2>&1 || log "discord notify failed"
}

# --- preconditions -------------------------------------------------------
if [ -z "$(find /dats -maxdepth 2 -name '*.dat' 2>/dev/null | head -1)" ]; then
  log "no DAT files in /dats yet — has dat-refresh run? aborting run."
  exit 0
fi

mkdir -p "$WORK" "$QUARANTINE" "$LIBRARY"
cd "$WORK" || exit 1

# --- collect non-empty staging inputs -----------------------------------
INPUTS=""
for d in $STAGING; do
  if [ -d "$d" ] && [ -n "$(ls -A "$d" 2>/dev/null)" ]; then
    INPUTS="$INPUTS --input $d"
  fi
done
if [ -z "$INPUTS" ]; then
  log "nothing staged. done."
  exit 0
fi

# --- validate + move matched ROMs into WORK, organised by DAT name -------
log "validating staged ROMs against DATs (igir $IGIR_VERSION)..."
# igir moves recognised ROMs to --output (extracting them from any archive);
# anything it does not recognise is left in the input dirs (swept to
# quarantine below).
npx --yes "igir@$IGIR_VERSION" move extract report \
  --dat "$DATS_GLOB" \
  $INPUTS \
  --output "$WORK" \
  --dir-dat-name \
  --report-output "$WORK/report.csv" \
  2>&1 | tail -50 || log "igir exited non-zero (continuing to sweep)"

# --- map DAT-name folders -> RomM platform slug and promote --------------
map_slug() {
  case "$1" in
    *"Game Boy Advance"*)                echo gba ;;
    *"Game Boy Color"*)                  echo gbc ;;
    *"Game Boy"*)                        echo gb ;;
    *"Super Nintendo"*|*"Super Famicom"*) echo snes ;;
    *"Nintendo 64"*)                     echo n64 ;;
    *"Nintendo DS"*)                     echo nds ;;
    *"Nintendo 3DS"*|*"New Nintendo 3DS"*) echo 3ds ;;
    *"Nintendo Entertainment System"*|*"Famicom"*) echo nes ;;
    *"GameCube"*)                        echo ngc ;;
    *"Master System"*|*"Mark III"*)      echo sms ;;
    *"Mega Drive"*|*"Genesis"*)          echo genesis ;;
    *"Dreamcast"*)                       echo dc ;;
    *"PlayStation Portable"*)            echo psp ;;
    *"PlayStation Vita"*)                echo psvita ;;
    *"PlayStation 2"*)                   echo ps2 ;;
    *"PlayStation 3"*)                   echo ps3 ;;
    *"PlayStation"*)                     echo psx ;;
    *"Xbox 360"*|*"XBOX 360"*)           echo xbox360 ;;
    *"Xbox"*|*"XBOX"*)                   echo xbox ;;
    *"Pure DOS"*|*"DOS Games"*)          echo dos ;;
    *) echo "" ;;
  esac
}

promoted=0
unmapped=0
for sysdir in "$WORK"/*/; do
  [ -d "$sysdir" ] || continue
  name=$(basename "$sysdir")
  slug=$(map_slug "$name")
  n=$(find "$sysdir" -type f | wc -l)
  [ "$n" -eq 0 ] && { rmdir "$sysdir" 2>/dev/null || true; continue; }
  if [ -n "$slug" ]; then
    mkdir -p "$LIBRARY/$slug"
    find "$sysdir" -mindepth 1 -maxdepth 1 -exec mv -f {} "$LIBRARY/$slug/" \; 2>/dev/null || true
    promoted=$((promoted + n))
    log "promoted $n file(s): $name -> roms/$slug"
  else
    mkdir -p "$QUARANTINE/_unmapped/$name"
    find "$sysdir" -mindepth 1 -maxdepth 1 -exec mv -f {} "$QUARANTINE/_unmapped/$name/" \; 2>/dev/null || true
    unmapped=$((unmapped + n))
    log "no slug mapping for '$name' -> quarantine/_unmapped ($n file(s))"
  fi
  rmdir "$sysdir" 2>/dev/null || true
done

# --- sweep anything igir did NOT recognise into quarantine ---------------
mkdir -p "$QUARANTINE/_unmatched"
for d in $STAGING; do
  [ -d "$d" ] || continue
  find "$d" -type f 2>/dev/null | while IFS= read -r f; do
    mv -f "$f" "$QUARANTINE/_unmatched/" 2>/dev/null || true
  done
  find "$d" -mindepth 1 -type d -empty -delete 2>/dev/null || true
done
unmatched=$(find "$QUARANTINE/_unmatched" -type f 2>/dev/null | wc -l)

summary="ROM gate: promoted $promoted, unmapped $unmapped, quarantined(unmatched) $unmatched"
log "$summary"
if [ "$promoted" -gt 0 ] || [ "$unmapped" -gt 0 ] || [ "$unmatched" -gt 0 ]; then
  notify "$summary"
fi
exit 0
