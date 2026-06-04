#!/usr/bin/env bash
# =============================================================================
# Dune Awakening dedicated-server images  ->  zot registry
# =============================================================================
# Downloads the Funcom self-hosted server depot via SteamCMD and pushes the
# OCI image tarballs to our zot registry. Works in two contexts:
#   - Workstation (first run, interactive: type the Steam Guard code from your
#     phone once; the session is cached under ~/Steam afterwards).
#   - In-cluster CronJob (headless: session restored from 1Password — see
#     cronjob.yaml + RUNBOOK-image-pull.md).
#
# Funcom's registry.funcom.com is INTERNAL-ONLY (not public DNS), so the images
# ship as tarballs inside the Steam depot — this script re-homes them in zot.
#
# Requires: steamcmd, skopeo (or crane), find, tar.  No secrets are hardcoded.
# =============================================================================
set -euo pipefail

: "${STEAM_USER:?set STEAM_USER (your Steam account that owns the game)}"
: "${ZOT_REGISTRY:?set ZOT_REGISTRY host, no scheme, e.g. zot.example.com}"
: "${ZOT_USER:=admin}"
: "${ZOT_PASS:?set ZOT_PASS (zot admin password)}"

DUNE_APPID="${DUNE_APPID:-4754530}"          # live self-hosted server tool (PTC=3104830)
INSTALL_DIR="${INSTALL_DIR:-$HOME/dune-server-depot}"
STEAMCMD="${STEAMCMD:-steamcmd}"             # path to steamcmd / steamcmd.sh
REPO_PREFIX="${REPO_PREFIX:-funcom/self-hosting}"
DUNE_TAG="${DUNE_TAG:-}"                     # <build>-0-shipping; autodetected if empty
PUSH="${PUSH:-1}"                            # set PUSH=0 to stop after recon

# image short-name -> tag.  igw-postgres has a fixed tag; the rest use DUNE_TAG.
declare -A FIXED_TAG=( [igw-postgres]="17.4-alpine-fc-13" )
IMAGES=(
  seabass-server
  igw-postgres
  seabass-server-rabbitmq
  seabass-server-db-utils
  seabass-server-bg-director
  seabass-server-text-router
  seabass-server-gateway
)

log() { printf '\n==> %s\n' "$*"; }

# --- 1. download -------------------------------------------------------------
log "[1/4] Downloading Dune dedicated-server depot (app ${DUNE_APPID}) -> ${INSTALL_DIR}"
# First run prompts for password + Steam Guard code (from your phone). Cached after.
"${STEAMCMD}" +force_install_dir "${INSTALL_DIR}" \
  +login "${STEAM_USER}" \
  +app_update "${DUNE_APPID}" validate \
  +quit

# --- 2. reconnaissance -------------------------------------------------------
log "[2/4] Reconnaissance — depot layout (exact structure is not publicly documented)"
echo "--- top level ---"; ls -la "${INSTALL_DIR}" || true
echo "--- candidate image archives ---"
mapfile -t ARCHIVES < <(find "${INSTALL_DIR}" -type f \
  \( -name '*.tar' -o -name '*.tar.gz' -o -name '*.tgz' -o -name '*.oci' \) 2>/dev/null | sort)
printf '%s\n' "${ARCHIVES[@]:-(none found)}"
echo "--- VHDX / disk images (if images live ONLY inside the VM, we extract differently) ---"
find "${INSTALL_DIR}" -type f \( -iname '*.vhdx' -o -iname '*.img' -o -iname '*.qcow2' \) 2>/dev/null || true
echo "--- build id (from Steam app manifest) ---"
grep -h '"buildid"' "${INSTALL_DIR}"/steamapps/appmanifest_"${DUNE_APPID}".acf 2>/dev/null || echo "(no appmanifest)"

# autodetect DUNE_TAG from a tarball name like *-0-shipping if not provided
if [[ -z "${DUNE_TAG}" ]]; then
  DUNE_TAG="$(printf '%s\n' "${ARCHIVES[@]:-}" | grep -oE '[0-9]+-0-shipping' | head -1 || true)"
fi
echo "--- resolved DUNE_TAG: ${DUNE_TAG:-<UNKNOWN — set DUNE_TAG explicitly>} ---"

if [[ "${PUSH}" != "1" ]]; then
  log "PUSH=0 set — stopping after recon. Review the output above."
  exit 0
fi

# --- 3. push to zot ----------------------------------------------------------
log "[3/4] Pushing images to ${ZOT_REGISTRY}/${REPO_PREFIX}/*"
command -v skopeo >/dev/null || { echo "skopeo not found — install it or adapt to 'crane push'"; exit 1; }

push_one() {
  local name="$1" tag="$2" archive="$3"
  local dest="docker://${ZOT_REGISTRY}/${REPO_PREFIX}/${name}:${tag}"
  echo ">> ${name}:${tag}  <-  ${archive}"
  skopeo copy --dest-creds "${ZOT_USER}:${ZOT_PASS}" \
    "docker-archive:${archive}" "${dest}"
}

missing=0
for name in "${IMAGES[@]}"; do
  tag="${FIXED_TAG[$name]:-${DUNE_TAG}}"
  [[ -z "${tag}" ]] && { echo "!! ${name}: no tag (set DUNE_TAG) — skipping"; missing=1; continue; }
  # auto-discover the archive whose name contains the image short-name
  archive="$(printf '%s\n' "${ARCHIVES[@]:-}" | grep -E "/${name}[^/]*\.(tar|tar\.gz|tgz|oci)$" | head -1 || true)"
  if [[ -z "${archive}" ]]; then
    echo "!! ${name}: no matching archive in depot — recon output above shows what exists; adjust mapping. Skipping."
    missing=1; continue
  fi
  push_one "${name}" "${tag}" "${archive}"
done

# --- 4. done -----------------------------------------------------------------
if [[ "${missing}" == "1" ]]; then
  log "[4/4] FINISHED WITH GAPS — some images had no auto-matched tarball. Use the recon"
  echo "    output to map the real filenames, then re-run (or push them manually with skopeo)."
  exit 1
fi
log "[4/4] All images pushed to zot. Verify:  skopeo list-tags docker://${ZOT_REGISTRY}/${REPO_PREFIX}/seabass-server"
