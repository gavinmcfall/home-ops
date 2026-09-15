#!/bin/bash
# Nightly incremental metadata bake: embed Calibre DB metadata into the library
# files themselves. Covers every edit path (CWA UI, calibredb CLI, bulk sessions)
# unlike CWA's UI-only enforcement hook.
#
# WHY NOT `calibredb embed_metadata`: Calibre 9.x Cache.embed_metadata returns,
# instead of continuing, when a book has no cover to copy, and the CLI prints
# "Processed" and exits 0 regardless. Every coverless book was therefore skipped
# on every run (19 of 4,136 on 2026-09-15). This job calls
# calibre.ebooks.metadata.epub.set_metadata per book instead, and judges each
# write by re-reading the OPF: dc:subject must equal the book's tags. A write
# that does not verify is rolled back from its backup and reported.
#
# Scope: the Calibre library ONLY (this pod mounts nothing else). Propagation to
# the genre tree is a deliberate manual step (propagate + promote), never this job's.
#
# Window: 2 days overlapping, idempotent. EMBED_DRY=1 verifies without writing.
#
# STYLE CONSTRAINT: no dollar-brace expansions anywhere in this file, comments
# included -- Flux's post-build envsubst runs over the ConfigMap and treats
# every dollar-brace token as a substitution variable ("bad substitution"
# broke the whole Kustomization). Bare $VAR is safe; brace expansion is not.
set -e

if [ -z "$LIB" ]; then echo "embed-nightly: LIB not set" >&2; exit 1; fi
if [ -z "$CALIBREDB" ]; then CALIBREDB=/app/calibre/calibredb; fi
CALIBRE_DEBUG=$(dirname "$CALIBREDB")/calibre-debug
CUTOFF=$(date -d '2 days ago' +%Y-%m-%d)

ids=$("$CALIBREDB" search "last_modified:\">=$CUTOFF\"" --library-path "$LIB" 2>/dev/null || true)
if [ -z "$ids" ]; then
  echo "embed-nightly: no books modified since $CUTOFF - nothing to do"
  exit 0
fi
count=$(printf '%s' "$ids" | awk -F, '{print NF}')
echo "embed-nightly: embedding $count book(s) modified since $CUTOFF: $ids"

# Plain loops only inside the calibre-debug script: it runs with separate
# globals and locals, so a name used inside a comprehension does not resolve.
"$CALIBRE_DEBUG" -e /dev/stdin -- "$LIB" "$ids" "$EMBED_DRY" <<'PY'
import sys, os, re, html, json, zipfile, shutil
from calibre.library import db
from calibre.ebooks.metadata.epub import set_metadata
lib_path, id_csv, dry = sys.argv[-3], sys.argv[-2], sys.argv[-1] == '1'
lib = db(lib_path).new_api

def subjects_of(path):
    z = zipfile.ZipFile(path)
    container = z.read('META-INF/container.xml').decode('utf-8', 'replace')
    opf = re.search(r'full-path="([^"]+)"', container).group(1)
    raw = z.read(opf).decode('utf-8', 'replace')
    z.close()
    out = []
    for t in re.findall(r'<dc:subject[^>]*>([^<]*)</dc:subject>', raw):
        out.append(html.unescape(t).strip())
    out.sort()
    return out

written = verified_already = restored = skipped = 0
for tok in id_csv.split(','):
    i = int(tok)
    has = False
    for f in (lib.formats(i) or []):
        if f.upper() == 'EPUB':
            has = True
    if not has:
        skipped += 1
        continue
    p = lib.format_abspath(i, 'EPUB')
    tags = sorted(lib.field_for('tags', i) or ())
    try:
        if subjects_of(p) == tags:
            verified_already += 1
            continue
    except Exception as e:
        print('embed-nightly: %d unreadable before write: %s' % (i, str(e)[:100]))
        skipped += 1
        continue
    if dry:
        print('embed-nightly: DRY would write %d (%s)' % (i, lib.field_for('title', i)))
        written += 1
        continue
    bak = p + '.pre-embed-nightly'
    shutil.copy2(p, bak)
    mi = lib.get_metadata(i, get_cover=False)
    with open(p, 'r+b') as fh:
        set_metadata(fh, mi, apply_null=False, update_timestamp=False, force_identifiers=False)
    ok = False
    try:
        ok = zipfile.ZipFile(p).testzip() is None and subjects_of(p) == tags
    except Exception:
        ok = False
    if ok:
        os.remove(bak)
        written += 1
    else:
        shutil.copy2(bak, p)
        os.remove(bak)
        restored += 1
        print('embed-nightly: %d write did NOT verify, restored (%s)' % (i, lib.field_for('title', i)))
print('embed-nightly: written=%d already-current=%d restored=%d no-epub=%d' % (written, verified_already, restored, skipped))
if restored:
    sys.exit(1)
PY
echo "embed-nightly: done"
