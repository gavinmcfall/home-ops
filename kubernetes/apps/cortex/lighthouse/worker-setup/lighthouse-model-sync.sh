#!/usr/bin/env bash
# Lighthouse worker model auto-fetch (ADR 018, task #40).
# Pulls the tier-filtered manifest from model-serve, fetches missing/changed
# files into the local ComfyUI models dir (resumable), and verifies sha256.
# Config: /etc/lighthouse-worker.conf with MASTER, TOKEN, TIER, MODELS_DIR.
set -euo pipefail

CONF=/etc/lighthouse-worker.conf
# shellcheck disable=SC1090
source "$CONF" # MASTER=10.99.8.215:9090  TOKEN=...  TIER=heavy|light  MODELS_DIR=/home/<u>/ComfyUI/models
: "${MASTER:?}" "${TOKEN:?}" "${TIER:?}" "${MODELS_DIR:?}"

AUTH=(-H "Authorization: Bearer $TOKEN")
BASE="http://$MASTER"

log() { echo "[model-sync] $*"; }

manifest=$(curl -fsS "${AUTH[@]}" "$BASE/models/manifest?tier=$TIER")
count=$(jq length <<<"$manifest")
log "manifest: $count files for tier=$TIER"

fetched=0 skipped=0 failed=0
while IFS=$'\t' read -r path size; do
  dest="$MODELS_DIR/$path"
  if [[ -f "$dest" && $(stat -c%s "$dest") -eq $size ]]; then
    skipped=$((skipped + 1))
    continue
  fi
  log "fetch: $path ($size bytes)"
  mkdir -p "$(dirname "$dest")"
  # -C - resumes a partial download; --fail-with-body so 404 ≠ success.
  if ! curl -fsS -C - "${AUTH[@]}" -o "$dest.part" "$BASE/models/$path"; then
    log "ERROR: download failed: $path"
    failed=$((failed + 1))
    continue
  fi
  want=$(curl -fsS "${AUTH[@]}" "$BASE/models/sha256/$path" | jq -r .sha256)
  got=$(sha256sum "$dest.part" | awk '{print $1}')
  if [[ "$want" != "$got" ]]; then
    log "ERROR: sha256 mismatch for $path (want $want got $got) — discarding"
    rm -f "$dest.part"
    failed=$((failed + 1))
    continue
  fi
  mv "$dest.part" "$dest"
  fetched=$((fetched + 1))
done < <(jq -r '.[] | [.path, (.size | tostring)] | @tsv' <<<"$manifest")

log "done: fetched=$fetched skipped=$skipped failed=$failed"
[[ $failed -eq 0 ]] || exit 1
