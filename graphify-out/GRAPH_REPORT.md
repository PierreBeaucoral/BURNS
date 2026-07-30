# Graph Report - BURNS  (2026-07-30)

## Corpus Check
- 34 files · ~100,516 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 416 nodes · 688 edges · 30 communities (23 shown, 7 thin omitted)
- Extraction: 86% EXTRACTED · 14% INFERRED · 0% AMBIGUOUS · INFERRED: 96 edges (avg confidence: 0.56)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `bb2724c0`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- cached
- leaflet-1.3.1/leaflet.js
- jquery-3.6.0.min.js
- proj4.min.js
- download_year
- jquery-3.6.0.js
- leaflet-binding-2.2.3/leaflet.js
- flag_table
- update_site.sh
- iso_week_start
- country_land_area
- fmt_bytes
- parse_year_args
- kv
- htmlwidgets.js
- Animation
- domManip
- clipboard.min.js
- matcherFromTokens
- How 2025 compares with earlier seasons
- expectSync
- getWidthOrHeight
- resolve
- CLAUDE.md

## God Nodes (most connected - your core abstractions)
1. `i()` - 16 edges
2. `h()` - 12 edges
3. `n()` - 11 edges
4. `o()` - 11 edges
5. `u()` - 11 edges
6. `l()` - 10 edges
7. `l()` - 10 edges
8. `cached` - 10 edges
9. `e()` - 9 edges
10. `q()` - 9 edges

## Surprising Connections (you probably didn't know these)
- `Interactive Leaflet Fire Explorer` --calls--> `cached`  [EXTRACTED]
  posts/2026.qmd → R/cache.R
- `Land-Cover Composition` --calls--> `get_tagged_window`  [EXTRACTED]
  posts/2026.qmd → R/pipeline.R
- `Summer 2026 Wildfires: State of the Season (2026 page)` --calls--> `get_tagged_full_year`  [EXTRACTED]
  posts/2026.qmd → R/pipeline.R
- `Season-at-a-glance Headline Numbers` --calls--> `build_envelope`  [EXTRACTED]
  index.qmd → R/pipeline.R
- `France and Spain Country Envelopes` --calls--> `build_envelope`  [EXTRACTED]
  posts/2026.qmd → R/pipeline.R

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Envelope chart data-to-figure pipeline** — r_pipeline_build_envelope, r_pipeline_get_tagged_summer, r_pipeline_build_daily_cum, r_cache_cached, r_plots_plot_envelope [EXTRACTED 0.75]
- **EFFIS WFS paged fetch machinery** — scripts_fetch_effis_process_year, scripts_fetch_effis_download_year, scripts_fetch_effis_fetch_hits, scripts_fetch_effis_curl_fetch, scripts_fetch_effis_build_page_url, scripts_fetch_effis_read_page_sf [EXTRACTED 0.75]
- **Cached country-tagged perimeter chain** — r_pipeline_tagged_window, r_pipeline_get_tagged_window, r_pipeline_get_tagged_summer, r_pipeline_get_tagged_full_year, r_cache_cached [EXTRACTED 0.75]
- **Single-source brand token palette** — r_tokens_burns_tokens, r_tokens_burns_brand, r_tokens_pal_lc, r_theme_theme_burns, theme_build_tokens_kv [EXTRACTED 0.75]
- **Historical footprint and re-burn analysis** — r_pipeline_get_historical_footprint, r_pipeline_clean_polygons, r_pipeline_compute_reburn [EXTRACTED 0.75]
- **Calendar heatmap data-to-figure pipeline** — r_pipeline_clip_europe_year, r_pipeline_summarise_weekly, r_pipeline_build_weekly_area, r_pipeline_prepare_calendar_grid, r_plots_plot_calendar_heatmap [EXTRACTED 0.75]
- **Gallery of scars and Paris comparator** — r_pipeline_build_gallery_scars, r_pipeline_build_paris_comparison, r_plots_plot_gallery_scars [EXTRACTED 0.75]
- **Country flag lookup and dominant colour** — r_flags_flag_table, r_flags_name_to_iso2, r_flags_fetch_flags, r_flags_dominant_flag_color [EXTRACTED 0.75]
- **2026 Season Page Analyses** — posts_2026_cumulative_envelope, posts_2026_calendar_heatmap, posts_2026_hero_map, posts_2026_leaflet_explorer, posts_2026_fire_size_distribution, posts_2026_gallery_of_scars, posts_2026_paris_comparator, posts_2026_country_rankings, posts_2026_reburn_map, posts_2026_land_cover_composition, posts_2026_natura_2000, posts_2026_country_envelopes [EXTRACTED 1.00]
- **BURNS Quarto Website Pages** — index_tracker, posts_2026_season_page, about_page, _quarto_yml_quarto_website [EXTRACTED 1.00]
- **EFFIS Data Provenance and Caveats** — about_effis_data_source, about_modis_sentinel_transition, about_country_attribution, about_snapshot_pinning [INFERRED 0.85]

## Communities (30 total, 7 thin omitted)

### Community 0 - "cached"
Cohesion: 0.06
Nodes (63): minty/darkly BURNS Identity Theme, Quarto Website Configuration, EFFIS Rapid Perimeters (data source), MODIS to Sentinel-2 Detection Transition, About BURNS, Weekly Snapshot Pinning, Season-at-a-glance Headline Numbers, Europe Wildfire Season Tracker (index page) (+55 more)

