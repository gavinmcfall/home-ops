#!/bin/bash
# Nightly incremental metadata bake: embed Calibre DB metadata into the library
# files themselves (calibredb embed_metadata). Covers every edit path — CWA UI,
# calibredb CLI, bulk sessions — unlike CWA's UI-only enforcement hook.
#
# Scope: the Calibre library ONLY (this pod mounts nothing else). Propagation to
# the genre tree is the reconcile job's business (hardlink re-link on inode
# change) or a deliberate manual bake-sync — never this job's.
#
# Window: 2 days overlapping, idempotent (re-embedding an already-baked book is
# a no-op byte-wise apart from a fresh rewrite).
set -euo pipefail

LIB="${LIB:?LIB (library path) must be set}"
CALIBREDB="${CALIBREDB:-/app/calibre/calibredb}"
CUTOFF=$(date -d '2 days ago' +%Y-%m-%d)

ids=$("$CALIBREDB" search "last_modified:\">=${CUTOFF}\"" --library-path "$LIB" 2>/dev/null || true)
if [ -z "$ids" ]; then
  echo "embed-nightly: no books modified since ${CUTOFF} — nothing to do"
  exit 0
fi

# calibredb search returns comma-separated ids; embed_metadata wants them as args
read -r -a id_args <<< "${ids//,/ }"
echo "embed-nightly: embedding ${#id_args[@]} book(s) modified since ${CUTOFF}: ${ids}"
"$CALIBREDB" embed_metadata "${id_args[@]}" --library-path "$LIB"
echo "embed-nightly: done"
