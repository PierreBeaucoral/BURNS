# BURNS — Europe Wildfire Season Tracker

A Quarto website tracking the European wildfire season from **EFFIS rapid
perimeters** (satellite-mapped burn-scar polygons, typically ≥ ~30–50 ha).
During fire season (June–September) the site refreshes weekly: a fetch script
snapshots the latest perimeters, and the tracker page re-renders charts of
where it burned, how much, when, and what land cover burned — with burned
areas computed from polygon geometry in an equal-area projection (EPSG:3035)
and country attribution by maximum border overlap.

The project grew out of the original one-off post
[`wildfires-europe-2025-local.qmd`](wildfires-europe-2025-local.qmd) — the
Summer 2025 season analysis — which remains the reference for the methodology.

## Quickstart

```bash
# 1) Fetch the latest EFFIS data (script lands in a later phase)
Rscript scripts/fetch_effis.R

# 2) Render the website
quarto render
```

The rendered site is written to `_site/`. The scaffold renders without any
data — the tracker page shows placeholders until a snapshot exists.

## Directory layout

```
.
├── _quarto.yml          # website configuration
├── index.qmd            # live tracker page (current season)
├── about.qmd            # project description, data caveats, disclaimer
├── R/                   # shared helper library (helpers, geo, flags, cache, theme)
├── scripts/             # pipeline scripts (fetch_effis.R — coming)
├── DATA/snapshots/      # dated EFFIS data snapshots (git-ignored, re-fetchable)
├── posts/               # frozen season posts (2025 post moves here later)
└── .github/workflows/   # weekly render & deploy action (June–September)
```

## Data source & attribution

Fire perimeter data: **EFFIS** (European Forest Fire Information System),
part of the **Copernicus Emergency Management Service**. For data licensing
and conditions of use, see the EFFIS terms. EFFIS rapid perimeters are
estimates from satellite mapping and differ from official national fire
statistics; see the [About](about.qmd) page for caveats.

## Author

Pierre Beaucoral
