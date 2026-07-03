# ==============================================================================
# fetch_effis.R
# Fetch EFFIS rapid burnt-area perimeters (WFS ms:modis.ba.poly layer) for a
# set of fire years, one GeoJSON per year, into a dated snapshot directory.
# Usage:
#   Rscript scripts/fetch_effis.R                  # default: 2006:2026
#   Rscript scripts/fetch_effis.R 2023 2024 2025    # explicit years
#   Rscript scripts/fetch_effis.R 2020:2025         # a range
# Inputs:  none (network fetch from Copernicus EFFIS WFS)
# Outputs: DATA/snapshots/<today>/ba_<year>.geojson (one per year)
#          DATA/snapshots/<today>/MANIFEST.md (fetch log + per-year summary)
# Notes:   The EFFIS WFS server is flaky (GetCapabilities can hang entirely;
#          intermittent HTTP/2 stream errors). We force HTTP/1.1 and shell out
#          to the curl binary (not the R curl package) so --http1.1 and
#          --retry are enforced exactly as tested against the live server.
# Required packages: sf, jsonlite (namespaced calls only, no library() here
#   besides the two below -- consistent with R/*.R convention in this repo)
# ==============================================================================

library(sf)
library(jsonlite)

# --- Root check: refuse to run from the wrong working directory (INV-16) ---
stopifnot(dir.exists("R"))

# ---- Config -----------------------------------------------------------------
effis_base_url <- "https://maps.effis.emergency.copernicus.eu/effis"
wfs_typename    <- "ms:modis.ba.poly"
default_years   <- 2006:2026
request_timeout <- 300      # seconds, per curl invocation (-m)
max_attempts    <- 2        # outer attempts per year, on top of curl's own --retry
polite_sleep    <- 3        # seconds between successive requests
current_year    <- as.integer(format(Sys.Date(), "%Y"))

snapshot_date <- format(Sys.Date(), "%Y-%m-%d")
snapshot_dir  <- file.path("DATA", "snapshots", snapshot_date)
dir.create(snapshot_dir, recursive = TRUE, showWarnings = FALSE)

# ---- Args ---------------------------------------------------------------
#' Parse command-line year arguments, allowing bare years ("2023") and
#' ranges ("2020:2025"), and returns a sorted unique integer vector.
#' @param args character vector from commandArgs(trailingOnly = TRUE)
#' @param default fallback integer vector if args is empty
#' @return sorted unique integer vector of years
parse_year_args <- function(args, default) {
  if (length(args) == 0) return(default)
  parsed <- lapply(args, function(a) {
    if (grepl("^[0-9]{4}:[0-9]{4}$", a)) {
      bounds <- as.integer(strsplit(a, ":", fixed = TRUE)[[1]])
      seq(bounds[1], bounds[2])
    } else if (grepl("^[0-9]{4}$", a)) {
      as.integer(a)
    } else {
      stop(sprintf("Unrecognized year argument: '%s' (expected YYYY or YYYY:YYYY)", a))
    }
  })
  sort(unique(unlist(parsed)))
}

years <- parse_year_args(commandArgs(trailingOnly = TRUE), default_years)
message(sprintf("Fetching EFFIS ba.poly for %d year(s): %s", length(years), paste(range(years), collapse = "-")))
message(sprintf("Snapshot directory: %s", snapshot_dir))

# ---- URL / filter construction ----------------------------------------------
#' Build the OGC filter-encoded WFS GetFeature URL for a full calendar year of
#' FIREDATE values (verified endpoint pattern: <And> of two comparisons).
#' @param year integer year
#' @return character URL
build_effis_url <- function(year) {
  filter_xml <- paste0(
    "<Filter><And>",
    "<PropertyIsGreaterThanOrEqualTo><PropertyName>FIREDATE</PropertyName>",
    sprintf("<Literal>%d-01-01 00:00:00</Literal></PropertyIsGreaterThanOrEqualTo>", year),
    "<PropertyIsLessThanOrEqualTo><PropertyName>FIREDATE</PropertyName>",
    sprintf("<Literal>%d-12-31 23:59:59</Literal></PropertyIsLessThanOrEqualTo>", year),
    "</And></Filter>"
  )
  query <- paste0(
    "service=WFS&version=1.1.0&request=GetFeature",
    "&typename=", wfs_typename,
    "&outputformat=geojson",
    "&filter=", utils::URLencode(filter_xml, reserved = TRUE)
  )
  paste0(effis_base_url, "?", query)
}

