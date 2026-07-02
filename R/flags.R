# ==============================================================================
# flags.R
# Country flag machinery: ISO2 lookup, cached PNG download, and dominant-color
# extraction. This logic was copy-pasted three times in the original qmd
# (top_countries, compare_2017, year_compare chunks); consolidated here into a
# single implementation.
# Required packages (namespaced calls only, no library() here):
#   countrycode, sf, dplyr, tibble, purrr, curl, fs, png, stats, grDevices
# ==============================================================================

#' Map country names to lowercase ISO2 codes, with a custom_match table for
#' known countrycode mismatches and a fallback to the Europe reference
#' polygons' iso_a2 for any names countrycode() cannot resolve.
#' @param names_vec character vector of country names (e.g., name_long values)
#' @param eu_poly sf polygons per country with name_long and iso_a2 columns
#'   (from load_europe_polygons()$poly), used as a fallback lookup
#' @return tibble(name_long, iso2_lower)
name_to_iso2 <- function(names_vec, eu_poly) {
  base <- tibble::tibble(name_long = as.character(names_vec)) |>
    dplyr::distinct() |>
    dplyr::mutate(
      iso2 = countrycode::countrycode(
        name_long, origin = "country.name", destination = "iso2c",
        custom_match = c(
          "Czechia" = "CZ", "United Kingdom" = "GB", "North Macedonia" = "MK",
          "Moldova" = "MD", "Kosovo" = "XK"
        )
      )
    )

  map_iso_from_poly <- eu_poly |>
    sf::st_drop_geometry() |>
    dplyr::distinct(name_long, iso_a2) |>
    dplyr::rename(iso2_poly = iso_a2)

  base |>
    dplyr::left_join(map_iso_from_poly, by = "name_long") |>
    dplyr::mutate(
      iso2 = dplyr::coalesce(iso2, iso2_poly),
      iso2_lower = tolower(iso2)
    ) |>
    dplyr::select(name_long, iso2_lower)
}

#' Download small (w40) PNG flags from flagcdn.com, cached on disk so repeat
#' calls do not re-download existing files.
#' @param iso2_lower_vec character vector of lowercase ISO2 codes
#' @param flags_dir directory to cache flag PNGs in, created if missing
#' @return tibble(iso2_lower, flag_path); flag_path is NA if download failed
fetch_flags <- function(iso2_lower_vec, flags_dir = "assets/flags_rect") {
  fs::dir_create(flags_dir)
  iso2_vec <- unique(stats::na.omit(iso2_lower_vec))
  tibble::tibble(iso2_lower = iso2_vec) |>
    dplyr::mutate(flag_path = purrr::map_chr(iso2_lower, function(code) {
      dest <- file.path(flags_dir, sprintf("%s.png", code))
      if (!file.exists(dest)) {
        url <- sprintf("https://flagcdn.com/w40/%s.png", code)
        try(curl::curl_download(url, dest, quiet = TRUE), silent = TRUE)
      }
      if (file.exists(dest)) dest else NA_character_
    }))
}

#' Extract a dominant, non-white color from a flag PNG via k-means clustering
#' on non-transparent, non-near-white pixels. Uses a fixed local seed for
#' reproducible k-means; the global RNG state is saved and restored so calling
#' this helper never perturbs the caller's random stream.
#' @param path path to a PNG flag image
#' @return hex color string (falls back to "#444444" on any read/compute error)
dominant_flag_color <- function(path) {
  # Preserve the caller's RNG stream: set.seed(1) below is local to this call.
  old_seed <- if (exists(".Random.seed", envir = globalenv())) get(".Random.seed", envir = globalenv()) else NULL
  on.exit(if (!is.null(old_seed)) assign(".Random.seed", old_seed, envir = globalenv()) else if (exists(".Random.seed", envir = globalenv())) rm(".Random.seed", envir = globalenv()))

  res <- try({
    arr <- png::readPNG(path)
    rgb <- cbind(as.vector(arr[, , 1]), as.vector(arr[, , 2]), as.vector(arr[, , 3]))
    a   <- if (dim(arr)[3] >= 4) as.vector(arr[, , 4]) else rep(1, nrow(rgb))
    keep <- a > 0.8
    rgb  <- rgb[keep, , drop = FALSE]
    # drop near-white pixels
    keep2 <- rowMeans(rgb) < 0.95
    rgb <- rgb[keep2, , drop = FALSE]
    if (nrow(rgb) < 50) rgb <- rgb[keep, , drop = FALSE]
    set.seed(1)
    km <- stats::kmeans(rgb, centers = min(3, nrow(rgb)), iter.max = 15)
    dom <- km$centers[which.max(tabulate(km$cluster)), ]
    grDevices::rgb(dom[1], dom[2], dom[3])
  }, silent = TRUE)
  if (inherits(res, "try-error")) "#444444" else res
}

#' Convenience wrapper: build a full flag lookup table for a set of country
#' names -- ISO2 codes, cached local flag PNG paths, and dominant colors.
#' @param names_vec character vector of country names (e.g., name_long values)
#' @param eu_poly sf polygons per country (from load_europe_polygons()$poly)
#' @param flags_dir directory to cache flag PNGs in
#' @return tibble(name_long, iso2_lower, flag_path, col)
flag_table <- function(names_vec, eu_poly, flags_dir = "assets/flags_rect") {
  codes <- name_to_iso2(names_vec, eu_poly)
  flag_paths <- fetch_flags(codes$iso2_lower, flags_dir = flags_dir)
  flag_cols <- flag_paths |>
    dplyr::mutate(col = vapply(flag_path, dominant_flag_color, character(1)))

  codes |>
    dplyr::left_join(flag_paths, by = "iso2_lower") |>
    dplyr::left_join(flag_cols, by = c("iso2_lower", "flag_path")) |>
    dplyr::mutate(col = dplyr::coalesce(col, "#444444"))
}
