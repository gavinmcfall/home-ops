#!/usr/bin/env python3
"""Make English audio the default track in anime MKVs, in place.

Walks ROOT for .mkv files. Where an English audio track exists but is not the
only default audio track, it sets the first English audio track as default and
clears the default flag on every other audio track. Header edit only
(mkvpropedit): no remux, no re-encode.

Subtitles (SUBS):
  report - log subtitle defaults that would change, but never edit them
  apply  - when the default audio is English, make an English signs & songs
           track the default subtitle if one exists, otherwise no default
           subtitle; full English or foreign subtitle tracks lose default
  off    - ignore subtitles entirely

Skipped, never edited:
  - any path with a Pokemon folder in it (either spelling)
  - files modified less than MIN_AGE_MINUTES ago
  - files a Tdarr worker is processing right now

Environment:
  ROOT             library root (default /media/Library/Anime)
  APPLY            "true" to edit files; anything else is a dry run
  SUBS             report | apply | off (default report)
  MIN_AGE_MINUTES  default 60
  LIMIT            stop after this many changed files, 0 = no limit
  ONLY             only consider paths containing this text
  TDARR_URL        Tdarr server API base, e.g. http://tdarr:8266
  apiKey           Tdarr API key (same env name the Tdarr secret uses)

Output is one TSV line per file worth mentioning, then a SUMMARY line.
"""
import json
import os
import subprocess
import sys
import time
import unicodedata
import urllib.request

ENGLISH = {"eng", "en"}
SIGNS_WORDS = ("sign", "song")


def env(name, default=""):
    return os.environ.get(name, default).strip()


def log(kind, rel, detail=""):
    print(f"{kind}\t{rel}\t{detail}", flush=True)


def fold(text):
    """Lowercase and strip accents, so Pokémon and Pokemon match alike."""
    decomposed = unicodedata.normalize("NFKD", text)
    return "".join(c for c in decomposed if not unicodedata.combining(c)).casefold()


def is_protected(rel):
    return any("pokemon" in fold(part) for part in rel.split(os.sep))


def lang(track):
    p = track.get("properties", {})
    ietf = (p.get("language_ietf") or "").split("-")[0].lower()
    return ietf or (p.get("language") or "und").lower()


def is_default(track):
    return bool(track.get("properties", {}).get("default_track"))


def is_signs(track):
    p = track.get("properties", {})
    name = (p.get("track_name") or "").lower()
    return bool(p.get("forced_track")) or any(w in name for w in SIGNS_WORDS)


def describe(tracks):
    return ",".join(f"{lang(t)}{'*' if is_default(t) else ''}" for t in tracks)


def tdarr_busy_files():
    """Paths Tdarr workers hold right now. None if Tdarr could not be asked."""
    url = env("TDARR_URL")
    if not url:
        return None
    req = urllib.request.Request(
        url.rstrip("/") + "/api/v2/get-nodes",
        headers={"x-api-key": env("apiKey")})
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            nodes = json.load(resp)
    except Exception as exc:
        print(f"WARN\t-\tTdarr API unreachable: {exc}", flush=True)
        return None
    busy = set()
    for node in nodes.values():
        for worker in (node.get("workers") or {}).values():
            if worker.get("file"):
                busy.add(os.path.realpath(worker["file"]))
    return busy


def plan_audio(audio):
    """Return {track_number: wanted_default} for audio, or None if no change."""
    eng = [t for t in audio if lang(t) in ENGLISH]
    if not eng or len(audio) < 2:
        return None
    target = eng[0]
    if all(is_default(t) == (t is target) for t in audio):
        return None
    return {t["properties"]["number"]: t is target for t in audio}


def plan_subs(subs):
    """Return {track_number: wanted_default} for subtitles, or None."""
    if not subs:
        return None
    signs = [t for t in subs if lang(t) in ENGLISH and is_signs(t)]
    target = signs[0] if signs else None
    if all(is_default(t) == (t is target) for t in subs):
        return None
    return {t["properties"]["number"]: t is target for t in subs}


def read_tracks(path):
    out = subprocess.run(["mkvmerge", "-J", path], capture_output=True,
                         text=True, check=True).stdout
    tracks = json.loads(out).get("tracks", [])
    return ([t for t in tracks if t.get("type") == "audio"],
            [t for t in tracks if t.get("type") == "subtitles"])


def english_audio_will_be_default(audio, audio_plan):
    if audio_plan is not None:
        return True  # a plan only exists when English becomes default
    defaults = [t for t in audio if is_default(t)]
    if not defaults and len(audio) == 1:
        defaults = audio  # a lone track plays whatever its flag says
    return bool(defaults) and lang(defaults[0]) in ENGLISH


