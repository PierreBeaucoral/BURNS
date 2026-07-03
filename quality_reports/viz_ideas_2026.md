# Visualization ideas — 2026 season page (ideation memo)

**Date:** 2026-07-02 (snapshot `DATA/snapshots/2026-07-03/`)
**Scope:** NEW visualizations only — not restyles of the envelope, hero map, leaflet, top-10 bars, re-burn map, or land-cover composition already on `posts/2026.qmd`.
**Ground rules applied throughout:** archive starts 2016; MODIS→Sentinel-2 shift (~2024) makes fire COUNTS incomparable across years; rapid perimeters miss fires < ~30–50 ha; 2026 has ~4 weeks of summer data (plus an unusually busy Jan–May).

## Data probes run for this memo (facts the ideas rely on)

Probed `ba_2026.geojson` (10,346 features) directly:

- **`FIREDATE` carries a time-of-day for every feature** — but the hour histogram peaks at 09:00–12:00 UTC and 23:00–00:00. That is the **satellite overpass schedule** (Sentinel-2 ~10:30 local descending; night-time detections cluster at 23–01), *not* ignition time. Any "when in the day do fires start?" chart would be a chart of orbital mechanics. Flagged below wherever relevant.
- **`FINALDATE` is populated (10,345/10,346)**; duration `FINALDATE − FIREDATE` has median **0.57 h** (single-detection fires) and mean 19 h, max ~52 days. It is a *detection span*, usable only for large multi-pass fires.
- **`PERCNA2K` (share of perimeter inside Natura 2000 protected sites) is populated and untapped**: 25.5 % of 2026 perimeters have a nonzero value; unweighted mean 23.4 %.
- **Size concentration is extreme**: in 2026 to date, the largest 1 % of perimeters hold **30.8 %** of total mapped area (median perimeter 11 ha, p99 471 ha, max 7,191 ha).
- Cache already holds: country-tagged perimeters for Jun–Sep 2017–2025 (full windows *and* same-window Jun 1–Jul 3 cuts), full-year 2026 tagged, the 2017–2025 unioned footprint, the envelope object. `tag_countries()` preserves **all** EFFIS attribute columns (incl. `PERCNA2K`, `province`, `commune`, land-cover shares), so most ideas below read straight from cached `.rds`.

Compute-cost vocabulary: *trivial* = seconds from existing cache; *cached-once* = one expensive pass (minutes), then cached `.rds`; *heavy* = tens of minutes or external downloads.

---

## (a) Time & rhythm

### 1. The fire-year calendar — "When does Europe actually burn?"