# ---- Download -----------------------------------------------------------
#' Download one year's GeoJSON via the curl binary (not the R curl package):
#' HTTP/1.1 is forced because the server intermittently drops HTTP/2 streams,
#' and curl's own --retry handles transient failures; an outer loop adds a
#' second full attempt with backoff for cases curl's retry can't recover from
#' (e.g., a cold start after a long hang).
#' @param year integer year (used only for logging)
#' @param url character URL built by build_effis_url()
#' @param out_file destination path for the GeoJSON body
#' @return TRUE if a 200 response with a non-empty body was written, else FALSE
download_year <- function(year, url, out_file) {
  for (attempt in seq_len(max_attempts)) {
    message(sprintf("  [%s] year %d: fetch attempt %d/%d...",
                     format(Sys.time(), "%H:%M:%S"), year, attempt, max_attempts))
    curl_args <- c(
      "--http1.1",
      "--retry", "5",
      "--retry-all-errors",
      "--retry-delay", "5",
      "-m", as.character(request_timeout),
      "-sS",
      "-o", out_file,
      "-w", "%{http_code}",
      url
    )
    http_out <- suppressWarnings(system2("curl", curl_args, stdout = TRUE, stderr = FALSE))
    http_code <- if (length(http_out) > 0) http_out[length(http_out)] else NA_character_
    exit_status <- attr(http_out, "status")
    ok <- identical(http_code, "200") && (is.null(exit_status) || exit_status == 0) &&
      file.exists(out_file) && file.size(out_file) > 0

    if (ok) return(TRUE)

    message(sprintf("    attempt %d failed (http_code=%s, exit_status=%s)",
                     attempt, http_code, paste(exit_status, collapse = ",")))
    if (file.exists(out_file)) file.remove(out_file)
    if (attempt < max_attempts) Sys.sleep(10)
  }
  FALSE
}

# ---- Validation -----------------------------------------------------------
#' Validate a downloaded GeoJSON: confirm it parses (both as JSON and as sf),
#' is non-empty for completed seasons, and summarize FIREDATE range / AREA_HA.
#' Zero features (or unparseable JSON) is only acceptable for `current_year`,
#' whose season may have barely started; any other year with zero features
#' indicates a bad/empty server response and is treated as a hard error.
#' @param path path to the GeoJSON file
#' @param year integer year being validated
#' @return named list summarizing the file (n_features, dates, area, flags)
validate_year_file <- function(path, year) {
  raw_ok <- tryCatch({
    j <- jsonlite::fromJSON(path, simplifyVector = FALSE)
    identical(j[["type"]], "FeatureCollection")
  }, error = function(e) FALSE)
  if (!raw_ok) {
    stop(sprintf("year %d: response is not a valid GeoJSON FeatureCollection (%s)", year, path))
  }

  sfobj <- tryCatch(sf::st_read(path, quiet = TRUE), error = function(e) NULL)
  if (is.null(sfobj)) {
    stop(sprintf("year %d: sf::st_read() failed to parse %s", year, path))
  }

  n_feat <- nrow(sfobj)
  if (n_feat == 0 && year != current_year) {
    stop(sprintf(
      "year %d: zero features returned for a completed fire season (unexpected)", year
    ))
  }

  firedate <- if ("FIREDATE" %in% names(sfobj)) {
    suppressWarnings(as.POSIXct(sfobj[["FIREDATE"]], tz = "UTC"))
  } else {
    as.POSIXct(character(0))
  }
  area_ha_sum <- if ("AREA_HA" %in% names(sfobj)) {
    suppressWarnings(sum(as.numeric(sfobj[["AREA_HA"]]), na.rm = TRUE))
  } else {
    NA_real_
  }

  list(
    year = year,
    n_features = n_feat,
    min_firedate = if (n_feat > 0 && length(stats::na.omit(firedate)) > 0)
      format(min(firedate, na.rm = TRUE)) else NA_character_,
    max_firedate = if (n_feat > 0 && length(stats::na.omit(firedate)) > 0)
      format(max(firedate, na.rm = TRUE)) else NA_character_,
    area_ha_sum = area_ha_sum,
    round_number_flag = n_feat > 0 && n_feat %% 10000 == 0,
    file_size_bytes = file.size(path)
  )
}

# ---- Main fetch loop --------------------------------------------------------
#' Fetch + validate a single year end-to-end; skips download if the file
#' already exists (idempotent re-runs), but always (re-)validates it so a
#' partial/corrupt file left over from a previous crash is still caught.
#' @param year integer year
#' @return named list: status ("ok"/"failed"), plus validate_year_file() fields
process_year <- function(year) {
  out_file <- file.path(snapshot_dir, sprintf("ba_%d.geojson", year))

  if (file.exists(out_file)) {
    message(sprintf("  year %d: %s already exists, skipping download", year, basename(out_file)))
  } else {
    url <- build_effis_url(year)
    ok <- download_year(year, url, out_file)
    Sys.sleep(polite_sleep)  # be polite to the flaky server regardless of outcome
    if (!ok) {
      return(list(year = year, status = "failed", error = "download failed after retries"))
    }
  }

  summary_or_err <- tryCatch(
    validate_year_file(out_file, year),
    error = function(e) e
  )
  if (inherits(summary_or_err, "error")) {
    return(list(year = year, status = "failed", error = conditionMessage(summary_or_err)))
  }
  c(list(status = "ok"), summary_or_err)
}

results <- vector("list", length(years))
for (i in seq_along(years)) {
  results[[i]] <- process_year(years[i])
}

