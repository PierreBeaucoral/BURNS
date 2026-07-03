# ==============================================================================
# pipeline.R
# Season-assembly layer for the 2026 follow-up (and the index.qmd tracker):
# per-year tagged perimeters, daily cumulative series, the envelope chart's
# historical band, the unioned historical footprint for re-burn analysis,
# national land-area lookups, the year x ISO-week burned-area aggregate
# (calendar heatmap), the Natura 2000 protected-burn series, and the gallery-
# of-scars small-multiples data prep. Every expensive step is wrapped in
# cached() so a second render reads .rds files instead of re-running geometry
# ops.
# Required packages (namespaced calls only, no library() here):
#   sf, dplyr, tidyr, tibble, purrr, lubridate, scales, stats
# Depends on: R/helpers.R, R/geo.R, R/cache.R
# ==============================================================================

#' Cached wrapper around load_europe_polygons(). Offline (rnaturalearthhires),
#' but the filter/intersect/union chain still costs a couple of seconds, so
#' cache it like everything else.
#' @param scale rnaturalearth scale, default "large"
#' @return list(poly = sf polygons per country, union = single unioned geometry)
get_eu <- function(scale = "large", version = 1) {
  cached(sprintf("eu_polygons_%s", scale), load_europe_polygons(scale = scale), version = version)
}

#' Read, window-filter, and country-tag one year of EFFIS perimeters.
#' Not cached itself (get_tagged_window() below caches it) -- kept as a plain
#' function so the caching key can encode exactly the window requested.
#' @param year integer year (matches ba_<year>.geojson file name)
#' @param snapshot_dir path to the dated snapshot directory holding ba_<year>.geojson
#' @param eu list(poly, union) from get_eu()
#' @param start_date, end_date Date bounds (inclusive), passed to filter_window()
#' @return sf object as returned by tag_countries() (CRS 3035, area_ha, name_long, iso_a2)
tagged_window <- function(year, snapshot_dir, eu, start_date, end_date) {
  geojson_path <- file.path(snapshot_dir, sprintf("ba_%d.geojson", year))
  ba_all <- read_effis(geojson_path)
  ba_win <- filter_window(ba_all, start_date, end_date)
  tag_countries(ba_win, eu$poly, eu$union)
}

#' Cached wrapper around tagged_window(), keyed by year + exact date window +
#' snapshot so distinct windows (summer vs season-to-date vs full-year) never
#' collide, AND a re-fetched snapshot for the same dates never serves a stale
#' .rds. Every ba_<year>.geojson file -- historical years included -- gets
#' re-downloaded and can carry revised perimeters on every snapshot (EFFIS
#' rapid mapping is corrected over time), so the snapshot identifier is
#' threaded into the key for ALL years, not just the in-progress current
#' year. The one-time recompute this forces on a new snapshot is an accepted,
#' documented cost (see cache.R contract comment).
#' @return sf object, see tagged_window()
get_tagged_window <- function(year, snapshot_dir, eu, start_date, end_date, version = 1) {
  key <- sprintf(
    "tagged_%d_%s_%s_snap%s",
    year, format(start_date, "%Y%m%d"), format(end_date, "%Y%m%d"), basename(snapshot_dir)
  )
  cached(key, tagged_window(year, snapshot_dir, eu, start_date, end_date), version = version)
}

#' Cached, country-tagged perimeters for a year's meteorological-summer window
#' (month-level convenience wrapper around get_tagged_window()).
#' @param start_month, end_month integer months (inclusive), default Jun-Sep (6-9)
#' @return sf object, see tagged_window()
get_tagged_summer <- function(year, snapshot_dir, eu, start_month = 6L, end_month = 9L, version = 1) {
  last_day <- lubridate::days_in_month(as.Date(sprintf("%d-%02d-01", year, end_month)))
  start_date <- as.Date(sprintf("%d-%02d-01", year, start_month))
  end_date   <- as.Date(sprintf("%d-%02d-%02d", year, end_month, last_day))
  get_tagged_window(year, snapshot_dir, eu, start_date, end_date, version = version)
}

