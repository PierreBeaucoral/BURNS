# BURNS: Europe Wildfire Season Tracker

A Quarto website tracking the European wildfire season from **EFFIS rapid
perimeters** (satellite-mapped burn-scar polygons, typically ≥ ~30–50 ha).
During fire season (June–September) the site refreshes weekly: a fetch script
snapshots the latest perimeters, and the tracker page re-renders charts of
where it burned, how much, when, and what land cover burned, with burned
areas computed from polygon geometry in an equal-area projection (EPSG:3035)
and country attribution by maximum border overlap.

The project grew out of the original one-off post
[`wildfires-europe-2025-local.qmd`](wildfires-europe-2025-local.qmd), the
Summer 2025 season analysis, which remains the reference for the methodology.

## Quickstart

```r
# 0) One-time setup: rnaturalearthhires is not on CRAN (r-universe only),
#    and is required for the Europe reference polygons in R/geo.R.
install.packages("rnaturalearthhires", repos = "https://ropensci.r-universe.dev")
```

```bash
# 1) Fetch the latest EFFIS snapshot, gate on completeness, and render
scripts/update_site.sh

# 2) Publish, once you're happy with the rendered site (separate, explicit step)
quarto publish gh-pages --no-prompt
```

The rendered site is written to `_site/`. `scripts/update_site.sh` fetches
2016 through the current year, aborts if any year's `ba_<year>.geojson` is
missing from today's snapshot, then runs `quarto render` (also aborting on a
nonzero exit). It never publishes on its own -- publishing to GitHub Pages is
always a separate command you run yourself. See `scripts/update_site.sh`
`--no-fetch` to re-render an already-fetched snapshot.

## Weekly refresh flow (local, not CI)

This project **does not** render or fetch data via GitHub Actions. During
fire season (June–September), refresh the site weekly by running
`scripts/update_site.sh` locally, checking the rendered `_site/` output, and
then running `quarto publish gh-pages --no-prompt` yourself. Why local
instead of CI:

- **EFFIS's WFS server is too flaky for unattended CI fetching.** Uncapped
  requests hang indefinitely and paged requests intermittently 502/500;
  `scripts/fetch_effis.R` compensates with forced HTTP/1.1, retries, and
  per-page timeouts (see that script's header for the verified server
  facts), which is manageable interactively but not safe to leave unattended
  on a CI schedule.
- **The raw data is too heavy for the repo.** Per-year EFFIS GeoJSON
  snapshots run from a few MB to over 100 MB each; `DATA/snapshots/` is
  git-ignored and re-fetched locally instead.
- **`rnaturalearthhires` is not on CRAN.** It ships only from the ropensci
  r-universe (see Quickstart above), which complicates an automated CI
  install.

## Directory layout

```
.
├── _quarto.yml          # website configuration
├── index.qmd            # live tracker page (current season)
├── about.qmd            # project description, data caveats, disclaimer
├── R/                   # shared helper library (helpers, geo, flags, cache, theme)
├── scripts/              # pipeline scripts: fetch_effis.R, update_site.sh, latest_snapshot.R
├── DATA/snapshots/      # dated EFFIS data snapshots (git-ignored, re-fetchable)
└── posts/               # frozen season posts (2025 post moves here later)
```

## Data source & attribution

Fire perimeter data: **EFFIS** (European Forest Fire Information System),
part of the **Copernicus Emergency Management Service**. For data licensing
and conditions of use, see the EFFIS terms. EFFIS rapid perimeters are
estimates from satellite mapping and differ from official national fire
statistics; see the [About](about.qmd) page for caveats.

## Author

Pierre Beaucoral
