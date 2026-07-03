# ==============================================================================
# pipeline.R
# Season-assembly layer for the 2026 follow-up (and the index.qmd tracker):
# per-year tagged perimeters, daily cumulative series, the envelope chart's
# historical band, the unioned historical footprint for re-burn analysis, and
# national land-area lookups. Every expensive step is wrapped in cached() so
# a second render reads .rds files instead of re-running geometry ops.
# Required packages (namespaced calls only, no library() here):
#   sf, dplyr, tibble, purrr, lubridate, stats
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

#' Cached wrapper around tagged_window(), keyed by year + exact date window so
#' distinct windows (summer vs season-to-date vs full-year) never collide.
#' @return sf object, see tagged_window()
get_tagged_window <- function(year, snapshot_dir, eu, start_date, end_date, version = 1) {
  key <- sprintf(
    "tagged_%d_%s_%s", year, format(start_date, "%Y%m%d"), format(end_date, "%Y%m%d")
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
  key <- sprintf(
    "envelope_%d_%d_%d_%d_%d",
    min(hist_years), max(hist_years), year_current, start_month, end_month
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
    current_cum_ha <- if (nrow(cur_daily)) cur_daily$cum_ha[nrow(cur_daily)] else 0
    current_n_fires <- if (nrow(cur_daily)) cur_daily$cum_fires[nrow(cur_daily)] else 0L

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
        pct_vs_median = 100 * current_cum_ha / median_to_date_ha
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