#' Cached, country-tagged perimeters for a year's full calendar range
#' (Jan 1 - Dec 31, or through today for the current partial year -- filter_window
#' simply returns fewer rows past the last available FIREDATE, so passing
#' Dec 31 is safe for an in-progress year too).
#' @return sf object, see tagged_window()
get_tagged_full_year <- function(year, snapshot_dir, eu, version = 1) {
  get_tagged_window(
    year, snapshot_dir, eu,
    start_date = as.Date(sprintf("%d-01-01", year)),
    end_date   = as.Date(sprintf("%d-12-31", year)),
    version = version
  )
}

#' Build a daily cumulative burned-area series over [start_date, end_date],
#' zero-filling days with no perimeters so every year's series has the same
#' length/day_idx grid (required for the envelope band).
#' @param tagged_sf sf object with ba_date, area_ha columns (geometry dropped internally)
#' @return tibble(ba_date, area_ha, n_fires, cum_ha, cum_fires, day_idx)
build_daily_cum <- function(tagged_sf, start_date, end_date) {
  all_dates <- tibble::tibble(ba_date = seq.Date(start_date, end_date, by = "day"))

  daily <- tagged_sf |>
    sf::st_drop_geometry() |>
    dplyr::group_by(ba_date) |>
    dplyr::summarise(area_ha = sum(area_ha, na.rm = TRUE), n_fires = dplyr::n(), .groups = "drop")

  all_dates |>
    dplyr::left_join(daily, by = "ba_date") |>
    dplyr::mutate(
      area_ha = dplyr::coalesce(area_ha, 0),
      n_fires = dplyr::coalesce(n_fires, 0L)
    ) |>
    dplyr::arrange(ba_date) |>
    dplyr::mutate(
      cum_ha    = cumsum(area_ha),
      cum_fires = cumsum(n_fires),
      day_idx   = as.integer(ba_date - start_date) + 1L
    )
}