# Retry failed years once more at the end (transient server flakiness) -------
failed_idx <- which(vapply(results, function(r) identical(r$status, "failed"), logical(1)))
if (length(failed_idx) > 0) {
  message(sprintf("Retrying %d failed year(s) once more: %s",
                   length(failed_idx), paste(years[failed_idx], collapse = ", ")))
  for (i in failed_idx) {
    out_file <- file.path(snapshot_dir, sprintf("ba_%d.geojson", years[i]))
    if (file.exists(out_file)) file.remove(out_file)  # clear any partial file before retry
    results[[i]] <- process_year(years[i])
  }
}

# ---- Manifest -----------------------------------------------------------
fmt_bytes <- function(b) {
  if (is.na(b)) return("NA")
  scales_unit <- c("B", "KB", "MB", "GB")
  i <- 1L
  while (b >= 1024 && i < length(scales_unit)) {
    b <- b / 1024
    i <- i + 1L
  }
  sprintf("%.1f %s", b, scales_unit[i])
}

manifest_rows <- vapply(results, function(r) {
  if (identical(r$status, "ok")) {
    sprintf(
      "| %d | %s | %s | %s | %s | %s | %s |",
      r$year, format(r$n_features, big.mark = ","),
      fmt_bytes(r$file_size_bytes),
      ifelse(is.na(r$min_firedate), "NA", r$min_firedate),
      ifelse(is.na(r$max_firedate), "NA", r$max_firedate),
      format(round(r$area_ha_sum, 0), big.mark = ","),
      if (isTRUE(r$round_number_flag)) "OK (**round feature count -- check for paging ceiling**)" else "OK"
    )
  } else {
    sprintf("| %d | -- | -- | -- | -- | -- | **FAILED: %s** |", r$year, r$error)
  }
}, character(1))

n_ok <- sum(vapply(results, function(r) identical(r$status, "ok"), logical(1)))
n_failed <- length(results) - n_ok

manifest_lines <- c(
  "# EFFIS fetch manifest",
  "",
  sprintf("- **Fetched:** %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  sprintf("- **Years requested:** %s (%d total)", paste(range(years), collapse = "-"), length(years)),
  sprintf("- **Years OK:** %d, **Years failed:** %d", n_ok, n_failed),
  sprintf("- **Source URL pattern:** `%s?service=WFS&version=1.1.0&request=GetFeature&typename=%s&outputformat=geojson&filter=<OGC-Filter-XML-on-FIREDATE>`",
          effis_base_url, wfs_typename),
  "",
  "## Per-year summary",
  "",
  "| Year | Features | File size | Min FIREDATE | Max FIREDATE | Sum AREA_HA | Status |",
  "|---|---|---|---|---|---|---|",
  manifest_rows,
  "",
  "## Schema notes",
  "",
  "- Layer: `ms:modis.ba.poly` (WFS GetFeature, GeoJSON output).",
  "- Properties: `id`, `FIREDATE`, `FINALDATE`, `LASTUPDATE`, `COUNTRY` (ISO2, incl.",
  "  non-EU e.g. DZ/UA), `PROVINCE`, `COMMUNE`, `AREA_HA`, `BROADLEA`, `CONIFER`,",
  "  `MIXED`, `SCLEROPH`, `TRANSIT`, `OTHERNATLC`, `AGRIAREAS`, `ARTIFSURF`,",
  "  `OTHERLC`, `PERCNA2K`, `CLASS`.",
  "- `COUNTRY` is EFFIS's own attribute and is kept as a cross-check only; this",
  "  pipeline's authoritative country tag is computed downstream by maximum",
  "  geometric overlap with reference polygons (see `R/geo.R::tag_countries()`),",
  "  not by trusting `COUNTRY` directly.",
  "- Perimeters are EFFIS *rapid* burnt-area estimates from satellite mapping,",
  "  typically covering fires of roughly ≥ 30-50 ha; smaller fires are",
  "  systematically under-represented.",
  "- As of 2026-07, the layer is still named `modis.ba.poly` for historical",
  "  reasons; EFFIS has been transitioning its rapid-mapping product from MODIS",
  "  to Sentinel-2-based detection, so per-year comparability of the *smallest*",
  "  detectable fires may shift across the archive even though the layer name",
  "  has not changed.",
  "- A round feature count (exact multiple of 10,000) is flagged above because",
  "  it may indicate a server-side result-paging ceiling rather than the true",
  "  total; such years should be re-fetched with STARTINDEX paging if confirmed.",
  ""
)

writeLines(manifest_lines, file.path(snapshot_dir, "MANIFEST.md"))
message(sprintf("Wrote manifest: %s", file.path(snapshot_dir, "MANIFEST.md")))
message(sprintf("Done: %d/%d years OK, %d failed.", n_ok, length(years), n_failed))
if (n_failed > 0) {
  message("Failed years: ", paste(years[vapply(results, function(r) identical(r$status, "failed"), logical(1))], collapse = ", "))
}
