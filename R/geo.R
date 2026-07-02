# ==============================================================================
# geo.R
# Europe reference polygons, EFFIS perimeter reading, summer-window filtering,
# and country tagging by maximum spatial overlap. Consolidates logic that was
# duplicated inline (2025 block) and in get_burnt_summer_local_geom() in the
# original qmd into a single implementation used everywhere.
# Required packages (namespaced calls only, no library() here):
#   sf, dplyr, rnaturalearth, rnaturalearthdata, janitor
# Depends on: R/helpers.R (parse_date_any)
# ==============================================================================

#' Build the Europe reference polygons (EU27 + EFTA + UK + Balkans), cropped to
#' a mainland-Europe bounding box and projected to the equal-area CRS (3035).
#' @param scale rnaturalearth scale, default "large"
#' @return list(poly = sf polygons per country, union = single unioned geometry)
load_europe_polygons <- function(scale = "large") {
  eu_keep <- c(
    "AT", "BE", "BG", "HR", "CY", "CZ", "DK", "EE", "FI", "FR", "DE", "GR", "HU", "IE", "IT",
    "LV", "LT", "LU", "MT", "NL",
    "PL", "PT", "RO", "SK", "SI", "ES", "SE",    # EU27
    "NO", "IS", "CH", "LI",                       # EFTA
    "GB",                                         # UK
    "BA", "RS", "MK", "ME", "XK", "AL"            # Balkans
  )

  europe_bbox <- sf::st_as_sfc(sf::st_bbox(
    c(xmin = -15, xmax = 40, ymin = 34, ymax = 72),
    crs = 4326
  ))

  eu_poly <- rnaturalearth::ne_countries(scale = scale, returnclass = "sf") |>
    dplyr::filter(iso_a2_eh %in% eu_keep) |>
    sf::st_intersection(europe_bbox) |>  # keep only mainland Europe
    sf::st_transform(3035)

  eu_u <- sf::st_union(eu_poly)  # union for stable clipping

  list(poly = eu_poly, union = eu_u)
}

#' Read EFFIS burnt-area perimeters from a shapefile, clean names, detect and
#' parse the fire-date column, and ensure a stable id column.
#' @param shp_path path to the .shp file (sibling .dbf/.shx/... must exist)
#' @return sf object with ba_date (Date) and id columns
read_effis <- function(shp_path) {
  stopifnot(file.exists(shp_path))

  ba_all <- suppressWarnings(sf::st_read(shp_path, quiet = TRUE)) |> janitor::clean_names()

  # Detect & parse date
  cand_names <- tolower(names(ba_all))
  wanted <- c("firedate", "lastupdate", "acq_date", "acqdate", "date", "startdate", "start_date")
  hit <- intersect(wanted, cand_names)
  if (!length(hit)) stop("No date-like column found in shapefile; available: ", paste(names(ba_all), collapse = ", "))
  date_col <- hit[1]

  ba_all <- ba_all |>
    dplyr::mutate(ba_date = parse_date_any(.data[[date_col]])) |>
    dplyr::filter(!is.na(ba_date))

  # Ensure an ID
  if (!"id" %in% names(ba_all)) ba_all <- ba_all |> dplyr::mutate(id = dplyr::row_number())

  ba_all
}

#' Filter perimeters to a given year's summer window (default Jun-Aug) and
#' project to the equal-area CRS (3035). Generalizes the hardcoded 2025 filter.
#' @param ba_all sf object with a ba_date (Date) column, as returned by read_effis()
#' @param year integer year to filter to
#' @param start_month integer start month (inclusive), default 6L (June)
#' @param end_month integer end month (inclusive), default 8L (August)
#' @return sf object, valid geometries, CRS 3035
filter_summer <- function(ba_all, year, start_month = 6L, end_month = 8L) {
  stopifnot(is.numeric(year), year == as.integer(year))
  last_day <- lubridate::days_in_month(as.Date(sprintf("%d-%02d-01", year, end_month)))
  summer_start <- as.Date(sprintf("%d-%02d-01", year, start_month))
  summer_end   <- as.Date(sprintf("%d-%02d-%02d", year, end_month, last_day))

  ba_all |>
    dplyr::filter(ba_date >= summer_start, ba_date <= summer_end) |>
    sf::st_make_valid() |>
    sf::st_transform(3035)
}

#' Clip perimeters to the Europe union and tag each with the country of
#' maximum spatial overlap. Consolidates the inline 2025 tagging block and
#' the former get_burnt_summer_local_geom() into one implementation.
#' @param ba_sf sf object of perimeters (CRS 3035), e.g. output of filter_summer()
#' @param eu_poly sf polygons per country (from load_europe_polygons()$poly)
#' @param eu_union unioned Europe geometry (from load_europe_polygons()$union)
#' @return sf object clipped to eu_union, with area_ha, name_long, iso_a2 columns
tag_countries <- function(ba_sf, eu_poly, eu_union) {
  # Clip to EU union (not bbox, so France/Corsica etc. stay)
  ba_eu <- sf::st_intersection(ba_sf, eu_union)

  # Compute area from geometry (ha)
  ba_eu <- ba_eu |> dplyr::mutate(area_ha = as.numeric(sf::st_area(geometry)) / 10000)

  # Robust country tagging: max overlap
  inter <- sf::st_intersection(
    ba_eu   |> dplyr::select(id, area_ha),
    eu_poly |> dplyr::select(name_long, iso_a2)
  ) |>
    dplyr::mutate(overlap_ha = as.numeric(sf::st_area(geometry)) / 10000)

  winner <- inter |>
    sf::st_drop_geometry() |>
    dplyr::group_by(id) |>
    dplyr::slice_max(overlap_ha, n = 1, with_ties = FALSE) |>
    dplyr::ungroup() |>
    dplyr::select(id, name_long, iso_a2)

  ba_eu |>
    dplyr::left_join(winner, by = "id") |>
    dplyr::filter(!is.na(name_long))
}