#' Build the envelope chart's underlying data: a min-max-median band across
#' hist_years plus the current year's truncated (as-of) daily cumulative
#' series, all on a shared day_idx grid. This is the single source both
#' index.qmd and posts/2026.qmd read (same cache key -> same object).
#' @param hist_years integer vector of historical years for the band (2017:2025)
#' @param year_current integer, the current season year (2026L)
#' @param snapshot_dir path to the dated snapshot directory
#' @param eu list(poly, union) from get_eu()
#' @param start_month, end_month integer months bounding the season window (default 6-9)
#' @param as_of_date Date to truncate the current year at; default NULL uses
#'   the max ba_date actually present in the current year's data (more
#'   reproducible than Sys.Date(), which can drift from the data snapshot)
#' @return list(hist_daily, band, current, current_full_window, ref_dates, meta)
build_envelope <- function(hist_years, year_current, snapshot_dir, eu,
                            start_month = 6L, end_month = 9L, as_of_date = NULL, version = 1) {
  # Snapshot-aware: the envelope is built from get_tagged_summer() calls over
  # both historical AND current years, all read from snapshot_dir's
  # ba_<year>.geojson files, which can be revised on a re-fetch (see cache.R
  # contract comment) -- omitting the snapshot here would silently serve a
  # stale envelope after a new weekly snapshot lands.
  key <- sprintf(
    "envelope_%d_%d_%d_%d_%d_snap%s",
    min(hist_years), max(hist_years), year_current, start_month, end_month, basename(snapshot_dir)
  )

  cached(key, {
    hist_daily <- purrr::map_dfr(hist_years, function(y) {
      last_day <- lubridate::days_in_month(as.Date(sprintf("%d-%02d-01", y, end_month)))
      start_date <- as.Date(sprintf("%d-%02d-01", y, start_month))
      end_date   <- as.Date(sprintf("%d-%02d-%02d", y, end_month, last_day))
      tg <- get_tagged_summer(y, snapshot_dir, eu, start_month, end_month)
      build_daily_cum(tg, start_date, end_date) |> dplyr::mutate(year = y)
    })

    cur_start <- as.Date(sprintf("%d-%02d-01", year_current, start_month))
    last_day_cur <- lubridate::days_in_month(as.Date(sprintf("%d-%02d-01", year_current, end_month)))
    cur_end_full <- as.Date(sprintf("%d-%02d-%02d", year_current, end_month, last_day_cur))

    tg_cur <- get_tagged_summer(year_current, snapshot_dir, eu, start_month, end_month)
    as_of <- if (is.null(as_of_date)) max(tg_cur$ba_date, na.rm = TRUE) else as_of_date

    cur_daily_full <- build_daily_cum(tg_cur, cur_start, cur_end_full) |>
      dplyr::mutate(year = year_current)
    cur_daily <- cur_daily_full |> dplyr::filter(ba_date <= as_of)

    ref_dates <- tibble::tibble(
      day_idx  = seq_len(as.integer(cur_end_full - cur_start) + 1L),
      ref_date = seq.Date(cur_start, cur_end_full, by = "day")
    )

    band <- hist_daily |>
      dplyr::group_by(day_idx) |>
      dplyr::summarise(
        min_ha    = min(cum_ha, na.rm = TRUE),
        max_ha    = max(cum_ha, na.rm = TRUE),
        median_ha = stats::median(cum_ha, na.rm = TRUE),
        .groups = "drop"
      ) |>
      dplyr::left_join(ref_dates, by = "day_idx")

    as_of_day_idx <- as.integer(as_of - cur_start) + 1L
    median_to_date_ha <- band$median_ha[band$day_idx == as_of_day_idx]
    if (length(median_to_date_ha) == 0L) median_to_date_ha <- NA_real_
    current_cum_ha <- if (nrow(cur_daily)) cur_daily$cum_ha[nrow(cur_daily)] else 0
    current_n_fires <- if (nrow(cur_daily)) cur_daily$cum_fires[nrow(cur_daily)] else 0L

    # Guard: very early in the season the historical median-to-date can be
    # exactly (or numerically) zero -- no historical fires yet by this
    # calendar day -- which would make pct_vs_median Inf/NaN and silently
    # corrupt the "vs a typical season" prose. Return NA with a warning
    # instead of a bogus ratio; callers (index.qmd, posts/2026.qmd) display
    # "n/a (too early in season)" when this is NA.
    pct_vs_median <- if (is.na(median_to_date_ha) || abs(median_to_date_ha) < 1e-9) {
      warning("median_to_date_ha is zero or unavailable (too early in season) -- pct_vs_median set to NA")
      NA_real_
    } else {
      100 * current_cum_ha / median_to_date_ha
    }

    list(
      hist_daily = hist_daily,
      band = band,
      current = cur_daily,
      current_full_window = cur_daily_full,
      ref_dates = ref_dates,
      meta = list(
        hist_years = hist_years,
        year_current = year_current,
        start_month = start_month,
        end_month = end_month,
        as_of_date = as_of,
        as_of_day_idx = as_of_day_idx,
        current_cum_ha = current_cum_ha,
        current_n_fires = current_n_fires,
        median_to_date_ha = median_to_date_ha,
        pct_vs_median = pct_vs_median
      )
    )
  }, version = version)
}

#' Coerce an sfc to clean, valid POLYGON/MULTIPOLYGON geometry: repairs
#' validity, extracts only the polygonal part of any GEOMETRYCOLLECTION
#' (drops degenerate point/line slivers left behind by repeated
#' simplify/union/intersect passes), and drops empty geometries. Repeated
#' union/simplify chains on thousands of input polygons are prone to
#' producing GEOMETRYCOLLECTIONs, which make GEOS fall back to slow,
#' per-element handling in downstream st_intersection()/st_difference()
#' calls -- this keeps every stage strictly polygonal so those stay fast.
#' NOTE the order of operations: empties are dropped BEFORE
#' st_collection_extract(). Empty geometries come back from GEOS typed as
#' GEOMETRYCOLLECTION EMPTY, and running st_collection_extract() on an sfc
#' polluted with them can silently drop ALL geometries (observed: a year's
#' ~657k ha simplified footprint collapsing to 0 ha). Extraction is applied
#' only to genuine GEOMETRYCOLLECTION elements; polygonal elements pass
#' through untouched and line/point slivers are dropped.
#' @param x sfc
#' @return sfc, POLYGON/MULTIPOLYGON only, no empties
clean_polygons <- function(x) {
  x <- sf::st_make_valid(x)
  x <- x[!sf::st_is_empty(x)]
  if (length(x) == 0L) return(x)

  types <- as.character(sf::st_geometry_type(x))
  keep <- x[types %in% c("POLYGON", "MULTIPOLYGON")]

  gc <- x[types == "GEOMETRYCOLLECTION"]
  if (length(gc) > 0L) {
    extracted <- suppressWarnings(sf::st_collection_extract(gc, "POLYGON"))
    extracted <- extracted[!sf::st_is_empty(extracted)]
    keep <- c(keep, extracted)
  }

  keep
}

