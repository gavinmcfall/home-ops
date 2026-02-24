# Session Journal

This file maintains running context across compactions.

## Current Focus

- Star Citizen Sanguine Volt Parallax render — fixed wear texture blend, awaiting re-render verification

## Recent Changes

- Fixed render script (`/tmp/sc_render/render_sanguine.py`) — removed wear texture inversion + HAL_R multiplication that crushed blend factor to ~0.05 (chrome everywhere). Now uses wear texture directly as blend factor (bright=base/paint, dark=wear/metal)
- Updated both pipeline docs with color space corrections and PaletteTint mapping fixes
- Three bugs total found and fixed: (1) sRGB→linear gamma on palette values, (2) A/B swap in Mix nodes, (3) wear texture inversion

## Key Decisions

- Wear texture convention: white=pristine/protected (base layer visible), black=worn (bare metal visible) — confirmed by stats (mean=224.7, 92% above 128; a new weapon should be mostly pristine)
- Palette values: divide by 255 only, NO gamma correction
- PaletteTint mapping: 0=no palette (use static TintColor), 1→A, 2→B, 3→C

## Important Context

- Render script at `/tmp/sc_render/render_sanguine.py` — all three fixes applied, needs re-render to verify
- Two pipeline docs at `/mnt/e/Star Citizen Data/Rendered/` (not in home-ops repo)
- Render outputs go to `/mnt/c/tmp/sc_render/` on Windows side

---
**Session compacted at:** 2026-02-17 19:14:34


---
**Session compacted at:** 2026-02-20 10:41:44


---
**Session compacted at:** 2026-02-20 12:20:05


---
**Session compacted at:** 2026-02-21 06:44:26


---
**Session compacted at:** 2026-02-21 07:22:28


---
**Session compacted at:** 2026-02-23 14:44:59


---
**Session compacted at:** 2026-02-23 19:58:36


---
**Session compacted at:** 2026-02-23 20:31:40


---
**Session compacted at:** 2026-02-23 20:43:57


---
**Session compacted at:** 2026-02-23 20:48:04


---
**Session compacted at:** 2026-02-23 21:12:31


---
**Session compacted at:** 2026-02-24 07:02:34


---
**Session compacted at:** 2026-02-24 07:59:17


---
**Session compacted at:** 2026-02-24 09:15:43


---
**Session compacted at:** 2026-02-24 10:15:49

