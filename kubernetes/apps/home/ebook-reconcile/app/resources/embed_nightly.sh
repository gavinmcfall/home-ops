#!/bin/bash
# Nightly incremental metadata bake: embed Calibre DB metadata into the library
# files themselves (calibredb embed_metadata). Covers every edit path — CWA UI,
# calibredb CLI, bulk sessions — unlike CWA's UI-only enforcement hook.
#
# Scope: the Calibre library ONLY (this pod mounts nothing else). Propagation to
# the genre tree is the reconcile job's business (hardlink re-link on inode
# change) or a deliberate manual bake-sync — never this job's.
#
# Window: 2 days overlapping, idempotent.
#
# STYLE CONSTRAINT: no dollar-brace expansions anywhere in this file, comments
# included — Flux's post-build envsubst runs over the ConfigMap and treats
# every dollar-brace token as a substitution variable ("bad substitution"
# broke the whole Kustomization). Bare $VAR is safe; brace expansion is not.
set -e

if [ -z "$LIB" ]; then echo "embed-nightly: LIB not set" >&2; exit 1; fi
if [ -z "$CALIBREDB" ]; then CALIBREDB=/app/calibre/calibredb; fi
CUTOFF=$(date -d '2 days ago' +%Y-%m-%d)

ids=$("$CALIBREDB" search "last_modified:\">=$CUTOFF\"" --library-path "$LIB" 2>/dev/null || true)
if [ -z "$ids" ]; then
  echo "embed-nightly: no books modified since $CUTOFF - nothing to do"
  exit 0
fi

# calibredb search returns comma-separated ids; embed_metadata wants args
ids_spaced=$(printf '%s' "$ids" | tr ',' ' ')
count=$(echo "$ids_spaced" | wc -w)
echo "embed-nightly: embedding $count book(s) modified since $CUTOFF: $ids"
# shellcheck disable=SC2086 — word-splitting is intended
"$CALIBREDB" embed_metadata $ids_spaced --library-path "$LIB"
echo "embed-nightly: done"