#' Build the unioned, simplified historical footprint (all perimeters across
#' `years`, full calendar range, EU-clipped) used as the re-burn reference
#' surface. Simplifies each year's clipped geometry BEFORE unioning to keep
#' the union tractable; st_filter() pre-screens candidates via spatial index
#' so years with many non-European fires (Russia, North Africa) don't pay for
#' exact intersection geometry on features that don't overlap Europe at all.
#' Every stage is passed through clean_polygons() so the result stays strictly
#' POLYGON/MULTIPOLYGON (never a GEOMETRYCOLLECTION) for fast downstream ops.
#' @param years integer vector of years to union (e.g. 2017:2025)
#' @param snapshot_dir path to the dated snapshot directory
#' @param eu list(poly, union) from get_eu()
#' @param tol_m simplification tolerance in metres (CRS 3035 is metric), default 100
#' @return sfc, single unioned (multi)polygon geometry, CRS 3035
get_historical_footprint <- function(years, snapshot_dir, eu, tol_m = 100, version = 3) {
  key <- sprintf("historical_footprint_%d_%d_tol%d", min(years), max(years), tol_m)

  cached(key, {
    per_year_union <- lapply(years, function(y) {
      message(sprintf("historical footprint: processing %d ...", y))
      geojson_path <- file.path(snapshot_dir, sprintf("ba_%d.geojson", y))
      ba_all <- read_effis(geojson_path)
      ba_full <- filter_window(ba_all, as.Date(sprintf("%d-01-01", y)), as.Date(sprintf("%d-12-31", y)))

      candidates <- sf::st_filter(ba_full, eu$union)  # spatial-index pre-screen
      clipped <- clean_polygons(sf::st_intersection(sf::st_geometry(candidates), eu$union))
      simplified <- clean_polygons(sf::st_simplify(clipped, dTolerance = tol_m))
      out <- clean_polygons(sf::st_union(simplified))
      message(sprintf(
        "historical footprint: %d done (%.0f ha unioned)",
        y, sum(as.numeric(sf::st_area(out))) / 10000
      ))
      out
    })

    combined <- do.call(c, per_year_union)
    clean_polygons(sf::st_union(combined))
  }, version = version)
}

#' Overlay 2026 (or any current-year) tagged perimeters against the
#' historical footprint: total area, re-burned area/share, and split
#' geometries for mapping (re-burned portion vs first-time portion).
#' @param tagged_current sf object (e.g. get_tagged_full_year(2026, ...))
#' @param footprint sfc from get_historical_footprint()
#' @return list(total_ha, reburn_ha, reburn_share, reburn_geom, new_geom)
compute_reburn <- function(tagged_current, footprint) {
  total_ha <- sum(tagged_current$area_ha, na.rm = TRUE)
  cur_geom <- clean_polygons(sf::st_geometry(tagged_current))
  footprint <- clean_polygons(footprint)

  reburn_geom <- clean_polygons(sf::st_intersection(cur_geom, footprint))
  reburn_ha <- if (length(reburn_geom) > 0L) sum(as.numeric(sf::st_area(reburn_geom))) / 10000 else 0

  new_geom <- clean_polygons(sf::st_difference(cur_geom, footprint))

  list(
    total_ha = total_ha,
    reburn_ha = reburn_ha,
    reburn_share = if (total_ha > 0) reburn_ha / total_ha else NA_real_,
    reburn_geom = reburn_geom,
    new_geom = new_geom
  )
}