- **Reader's question:** Is fire a summer thing, or does Europe burn all year round?
- **Sketch:** Heatmap grid — x = week of year (1–52), y = year (2016–2026), fill = weekly burned area (binned log scale, e.g. viridis `magma`). One glance shows the July–August furnace, the February–April agricultural-burning band, and 2026's anomalous bright winter-spring row that the current post only mentions in text. Annotate the 2026 row's cutoff week.
- **Data check:** Snapshot only. `FIREDATE` + `AREA_HA` per year, 2016–2026; needs full-year reads of `ba_<y>.geojson` for 2016–2025 (currently only summer windows cached) — one pass, then cache the tiny weekly tibble (~52×11 rows). Europe-clip optional but recommended for consistency (reuse `tag_countries` or just `st_filter(eu$union)`).
- **Honesty:** Uses AREA not counts, so the detection shift mostly washes out; still add one caption line that post-2024 rows include small fires earlier years miss (a modest area effect, big count effect). Keep 2016 in but mark it as partial-quality (consistent with the post's convention of excluding it from the band).
- **Feasibility:** ggplot2 `geom_tile`; compute cached-once (~5–10 min first render reading ~450 MB of GeoJSON); page weight = one PNG.
- **Impact 8 / Effort 4.** The single best "context" chart the site doesn't have.
- **When: NOW** — it explains the post's own Jan–May surprise, and the 2026 row being partial is visually self-evident.

### 2. Two fire regimes — agricultural spring vs forest summer

- **Reader's question:** Why was there so much fire in February–April? Is that the same phenomenon as summer wildfires?
- **Sketch:** Two smoothed seasonal curves (weekly burned area, pooled 2017–2025, mean or median across years), one for perimeters whose dominant land cover is **agricultural**, one for **forest/shrub** (broadleaved+conifer+mixed+scleroph+transit). Agricultural fire should peak in late winter/spring (stubble and pasture burning), forest fire in July–August. Overlay 2026-to-date as points or a partial line on each panel. Two-panel patchwork or one panel, two colors from `pal_lc` logic.
- **Data check:** Snapshot only. Land-cover shares × `AREA_HA` × week(`FIREDATE`), full-year reads 2017–2025 (same pass as idea 1 — build them together, one cache). Dominant-LC assignment already implemented in the leaflet chunk (`max.col` on the lc matrix).
- **Honesty:** Area-weighted, pooled across years — the detection shift adds many small agri fires in 2024–25, so pool medians rather than sums, or show 2017–2023 vs 2024–2025 as two line styles if the shift visibly distorts. Say explicitly: "these are two different human phenomena, not one."
- **Feasibility:** ggplot2 only; cached-once (shares idea 1's pass); one PNG.
- **Impact 8 / Effort 4.** Genuinely pedagogic — most readers don't know Europe has *two* fire seasons; it reframes the post's headline number.
- **When: NOW.**

### 3. Season speed — "On what date did each year reach 2026's current total?"

- **Reader's question:** 2026 has burned X ha — how fast is that compared to past years?
- **Sketch:** Minimal dot-on-timeline chart: one row per year 2017–2025, a dot on the calendar date when that year's cumulative Jun-window (or Jan-window) burned area crossed today's 2026 total, plus a vertical reference line at 3 July. Years to the left of the line were faster; right = slower. A stripped-down, more shareable derivative of the envelope — a single number per year instead of nine curves.
- **Data check:** Snapshot only; fully computable from the **already-cached** envelope object (`hist_daily` has `cum_ha` × `day_idx` × year). Choose window: Jun-window matches the envelope; a Jan 1-anchored variant would credit 2026's spring, but requires the full-year pass (bundle with idea 1).
- **Honesty:** Pure area comparison; inherits the envelope's honesty. Caption: crossing dates shift as 2026's total grows — chart is a snapshot.
- **Feasibility:** trivial (envelope cache), `geom_point` + `geom_vline`; one small PNG.
- **Impact 6.5 / Effort 2.** Cheap, quotable ("2022 hit this total by 18 June; 2018 never did").
- **When: NOW.**

### 4. Diurnal / day-of-week patterns — **anti-idea, do not build naively**

- **Reader's question it *seems* to answer:** What time of day do fires start? Do weekends burn more (human ignition)?
- **Why the naive version misleads:** verified above — `FIREDATE` time-of-day is the satellite overpass time (09–12 UTC + 23–01 UTC bimodal in both counts and area). A "fires per hour" chart would be a beautiful, viral, *wrong* chart of Sentinel-2's orbit. Day-of-week is also contaminated: revisit cadence + cloud gaps alias detections across days.
- **Honest version, if ever:** ignition-time analysis needs an *active-fire* product (VIIRS/MODIS FIRMS hotspots, free CSV from NASA FIRMS archive download / API key) with its own overpass caveats, or national ignition databases (e.g., France's BDIFF, Spain's EGIF). That's a separate post, not a snapshot chart. Day-of-week on `FIREDATE` at daily resolution *might* survive for large fires only, but the payoff/risk ratio is poor.
- **Recommendation:** park it; optionally one caveat sentence in the post ("the data can't tell us the hour a fire started — here's why"), which is itself good pedagogy.
- **Impact n/a / Effort n/a. When: NEVER (as naive), SEPTEMBER+ external-data post (as honest).**

### 5. How long do big fires stay active? (detection-span anatomy)

- **Reader's question:** Are the monster fires over in a day, or do they burn for weeks?
- **Sketch:** Scatter/beeswarm for fires ≥ 500 ha (2017–2026): x = detection span in days (`FINALDATE − FIREDATE`), y = final `AREA_HA` (log), colored by country for the top few countries. Annotate the extremes (the 52-day 2026 fire). Alternative encoding: horizontal segments on a calendar (Gantt-style) for the 20 largest 2026 fires, segment = FIREDATE→FINALDATE, thickness = area.
- **Data check:** Snapshot only: `FIREDATE`, `FINALDATE`, `AREA_HA`. Both fields verified present. **Restrict to ≥ 500 ha**: below that, median span is 0.57 h (one overpass) and the chart would be a wall at zero.
- **Honesty:** Caption must say "days between first and last satellite mapping of the perimeter," not "fire duration" — rapid mapping can lag ignition and extinction. The ≥ 500 ha filter also neutralizes the detection shift (large fires detected in all years).
- **Feasibility:** trivial from cached tagged objects (FINALDATE preserved) + one full-year hist pass if multi-year (bundle with idea 1); ggplot2/ggrepel.
- **Impact 6 / Effort 3. When: SEPTEMBER** (mid-season truncation bias: long-lived fires still burning are censored — honest version needs the season closed, or a "still active" marker).

---

## (b) Space beyond choropleths

### 6. Is fire creeping north? The latitude of burning, 2016–2026

- **Reader's question:** Is the fire zone moving toward northern Europe, or is that just headlines?
- **Sketch:** Area-weighted latitude distribution of burned area per year: a ridgeline (one density ridge per year, weight = clipped `area_ha`, y = latitude of perimeter centroid) or, more sober, a line chart of the area-weighted p50 and p90 latitude by year with a shaded interquartile band. If the p90 line trends north, that's the story; if it doesn't, publishing the flat line is exactly the site's honest brand.
- **Data check:** Snapshot only. Centroid latitude: `st_centroid()` on tagged geometries, transform to 4326, take Y. Years 2016–2026, full-year windows (bundle the pass with idea 1). No external data.
- **Honesty:** MUST be area-weighted — the post-2024 small-fire flood is geographically broad and would drag unweighted distributions around. For the NOW version, compare like-for-like windows (Jan 1–Jul 3 of each year), otherwise 2026 lacks its summer-Mediterranean mass and will look spuriously northern. Caveat: 11 years is short for "trend" talk — frame as "where the burning was," not climate attribution.
- **Feasibility:** ggridges (tiny extra dep) or pure ggplot2 quantile lines; cached-once; one PNG.
- **Impact 8.5 / Effort 4.** "The fire frontier is/isn't moving north" is a shareable, quotable finding either way.
- **When: NOW with same-window framing; refresh in SEPTEMBER with full seasons.**

### 7. Where fire keeps coming back — decade recurrence hex map

- **Reader's question:** Are the same places burning again and again?
- **Sketch:** Hexbin map of Europe (~25 km hexes, EPSG:3035): fill = number of distinct **years** (2016–2026) in which any perimeter intersected the hex. A `magma`/`inferno` sequential scale makes chronic-fire country (northern Portugal, Galicia, southern Italy, Peloponnese) glow against one-off territory. Complements — doesn't duplicate — the existing re-burn map: that one shows exact 2026-on-old-scars overlap; this shows the decade's structural geography.
- **Data check:** Snapshot only. `st_make_grid(square = FALSE)` over the EU union, `st_intersects` per year, count distinct years per hex. All years 2016–2026 (bundle pass with idea 1).
- **Honesty:** "Distinct years burned" is a count-flavored statistic — the detection shift adds small fires in 2024–2026 that can light up new hexes. Honest version: **restrict to perimeters ≥ 100 ha** (uniform threshold detectable in all years) OR fill by "years in which ≥ 500 ha burned in the hex." State the threshold in the caption.
- **Feasibility:** sf + ggplot2 `geom_sf`; cached-once (spatial joins over ~85k polygons — minutes); one PNG (or a leaflet layer later).
- **Impact 8 / Effort 5.
- **When: NOW** (2026's partial year barely affects a decade-scale map; caption notes it).

### 8. Fires at the edge of towns — the artificial-surface interface (WUI proxy)

- **Reader's question:** Are fires reaching places where people live?
- **Sketch:** Two-part figure. Left: share of each year's burned area in perimeters that contain **any artificial surface** (`ARTIFSURF > 0`), 2017–2026 — a proxy for wildland-urban-interface contact. Right: map of 2026 perimeters colored by `ARTIFSURF` share, dots sized by area, so readers see *which* fires touched built-up land (likely the shareable half).
- **Data check:** Snapshot-only version uses `ARTIFSURF` (CORINE-derived share inside each perimeter) — already in every cached tagged object. A *true* WUI distance analysis needs external data: **GHSL GHS-BUILT-S** (JRC, free GeoTIFF download from the GHSL data portal, 100 m grid) — compute perimeter-to-built-up distance with `terra`+`sf`. Recommend the internal proxy first.
- **Honesty:** `ARTIFSURF > 0` on small perimeters is noisy CORINE mixing; use area-weighted share of artificial land burned, not "% of fires touching towns" (count-flavored + shift-contaminated). Restrict trend panel to ≥ 100 ha perimeters.
- **Feasibility:** proxy version trivial/cached-once, ggplot2 + patchwork; GHSL version heavy (multi-GB raster). Page weight: one PNG.
- **Impact 7 / Effort 3 (proxy) or 8 (GHSL). When: NOW (proxy), SEPTEMBER (GHSL if the proxy finds a story).**

---

## (c) Fire-level anatomy

### 9. A few monsters do most of the damage — size-concentration chart

- **Reader's question:** Is the season made of thousands of small fires, or a handful of giants?
- **Sketch:** Left panel: Lorenz-style concentration curve for 2026 (x = share of fires, smallest→largest; y = cumulative share of burned area), annotated at the verified fact: **"the largest 1 % of fires account for 31 % of the area"** (and largest 10 % ≈ most of it). Right panel: all 2026 perimeters as a one-dot-per-fire strip (log area axis), the top-10 labeled. An economist's chart (it's a Gini) explained in fire terms — on-brand for the author.
- **Data check:** Snapshot only — `area_ha` from cached `tagged_2026_full`. Fact pre-verified in the probe above.
- **Honesty:** Within-2026 statement, fully immune to the detection shift *within the year* — but say that the ≥30–50 ha floor means the true count of small fires is higher, so concentration is if anything **understated**. Do NOT plot a cross-year "number of fires" trend next to it.
- **Feasibility:** trivial (one cached rds, `cumsum` on sorted areas); ggplot2 + patchwork; one PNG.
- **Impact 7.5 / Effort 2.** The 1 %/31 % line is a ready-made social-media sentence.
- **When: NOW.**

### 10. Gallery of scars — the ten biggest fires of 2026, drawn to the same scale

- **Reader's question:** What does a 7,000-hectare fire actually look like?
- **Sketch:** Small-multiples "specimen sheet": the true perimeter geometry of the 10 largest 2026 fires, each in its own panel on a common metric scale (shared coord limits per panel width, EPSG:3035), fill = dominant land cover (`pal_lc`), panel label = "Commune, Country — dd Mon — N,NNN ha". One ghost reference shape in the corner of panel 1: the footprint of **Paris intra-muros (~10,500 ha)** drawn at the same scale, so every scar is instantly readable as "×0.7 of Paris". Ordered largest→smallest so the size decay is visible.
- **Data check:** Snapshot only: geometry, `AREA_HA`, `COMMUNE`/`PROVINCE`, lc shares from cached `tagged_2026_full`. Paris outline: a simple 10.5 kha circle avoids any external fetch (honest label: "area of Paris, drawn as a circle"); or `rnaturalearth` urban polygons if available offline.
- **Honesty:** No cross-year claim at all — purely descriptive of named 2026 events. Caption: rapid perimeters are provisional and revised.
- **Feasibility:** trivial; ggplot2 facets with fixed `coord_sf` extents (the only fiddly bit: equal panel windows — compute a common bbox side = max scar extent ×1.1 and center each scar); one PNG.
- **Impact 8.5 / Effort 3.** Concrete named places + "the size of Paris" = the most shareable cheap chart available; also gives the Aude-origin narrative named French entries if any qualify.
- **When: NOW** (and re-render trivially in September — the gallery updates itself).

### 11. The decade's champions — biggest fire of each year, 2016–2026

- **Reader's question:** Is the *biggest* fire getting bigger?
- **Sketch:** Eleven perimeter shapes in a row (one per year, common scale, same treatment as idea 10), height of an accompanying bar = that fire's ha. The eye compares monsters across a decade — Pedrógão Grande 2017 vs Evros 2023 vs whatever 2026 produces.
- **Data check:** Snapshot only; needs the full-year pass (bundle with idea 1) then `slice_max(area_ha)` per year. Careful: take the largest *single perimeter*, and note that EFFIS sometimes splits/merges complexes (the 2020 file has one >200 MB multipolygon — check it isn't a merged complex before crowning it).
- **Honesty:** Maximum-of-year is robust to the detection shift (the biggest fire was always detectable). The one real risk is perimeter-merging artifacts — eyeball each champion.
- **Feasibility:** cached-once; ggplot2; one PNG.
- **Impact 7.5 / Effort 4. When: SEPTEMBER** (2026's champion isn't crowned yet; mid-season version would be instantly stale).

---

## (d) Land cover & ecology

### 12. National fire fingerprints — what burns in each country

- **Reader's question:** Does "wildfire" mean the same thing in Portugal, Greece, and Romania?
- **Sketch:** Small-multiple 100 % stacked bars (or a country × land-cover heatmap): pooled 2017–2025 area-weighted land-cover composition of burned area for the ~12 most fire-affected countries, sorted by forest-share. Expect: Portugal/Spain = forest+scleroph; Romania/Bulgaria/Serbia = heavily agricultural; Greece = scleroph. This turns the existing single-comparison LC chart into a *typology of national fire regimes* — and quietly explains why "burned area" alone mis-ranks countries.
- **Data check:** Snapshot only: lc share columns × `area_ha` × `name_long`, pooled over cached Jun–Sep tagged objects (fully cached already) — or full-year for the honest agri picture (spring burning is *outside* Jun–Sep; use the idea-1 pass). Prefer full-year.
- **Honesty:** Area-weighted shares are shift-robust. Note CORINE classes are static-ish (land cover, not what the flames did). Pooling years avoids single-year weirdness.
- **Feasibility:** trivial-to-cached-once; ggplot2, existing `pal_lc`; one PNG.
- **Impact 7 / Effort 3. When: NOW.**

### 13. Burning the family silver — fire inside Natura 2000 protected areas

- **Reader's question:** How much of the burning is happening inside Europe's protected natural sites?
- **Sketch:** Headline stat + two panels. Compute protected-burned area as `Σ area_ha × PERCNA2K/100`. Panel A: share of burned area inside Natura 2000, per year 2017–2026 (same-window Jan 1–Jul 3 for the NOW version), as a lollipop series with 2026 highlighted. Panel B: map of 2026 perimeters colored by `PERCNA2K` (0 → grey, 100 → deep green/purple), so readers see *which* scars are protected-area fires.
- **Data check:** Snapshot only — `PERCNA2K` verified populated (25.5 % of 2026 perimeters nonzero, unweighted mean 23.4 %); preserved in all cached tagged objects. Cross-year panel needs the same-window caches (already exist for Jun 1–Jul 3; a Jan-anchored version needs the idea-1 pass). One TODO for the coder: sanity-check the field's definition against EFFIS docs (percentage of burnt area inside Natura 2000 sites) and confirm it's populated in the 2017–2019 files too before promising the trend panel.
- **Honesty:** Area-weighted by construction. Caveat that Natura 2000 includes fire-adapted habitats where fire is not automatically "destruction" — the pedagogic voice should say so; also the site network itself grew slightly over the decade (minor).
- **Feasibility:** trivial (fields already in cache) + ggplot2/patchwork map; one PNG.
- **Impact 8 / Effort 3.** Nobody else is showing this from EFFIS's own field; "X % of this year's burned land is protected nature" is a strong, honest headline.
- **When: NOW** (with the definition check); richer in SEPTEMBER.

---

## (e) Signature visualization

### 14. The Fire Spiral — a decade of European burning on one clock face

- **Reader's question:** Can I *see* ten years of fire seasons at once — and where 2026 is on the clock?
- **Sketch:** Radial "climate-spiral" chart (the Ed Hawkins genre, which is precisely the format that makes sites known): angle = day of year (Jan at 12 o'clock), radius = year (2016 inner → 2026 outer), and each year drawn as a ring whose thickness/color intensity encodes weekly burned area (`magma` on log area). Ten rings of pulsing July–August heat, the faint spring band of agricultural burning at 2–4 o'clock every year, and the 2026 outer ring conspicuously hot *early* and then stopping dead at the 3-July mark — the unfinished ring is itself the honest "season in progress" statement. Ship both: a static PNG (shareable, printable) and a gganimate version that draws the spiral year by year (GIF/mp4, autoplay muted).
- **Data check:** Snapshot only: week(`FIREDATE`) × year × Σ clipped `area_ha`, 2016–2026 — exactly the same tiny aggregate as idea 1 (the spiral is idea 1's calendar bent into a circle; build both from one cached tibble).
- **Honesty:** Area, not counts — shift-safe by design. Caption: 2016 partial-quality; radial charts distort (outer rings get more ink per datum) — mitigate by encoding value in **color/thickness only**, never in radial length; keep the linear calendar (idea 1) on the page as the sober companion so no one has to decode the spiral to get the facts.
- **Feasibility:** ggplot2 `coord_polar` (or `geom_rect` + `coord_radial` in ggplot2 ≥ 3.5) + gganimate/gifski, all installed. Compute trivial once the idea-1 aggregate exists; the effort is design iteration (label placement in polar coords, legible month ticks, dark background art direction). Page weight: PNG fine; GIF ~2–5 MB — offer mp4 or place below the fold.
- **Impact 9 / Effort 6.** This is the one that gets screenshot on social media and linked as "that European fire spiral site." Honest scores: it will take a full day of polishing to be good, and a mediocre spiral is worse than no spiral.
- **When: build the aggregate NOW (shared with ideas 1–2), ship the static spiral NOW if a day is available; the animated version is a SEPTEMBER centerpiece when the 2026 ring closes.**

---

## Top-3 recommendation for THIS week's page (ranked by impact/effort)

**1. Gallery of scars — top-10 fires of 2026 at common scale with a Paris-sized comparator (idea 10). Impact 8.5 / Effort 3.**
Implementation brief: from cached `tagged_2026_full`, `slice_max(area_ha, n = 10)`; build one facet per fire with `geom_sf` filled by dominant LC (reuse the leaflet chunk's `max.col` dominant-LC code and `pal_lc`), equal panel extents = max scar bbox side ×1.1 centered on each centroid (EPSG:3035), add a 10,500 ha circle labeled "Paris, for scale" in panel 1, panel titles from `commune`/`province` + `ba_date` + `lab_si_ha(area_ha)`; static PNG, `theme_burns(map = TRUE)`.

**2. Fire inside Natura 2000 protected areas (idea 13). Impact 8 / Effort 3.**
Implementation brief: verify `percna2k` exists in the 2017–2019 cached same-window objects; compute `prot_ha = sum(area_ha * to_num(percna2k)/100)` per year from the existing `tagged_<y>_<y>0601_<y>0703` caches + 2026, plot share-of-burned-area lollipops (2026 in `#D64A05`) beside a 2026 map colored by `percna2k` (grey→green gradient); caption the field definition, the fire-adapted-habitat nuance, and the Jun 1–Jul 3 same-window framing.

**3. The fire-year calendar heatmap, 2016–2026 (idea 1) — and cache the weekly aggregate that unlocks ideas 2, 6, 14. Impact 8 / Effort 4.**
Implementation brief: one `cached()` pass looping `read_effis()` over `ba_2016.geojson`…`ba_2026.geojson`, `st_filter(eu$union)`, aggregate to year × ISO-week × Σ `area_ha` (drop geometry immediately after clipping; keep centroid lat and agri/forest dominant-LC flags in the same aggregate for later ideas); plot `geom_tile` (x = week, y = year desc, fill = log10 area, `magma`, na grey), annotate 2026 cutoff week; caption the 2016 partial-quality and small-fire-floor caveats.

All three are NOW-honest (no season verdict implied), snapshot-only, and use packages already on the page. Pick 3 deliberately over-invests one notch of effort because its cached aggregate is the down payment on the signature spiral (idea 14) for September.