### Community 1 - "leaflet-1.3.1/leaflet.js"
Cohesion: 0.10
Nodes (42): a(), c(), ct(), dt(), e(), et(), f(), ft() (+34 more)

### Community 2 - "jquery-3.6.0.min.js"
Cohesion: 0.07
Nodes (34): A(), at(), b(), be(), ce(), e(), Ee(), fe() (+26 more)

### Community 3 - "proj4.min.js"
Cohesion: 0.08
Nodes (31): a(), b(), c(), d(), Dt(), e(), et(), f() (+23 more)

### Community 4 - "download_year"
Cohesion: 0.28
Nodes (9): build_hits_url, build_page_url, build_year_filter, curl_fetch, download_year, fetch_hits, process_year, read_page_sf (+1 more)

### Community 5 - "jquery-3.6.0.js"
Cohesion: 0.06
Nodes (10): computeStyleTests(), dataAttr(), finalPropName(), getData(), NOTE: This can be skipped if there are no unmatched elements (i.e., `matchedCoun, TODO: Now that all calls to _data and _removeData have been replaced, TODO: identify versions, TODO: identify versions (+2 more)

### Community 6 - "leaflet-binding-2.2.3/leaflet.js"
Cohesion: 0.08
Nodes (12): addLayers(), addMarkers(), _classCallCheck(), ClusterLayerStore(), ControlStore(), _createClass(), DataFrame(), _defineProperties() (+4 more)

### Community 7 - "flag_table"
Cohesion: 0.33
Nodes (6): Country Attribution by Maximum Overlap, Top-10 Country Rankings, dominant_flag_color, fetch_flags, flag_table, name_to_iso2

### Community 14 - "htmlwidgets.js"
Cohesion: 0.10
Nodes (14): escapeRegExp(), evalAndRun(), filterByClass(), forEach(), has_jQuery3(), hasClass(), initSizing(), maybeStaticRenderLater() (+6 more)

### Community 15 - "Animation"
Cohesion: 0.15
Nodes (14): adoptValue(), ajaxConvert(), ajaxHandleResponses(), Animation(), camelCase(), createFxNow(), createTween(), defaultPrefilter() (+6 more)

### Community 16 - "domManip"
Cohesion: 0.16
Nodes (14): buildFragment(), buildParams(), cloneCopyEvent(), disableScript(), DOMEval(), domManip(), getAll(), isArrayLike() (+6 more)

### Community 17 - "clipboard.min.js"
Cohesion: 0.23
Nodes (7): c(), e(), h(), o(), p(), r(), v()

### Community 18 - "matcherFromTokens"
Cohesion: 0.20
Nodes (12): addCombinator(), condense(), createPositionalPseudo(), elementMatcher(), markFunction(), matcherFromGroupMatchers(), matcherFromTokens(), multipleContexts() (+4 more)

### Community 19 - "How 2025 compares with earlier seasons"
Cohesion: 0.17
Nodes (11): 2025 against 2017, 2022, and 2023, 2025 against the 2017 benchmark, Day by day, Geographic distribution, How 2025 compares with earlier seasons, Month by month, Notes and caveats, The season in motion (+3 more)

### Community 20 - "expectSync"
Cohesion: 0.50
Nodes (4): expectSync(), leverageNative(), returnTrue(), safeActiveElement()

### Community 21 - "getWidthOrHeight"
Cohesion: 0.67
Nodes (3): boxModelAdjustment(), curCSS(), getWidthOrHeight()

### Community 22 - "resolve"
Cohesion: 0.67
Nodes (3): Identity(), resolve(), Thrower()

## Knowledge Gaps
- **27 isolated node(s):** `graphify`, `Geographic distribution`, `Month by month`, `Day by day`, `The season in motion` (+22 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **7 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `e()` connect `jquery-3.6.0.min.js` to `resolve`?**
  _High betweenness centrality (0.152) - this node is a cross-community bridge._
- **Why does `resolve()` connect `resolve` to `jquery-3.6.0.min.js`, `jquery-3.6.0.js`?**
  _High betweenness centrality (0.151) - this node is a cross-community bridge._
- **Why does `l()` connect `jquery-3.6.0.min.js` to `leaflet-1.3.1/leaflet.js`?**
  _High betweenness centrality (0.113) - this node is a cross-community bridge._
- **Are the 12 inferred relationships involving `i()` (e.g. with `dt()` and `e()`) actually correct?**
  _`i()` has 12 INFERRED edges - model-reasoned connections that need verification._
- **Are the 4 inferred relationships involving `h()` (e.g. with `i()` and `n()`) actually correct?**
  _`h()` has 4 INFERRED edges - model-reasoned connections that need verification._
- **Are the 8 inferred relationships involving `n()` (e.g. with `f()` and `h()`) actually correct?**
  _`n()` has 8 INFERRED edges - model-reasoned connections that need verification._
- **Are the 7 inferred relationships involving `o()` (e.g. with `f()` and `R()`) actually correct?**
  _`o()` has 7 INFERRED edges - model-reasoned connections that need verification._