#' National land area (ha) per country in the Europe reference polygons, for
#' normalizing burned area into a "% of national land area" measure.
#' @param eu list(poly, union) from get_eu()
#' @return tibble(name_long, iso_a2, land_area_ha)
country_land_area <- function(eu) {
  areas_ha <- as.numeric(sf::st_area(eu$poly)) / 10000
  eu$poly |>
    sf::st_drop_geometry() |>
    dplyr::mutate(land_area_ha = areas_ha) |>
    dplyr::distinct(name_long, iso_a2, land_area_ha)
}

# ==============================================================================
# Calendar heatmap (year x ISO-week burned area, 2016-2026)
# ==============================================================================

#' Lightweight Europe-clip for one year: st_intersection against the SINGLE
#' unioned Europe geometry only, no per-country attribution. Deliberately
#' NOT get_tagged_full_year()/tag_countries() -- benchmarked at 3,767 s for
#' one historical year (2019) because tag_countries() does a pairwise overlap
#' join against ~40 detailed country polygons; looping that over 2016-2025
#' would take 10+ hours. This lighter clip was benchmarked at 17.6-61.3 s per
#' year (worst case: 2025, 23,188 raw features), i.e. tractable for an
#' 11-year loop. Used only by build_weekly_area(); country-level figures
#' (gallery, Natura map) still use the fully tagged objects elsewhere.
#' @param year integer year (matches ba_<year>.geojson file name)
#' @param snapshot_dir path to the dated snapshot directory
#' @param eu list(poly, union) from get_eu()
#' @return sf object, Europe-clipped, CRS 3035, with area_ha recomputed post-clip
clip_europe_year <- function(year, snapshot_dir, eu) {
  geojson_path <- file.path(snapshot_dir, sprintf("ba_%d.geojson", year))
  ba_all <- read_effis(geojson_path)
  ba_full <- filter_window(ba_all, as.Date(sprintf("%d-01-01", year)), as.Date(sprintf("%d-12-31", year)))
  candidates <- sf::st_filter(ba_full, eu$union)          # spatial-index pre-screen
  clipped <- suppressWarnings(sf::st_intersection(candidates, eu$union))
  # Boundary touches can leave empty or degenerate (line/point-only) results;
  # drop them before area/centroid, else st_coordinates(st_centroid(...))
  # silently returns fewer rows than nrow(clipped) (empty points carry no
  # coordinate row), desynchronising downstream vectors by length.
  clipped <- clipped[!sf::st_is_empty(sf::st_geometry(clipped)), ]
  clipped |> dplyr::mutate(area_ha = as.numeric(sf::st_area(sf::st_geometry(clipped))) / 10000)
}

#' Collapse a tagged/clipped sf of perimeters to year x ISO-week totals:
#' burned area, fire count, forest-vs-agricultural area split (for a future
#' "two fire regimes" chart), and the area-weighted mean centroid latitude
#' (for a future "is fire creeping north" chart) -- both cheap to compute
#' alongside the area sum, so this pass is a down payment on later ideas.
#' ISO week 53 (rare; only a few years define it) is folded into week 52 to
#' keep every year on the same 1-52 grid.
#' @param tg sf with ba_date, area_ha, and lc_cols columns (raw or already numeric)
#' @param year integer year label to attach (kept separate from isoyear() to
#'   avoid a Dec-31-belongs-to-next-ISO-year edge case splitting one year's
#'   data across two grid rows)
#' @param lc_cols character vector of land-cover share column names
#' @return tibble(year, iso_week, area_ha, n_fires, forest_ha, agri_ha, mean_lat)
summarise_weekly <- function(tg, year, lc_cols) {
  geom <- sf::st_geometry(tg)
  lat <- sf::st_coordinates(suppressWarnings(sf::st_centroid(sf::st_transform(geom, 4326))))[, "Y"]

  tg |>
    sf::st_drop_geometry() |>
    dplyr::mutate(
      dplyr::across(dplyr::all_of(lc_cols), to_num),
      lat = lat,
      forest_ha = (broadlea + conifer + mixed + scleroph + transit) / 100 * area_ha,
      agri_ha   = agriareas / 100 * area_ha,
      iso_week  = pmin(lubridate::isoweek(ba_date), 52L),
      year      = year
    ) |>
    dplyr::group_by(year, iso_week) |>
    # NOTE order matters: dplyr::summarise() evaluates arguments sequentially
    # within one call, so mean_lat (which needs the PER-ROW area_ha as
    # weights) must be computed BEFORE area_ha is overwritten by its own
    # sum() below -- reversing the order silently reduces area_ha to a
    # length-1 scalar for the weighted.mean() call and throws a length
    # mismatch (caught in smoke-testing, not a hypothetical).
    dplyr::summarise(
      mean_lat  = stats::weighted.mean(lat, w = pmax(area_ha, 1e-6), na.rm = TRUE),
      n_fires   = dplyr::n(),
      forest_ha = sum(forest_ha, na.rm = TRUE),
      agri_ha   = sum(agri_ha, na.rm = TRUE),
      area_ha   = sum(area_ha, na.rm = TRUE),
      .groups = "drop"
    )
}

