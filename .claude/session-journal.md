# Session Journal

This file maintains running context across compactions.

## Current Focus

- Fixed session journal — added instructions for Claude to maintain this file

## Recent Changes

- Added rule 17 (Maintain the Session Journal) to global `~/.claude/CLAUDE.md`
- Added Session Journal section with update triggers, content guide, and conventions
- Reset this journal from stale compaction-only timestamps to clean template

## Key Decisions

- Session journal instructions live globally (not per-project) since `init-project.sh` creates journals everywhere
- Update frequency: after each significant task (not continuous, not end-of-session only)
- Journal is a snapshot of NOW, not a history log — replace content, don't append endlessly

## Important Context

- PreCompact hook (`~/.claude/hooks/session-journal.sh`) handles timestamps and trimming automatically
- SessionStart compact hook reads journal back after compaction via `cat`
- The shell hooks can't write meaningful content — only Claude can, driven by the CLAUDE.md instructions

---
**Session compacted at:** 2026-02-17 19:14:34


---
**Session compacted at:** 2026-02-20 10:41:44


---
**Session compacted at:** 2026-02-20 12:20:05

