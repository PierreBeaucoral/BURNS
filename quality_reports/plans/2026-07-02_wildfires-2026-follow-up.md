# Plan — BURNS: Summer 2026 follow-up + project overhaul

**Status:** APPROVED (user: "implement all", Fable orchestrates, cheaper agents code)
**Date:** 2026-07-02

## Objective
Turn the one-off 2025 wildfires post into a reusable, year-parameterized season tracker;
produce the Summer 2026 follow-up with upgraded analyses; publish as a Quarto website
with weekly auto-refresh scaffolding.

## Phases

### Phase 1 — Reusable pipeline (foundation)
1. `R/` helper package-style folder extracted from the monolithic qmd:
   - `R/helpers.R` (to_num, parse_date_any, lab_si_ha)
   - `R/geo.R` (Europe polygons, country tagging by max overlap, summer filter fn)
   - `R/flags.R` (flag fetch + dominant color, deduplicated — was copy-pasted 3x)
   - `R/cache.R` (disk-cache wrapper for expensive geometry ops)
2. `scripts/fetch_effis.R` — download current EFFIS burnt-area product, snapshot to
   `DATA/snapshots/YYYY-MM-DD/`, pin per post. (DATA/ is currently EMPTY — post is
   not reproducible; this fixes it permanently.)
3. Year as a Quarto parameter; no hardcoded 2025/2026 in analysis code.

### Phase 2 — 2026 follow-up content
4. Envelope chart: cumulative 2026 burned area vs 2008–2025 min–max band + median.
5. Normalized country rankings (% of national land area, alongside raw ha).
6. Recurrence analysis: 2026 scars ∩ prior-year scars (2017/2022/2023/2025) — new land
   vs re-burn; Aude/France callout.
7. Dumbbell 2026 vs 2025 headline comparison (2017 kept as benchmark).
8. Keep/port: hero map, monthly facets, daily timeline, land-cover composition.

### Phase 3 — Impact multipliers
9. Quarto website project (index = live tracker, per-year post pages), GitHub Pages
   ready + GitHub Action for weekly re-render during fire season (Jun–Sep).
10. Interactive leaflet map (perimeters + date/area on hover).
11. Climate-driver panel: FWI/temperature anomaly IF a no-auth data source is feasible;
    otherwise documented deferral (no API-key dependencies).

## Constraints
- Coding delegated to Sonnet-tier agents; Fable orchestrates + reviews.
- No git push / deploy without explicit user confirmation (scaffold only).
- INV compliance: no install.packages() in scripts, relative paths, seeds, notes on figs.
- EFFIS product must be re-verified (MODIS→Sentinel-2 transition since Sept 2025).

## Verification
- `scripts/fetch_effis.R` runs, snapshot present, schema validated.
- Full site renders via `quarto render` without error.
- coder-critic review ≥ 80 before declaring done.