#' Build the year x ISO-week burned-area aggregate behind the calendar
#' heatmap, cached as one small tibble (~11 years x 52 weeks). Historical
#' years go through the light Europe-clip (clip_europe_year(), fast); the
#' current year reuses an already-loaded, already country-tagged object
#' (avoids a second read of the same file).
#' @param years historical (complete) years requiring a fresh clip pass, e.g. 2016:2025
#' @param current_year integer, in-progress current year, e.g. 2026L
#' @param current_tagged sf, already-tagged perimeters for current_year (e.g.
#'   tagged_2026_full), reused instead of re-reading/re-clipping
#' @param lc_cols character vector of land-cover share column names
#' @return tibble, see summarise_weekly()
build_weekly_area <- function(years, current_year, current_tagged, snapshot_dir, eu, lc_cols, version = 1) {
  # Snapshot-aware: clip_europe_year() reads ba_<year>.geojson directly from
  # snapshot_dir for every historical year, which can carry revised
  # perimeters on a re-fetch (see cache.R contract comment).
  key <- sprintf("weekly_area_%d_%d_snap%s", min(years), current_year, basename(snapshot_dir))

  cached(key, {
    hist_part <- purrr::map_dfr(years, function(y) {
      t0 <- Sys.time()
      message(sprintf("weekly aggregate: clipping %d ...", y))
      cl <- clip_europe_year(y, snapshot_dir, eu)
      out <- summarise_weekly(cl, y, lc_cols)
      message(sprintf(
        "weekly aggregate: %d done (%s ha, %.0fs)",
        y, scales::comma(round(sum(out$area_ha))), as.numeric(difftime(Sys.time(), t0, units = "secs"))
      ))
      out
    })

    message(sprintf("weekly aggregate: summarising %d (already loaded) ...", current_year))
    cur_part <- summarise_weekly(current_tagged, current_year, lc_cols)

    dplyr::bind_rows(hist_part, cur_part)
  }, version = version)
}

#' Expand the sparse year x ISO-week aggregate into the full display grid for
#' the calendar heatmap: every (year, week) cell 1-52, real zeros for elapsed
#' weeks with no burned area, and explicit NA (left blank, not zero) for
#' weeks of the current in-progress year that have not happened yet.
#' @param weekly tibble from build_weekly_area()
#' @param hist_years complete past years (e.g. 2016:2025)
#' @param year_current in-progress year (e.g. 2026L)
#' @param as_of_date Date; weeks after isoweek(as_of_date) in year_current are NA
#' @return tibble(year, iso_week, area_ha) with area_ha NA for not-yet-happened weeks
prepare_calendar_grid <- function(weekly, hist_years, year_current, as_of_date) {
  all_years <- c(hist_years, year_current)
  cutoff_week <- min(lubridate::isoweek(as_of_date), 52L)

  tidyr::expand_grid(year = all_years, iso_week = 1:52) |>
    dplyr::left_join(
      weekly |> dplyr::select(year, iso_week, area_ha), by = c("year", "iso_week")
    ) |>
    dplyr::mutate(
      is_future = year == year_current & iso_week > cutoff_week,
      area_ha = dplyr::if_else(is_future, NA_real_, dplyr::coalesce(area_ha, 0))
    ) |>
    dplyr::select(-is_future)
}