def edit(path, changes):
    cmd = ["mkvpropedit", "--quiet", path]
    for number, default in sorted(changes.items()):
        cmd += ["--edit", f"track:@{number}", "--set",
                f"flag-default={1 if default else 0}"]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode not in (0, 1):  # 1 = warnings only
        return f"{res.stdout.strip()} {res.stderr.strip()}".strip()
    return None


def verify(path, changes):
    audio, subs = read_tracks(path)
    actual = {t["properties"]["number"]: is_default(t) for t in audio + subs}
    wrong = [n for n, want in changes.items() if actual.get(n) != want]
    return wrong


def walk(root, only):
    for dirpath, dirnames, files in os.walk(root):
        dirnames.sort()
        for name in sorted(files):
            if name.lower().endswith(".mkv"):
                path = os.path.join(dirpath, name)
                if not only or only in path:
                    yield path


def main():
    root = env("ROOT", "/media/Library/Anime")
    apply = env("APPLY").lower() == "true"
    subs_mode = env("SUBS", "report").lower()
    if subs_mode not in ("report", "apply", "off"):
        sys.exit(f"SUBS must be report, apply or off, not {subs_mode!r}")
    min_age = float(env("MIN_AGE_MINUTES", "60")) * 60
    limit = int(env("LIMIT", "0") or 0)
    only = env("ONLY")

    print(f"START\t{root}\tapply={apply} subs={subs_mode} "
          f"min_age_min={min_age / 60:g} limit={limit} only={only!r}", flush=True)
    busy = tdarr_busy_files()
    if busy is None and apply:
        print("WARN\t-\tTdarr state unknown; relying on the file-age guard only",
              flush=True)

    counts = {k: 0 for k in (
        "files", "ok", "audio_fix", "subs_fix", "subs_report", "changed",
        "verify_failed", "no_english", "protected", "too_new", "tdarr_busy",
        "error")}
    changed = 0
    now = time.time()

    for path in walk(root, only):
        rel = os.path.relpath(path, root)
        counts["files"] += 1
        if is_protected(rel):
            counts["protected"] += 1
            continue
        try:
            if now - os.stat(path).st_mtime < min_age:
                counts["too_new"] += 1
                log("SKIP_TOO_NEW", rel)
                continue
            if busy and os.path.realpath(path) in busy:
                counts["tdarr_busy"] += 1
                log("SKIP_TDARR", rel)
                continue
            audio, subs = read_tracks(path)
        except Exception as exc:
            counts["error"] += 1
            log("ERROR", rel, str(exc))
            continue

        if len(audio) > 1 and not any(lang(t) in ENGLISH for t in audio):
            counts["no_english"] += 1

        audio_plan = plan_audio(audio)
        sub_plan = None
        if subs_mode != "off" and english_audio_will_be_default(audio, audio_plan):
            sub_plan = plan_subs(subs)

        changes = dict(audio_plan or {})
        detail = []
        if audio_plan:
            counts["audio_fix"] += 1
            detail.append(f"audio {describe(audio)}")
        if sub_plan:
            names = ",".join(
                f"{lang(t)}{'*' if is_default(t) else ''}"
                f"{'(signs)' if is_signs(t) else ''}" for t in subs)
            if subs_mode == "apply":
                counts["subs_fix"] += 1
                changes.update(sub_plan)
                detail.append(f"subs {names}")
            else:
                counts["subs_report"] += 1
                if not audio_plan:
                    log("SUBS_WOULD_CHANGE", rel, f"subs {names}")
                else:
                    detail.append(f"subs-report-only {names}")

        if not changes:
            if not sub_plan:
                counts["ok"] += 1
            continue
        if not apply:
            log("WOULD_CHANGE", rel, "; ".join(detail))
            continue

        err = edit(path, changes)
        if err:
            counts["error"] += 1
            log("ERROR", rel, err)
            continue
        wrong = verify(path, changes)
        if wrong:
            counts["verify_failed"] += 1
            log("VERIFY_FAILED", rel, f"tracks {wrong}")
            continue
        counts["changed"] += 1
        log("CHANGED", rel, "; ".join(detail))
        changed += 1
        if limit and changed >= limit:
            print(f"STOP\t-\treached LIMIT={limit}", flush=True)
            break

    print("SUMMARY\t-\t" + json.dumps(counts), flush=True)
    if counts["error"] or counts["verify_failed"]:
        sys.exit(1)


if __name__ == "__main__":
    main()