# ==============================================================================
# Fire inside Natura 2000
# ==============================================================================

#' Summarise one tagged/windowed sf of perimeters into total and
#' Natura-2000-protected burned area, using EFFIS's own PERCNA2K field
#' (share of each perimeter's area inside a Natura 2000 site).
#' @param tg sf with area_ha, percna2k columns (percna2k may be raw character)
#' @param year integer year label
#' @return tibble(year, total_ha, prot_ha, share)
natura_summary <- function(tg, year) {
  df <- tg |> sf::st_drop_geometry() |> dplyr::mutate(percna2k = to_num(percna2k))
  total_ha <- sum(df$area_ha, na.rm = TRUE)
  prot_ha  <- sum(df$area_ha * df$percna2k / 100, na.rm = TRUE)
  tibble::tibble(
    year = year, total_ha = total_ha, prot_ha = prot_ha,
    share = if (total_ha > 0) prot_ha / total_ha else NA_real_
  )
}

#' Year-by-year share of burned area falling inside Natura 2000 protected
#' sites, same Jun 1-cutoff window every year so seasons compare like for
#' like. Historical years reuse the SAME cached Jun1-cutoff tagged windows
#' already built for the land-cover chunk (identical cache key via
#' get_tagged_window()) -- no extra geometry read. The current year reuses an
#' already-loaded tagged object, filtered in-memory to the same window.
#' @param hist_years complete past years, e.g. 2017:2025
#' @param year_current current year, e.g. 2026L
#' @param current_tagged sf, already-tagged full-year perimeters for year_current
#' @param snapshot_dir, eu as elsewhere
#' @param cutoff_md "MM-DD" string marking the same-window end date every year
#' @return tibble(year, total_ha, prot_ha, share)
build_natura_trend <- function(hist_years, year_current, current_tagged, snapshot_dir, eu, cutoff_md, version = 1) {
  key <- sprintf("natura_trend_%d_%d_%s", min(hist_years), year_current, gsub("-", "", cutoff_md))

  cached(key, {
    hist_part <- purrr::map_dfr(hist_years, function(y) {
      tg <- get_tagged_window(
        y, snapshot_dir, eu,
        start_date = as.Date(sprintf("%d-06-01", y)),
        end_date   = as.Date(paste0(y, "-", cutoff_md))
      )
      natura_summary(tg, y)
    })

    cur_start <- as.Date(sprintf("%d-06-01", year_current))
    cur_end   <- as.Date(paste0(year_current, "-", cutoff_md))
    cur_tg <- current_tagged |> dplyr::filter(ba_date >= cur_start, ba_date <= cur_end)
    cur_part <- natura_summary(cur_tg, year_current)

    dplyr::bind_rows(hist_part, cur_part)
  }, version = version)
}

# ==============================================================================
# Gallery of scars
# ==============================================================================

#' Top-n current-year fires by Europe-clipped area, geometry recentred on
#' each fire's own centroid (CRS deliberately dropped: the result is a
#' shared LOCAL coordinate frame in metres-from-own-centroid, not a
#' geographic layer) so a single shared coord window (half_side) renders
#' every panel at an identical metres-per-pixel scale in facet_wrap(). A
#' same-area reference circle (Paris intra-muros, drawn as a circle -- no
#' external boundary fetch) is appended as its own panel at the same scale.
#' @param tagged_full sf, Europe-clipped current-year perimeters (area_ha,
#'   ba_date, commune, name_long, lc_cols)
#' @param n top-n fires by area_ha
#' @param lc_cols, lc_labels dominant land-cover machinery (matches leaflet chunk)
#' @param paris_ha reference circle area in hectares (10,500 ha = ~105 km2,
#'   Paris intra-muros)
#' @return list(panels = sf with panel_label/dominant_lc/area_ha/geometry
#'   (local, CRS-less), half_side = shared window half-width (m), top1_share
#'   = share of tagged_full's total area held by its largest 1% of fires)
build_gallery_scars <- function(tagged_full, n = 10L, lc_cols, lc_labels, paris_ha = 10500) {
  top_n <- tagged_full |>
    dplyr::mutate(dplyr::across(dplyr::all_of(lc_cols), to_num)) |>
    dplyr::slice_max(area_ha, n = n, with_ties = FALSE) |>
    dplyr::arrange(dplyr::desc(area_ha))

  lc_mat <- as.matrix(sf::st_drop_geometry(top_n)[, lc_cols])
  lc_mat[is.na(lc_mat)] <- 0
  dom <- lc_labels[lc_cols[max.col(lc_mat, ties.method = "first")]]
  dom[rowSums(lc_mat) <= 0] <- "n/a"
  top_n$dominant_lc <- unname(dom)

  rank_lab <- sprintf("%02d", seq_len(nrow(top_n)))
  # English month abbreviations regardless of system locale (format(..., "%b")
  # follows the OS locale and silently prints French/etc. abbreviations; the
  # rest of the page avoids this via month.abb[], see posts/2026.qmd as_of_lab)
  date_lab <- sprintf("%02d %s", lubridate::day(top_n$ba_date), month.abb[lubridate::month(top_n$ba_date)])
  # Truncate long commune names so the two-line strip label fits a facet
  # column at ncol = 4; country given as its ISO2 code (compact "name"
  # fallback, since per-panel flag icons inside facet_wrap add real
  # complexity for little payoff at this size).
  commune_raw <- dplyr::coalesce(top_n$commune, "Unnamed")
  commune_lab <- ifelse(
    nchar(commune_raw) > 20, paste0(substr(commune_raw, 1, 19), "…"), commune_raw
  )
  top_n$panel_label <- sprintf(
    "%s. %s (%s)\n%s · %s ha",
    rank_lab, commune_lab, top_n$iso_a2, date_lab, scales::comma(round(top_n$area_ha))
  )
  # Untruncated, single-line "Commune, Country" for prose (panel_label is
  # two-line and truncated for the strip width; prose sentences want the
  # full name instead).
  top_n$place_lab <- sprintf("%s, %s", commune_raw, top_n$name_long)

  bbox_side <- vapply(seq_len(nrow(top_n)), function(i) {
    bb <- sf::st_bbox(sf::st_geometry(top_n)[i])
    max(bb["xmax"] - bb["xmin"], bb["ymax"] - bb["ymin"])
  }, numeric(1))
  half_side <- max(bbox_side) * 1.1 / 2

  geom <- sf::st_geometry(top_n)
  cent <- sf::st_coordinates(sf::st_centroid(geom))
  for (i in seq_along(geom)) geom[i] <- geom[i] - cent[i, ]
  sf::st_geometry(top_n) <- geom
  sf::st_crs(top_n) <- NA

  paris_radius_m <- sqrt(paris_ha * 10000 / pi)
  paris_row <- sf::st_sf(
    panel_label = sprintf("Paris, for scale\n(circle, equal-area, %s ha)", scales::comma(paris_ha)),
    dominant_lc = "Reference (Paris outline)",
    area_ha = paris_ha,
    place_lab = NA_character_,
    geometry = sf::st_buffer(sf::st_sfc(sf::st_point(c(0, 0))), paris_radius_m)
  )

  panels <- top_n |>
    dplyr::select(panel_label, dominant_lc, area_ha, place_lab) |>
    rbind(paris_row)
  panels$panel_label <- factor(panels$panel_label, levels = panels$panel_label)

  # Size-concentration stat quoted in prose: computed on the SAME population
  # (tagged_full = current-year, Europe-clipped) as the gallery itself.
  areas <- tagged_full$area_ha
  thr <- stats::quantile(areas, 0.99, na.rm = TRUE)
  top1_share <- sum(areas[areas >= thr], na.rm = TRUE) / sum(areas, na.rm = TRUE)

  list(panels = panels, half_side = half_side, top1_share = top1_share)
}
