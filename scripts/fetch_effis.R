# ==============================================================================
# fetch_effis.R
# Fetch EFFIS rapid burnt-area perimeters (WFS ms:modis.ba.poly layer) for a
# set of fire years, one GeoJSON per year, into a dated snapshot directory.
# Usage:
#   Rscript scripts/fetch_effis.R                  # default: 2016:2026
#   Rscript scripts/fetch_effis.R 2023 2024 2025    # explicit years
#   Rscript scripts/fetch_effis.R 2020:2025         # a range
# Inputs:  none (network fetch from Copernicus EFFIS WFS)
# Outputs: DATA/snapshots/<today>/ba_<year>.geojson (one per year)
#          DATA/snapshots/<today>/MANIFEST.md (fetch log + per-year summary)
#
# VERIFIED SERVER FACTS (probed 2026-07; design constraints, do not "simplify"):
#   1. UNCAPPED GetFeature requests hang forever (as does GetCapabilities).
#      Requests WITH maxFeatures return in ~9-14 s. NEVER request without
#      maxFeatures -- hence the paging loop below.
#   2. Paging works: maxFeatures=N + startindex=K returns distinct features.
#      Every paged request carries &sortby=id so page order is deterministic
#      (MapServer's default order is not guaranteed stable); merged features
#      are additionally deduped by their id property as a safety net.
#   3. resultType=hits is cheap and returns XML with numberOfFeatures="NNN";
#      used (with retries -- it intermittently times out too) to know the
#      expected count per year before paging. If hits fails, we page blind
#      and stop when a page comes back short.
#   4. Archive coverage: 2010/2012/2014 = 0 features; 2016 = 1331. The layer
#      effectively starts in 2016 -- hence default_years = 2016:2026. The
#      2023 (~9.4k) -> 2024 (~20k) count doubling reflects the
#      MODIS -> Sentinel-2 detection-threshold shift, not more fire.
#   5. The server is generally flaky: intermittent HTTP/2 stream drops and
#      502/500s. We force HTTP/1.1 and shell out to the curl binary (not the
#      R curl package) so --http1.1/--retry are enforced exactly as tested.
#
# Required packages: sf, jsonlite (loaded below; all other calls namespaced,
#   consistent with the R/*.R convention in this repo)
# ==============================================================================

library(sf)
library(jsonlite)

# --- Root check: refuse to run from the wrong working directory (INV-16) ---
stopifnot(dir.exists("R"))

# GDAL caps single GeoJSON features at ~200 MB by default; the 2020 layer
# contains one giant multi-polygon complex that exceeds it and made st_read()
# fail. 0 = no per-object size limit (memory is fine: pages are <= 1000 feats).
Sys.setenv(OGR_GEOJSON_MAX_OBJ_SIZE = "0")

# ---- Config -----------------------------------------------------------------
effis_base_url  <- "https://maps.effis.emergency.copernicus.eu/effis"
wfs_typename    <- "ms:modis.ba.poly"
default_years   <- 2016:2026   # layer has no features before 2016 (verified)
page_size       <- 1000L       # maxFeatures per paged request (fact 1: required)
page_timeout    <- 120         # seconds per page request (-m)
hits_timeout    <- 60          # seconds per hits request (-m)
hits_attempts   <- 3L          # outer attempts for the hits count
max_page_tries  <- 2L          # outer attempts per page, on top of curl --retry
page_sleep      <- 2           # polite seconds between page requests
year_sleep      <- 3           # polite seconds between years
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
message(sprintf("Fetching EFFIS ba.poly for %d year(s): %s",
                 length(years), paste(range(years), collapse = "-")))
message(sprintf("Snapshot directory: %s", snapshot_dir))

# ---- URL / filter construction ----------------------------------------------
#' Build the URL-encoded OGC filter for a full calendar year of FIREDATE
#' values (verified pattern: <And> of two comparisons).
#' @param year integer year
#' @return character, URL-encoded filter XML
build_year_filter <- function(year) {
  filter_xml <- paste0(
    "<Filter><And>",
    "<PropertyIsGreaterThanOrEqualTo><PropertyName>FIREDATE</PropertyName>",
    sprintf("<Literal>%d-01-01 00:00:00</Literal></PropertyIsGreaterThanOrEqualTo>", year),
    "<PropertyIsLessThanOrEqualTo><PropertyName>FIREDATE</PropertyName>",
    sprintf("<Literal>%d-12-31 23:59:59</Literal></PropertyIsLessThanOrEqualTo>", year),
    "</And></Filter>"
  )
  utils::URLencode(filter_xml, reserved = TRUE)
}

#' Build the resultType=hits URL for a year (XML response, no outputformat).
#' @param year integer year
#' @return character URL
build_hits_url <- function(year) {
  paste0(
    effis_base_url, "?service=WFS&version=1.1.0&request=GetFeature",
    "&typename=", wfs_typename,
    "&resultType=hits",
    "&filter=", build_year_filter(year)
  )
}

#' Build one paged GeoJSON GetFeature URL: maxFeatures cap (fact 1),
#' startindex offset, and sortby=id for deterministic page order (fact 2).
#' @param year integer year
#' @param startindex 0-based feature offset
#' @return character URL
build_page_url <- function(year, startindex) {
  paste0(
    effis_base_url, "?service=WFS&version=1.1.0&request=GetFeature",
    "&typename=", wfs_typename,
    "&outputformat=geojson",
    "&maxFeatures=", page_size,
    "&startindex=", startindex,
    "&sortby=id",
    "&filter=", build_year_filter(year)
  )
}

# ---- HTTP helpers -----------------------------------------------------------
#' Run one curl download with the flaky-server survival kit: HTTP/1.1 forced,
#' curl-level retries, hard timeout, HTTP status captured via -w.
#' @param url request URL
#' @param out_file destination path for the response body
#' @param timeout_sec hard per-request timeout (-m)
#' @return TRUE if HTTP 200 and a non-empty body was written, else FALSE
curl_fetch <- function(url, out_file, timeout_sec) {
  # system2() joins args into a shell command line: the URL's literal '&'
  # query separators MUST be shQuote()d or the shell splits the command
  # (symptom: curl silently requests the bare endpoint and gets a 502 page).
  curl_args <- c(
    "--http1.1",
    "--retry", "3",
    "--retry-all-errors",
    "--retry-delay", "5",
    "-m", as.character(timeout_sec),
    "-sS",
    "-o", shQuote(out_file),
    "-w", shQuote("%{http_code}"),
    shQuote(url)
  )
  http_out <- suppressWarnings(system2("curl", curl_args, stdout = TRUE, stderr = FALSE))
  http_code <- if (length(http_out) > 0) http_out[length(http_out)] else NA_character_
  exit_status <- attr(http_out, "status")
  identical(http_code, "200") && (is.null(exit_status) || exit_status == 0) &&
    file.exists(out_file) && file.size(out_file) > 0
}

#' Get the server-side feature count for a year via resultType=hits (fact 3).
#' @param year integer year
#' @return integer count, or NA_integer_ if all attempts fail
fetch_hits <- function(year) {
  hits_file <- tempfile(fileext = ".xml")
  on.exit(unlink(hits_file), add = TRUE)
  for (attempt in seq_len(hits_attempts)) {
    ok <- curl_fetch(build_hits_url(year), hits_file, hits_timeout)
    if (ok) {
      xml_txt <- paste(readLines(hits_file, warn = FALSE), collapse = "")
      m <- regmatches(xml_txt, regexpr('numberOfFeatures="[0-9]+"', xml_txt))
      if (length(m) == 1) {
        return(as.integer(gsub("[^0-9]", "", m)))
      }
    }
    message(sprintf("    hits attempt %d/%d failed for year %d", attempt, hits_attempts, year))
    if (attempt < hits_attempts) Sys.sleep(5)
  }
  NA_integer_
}

#' Read one downloaded page into an sf object. An empty FeatureCollection
#' (startindex past the end, or a short final page) is returned as NULL
#' rather than an error; genuinely unparseable responses raise an error.
#' @param path path to the page GeoJSON
#' @return sf object, or NULL if the page contains zero features
read_page_sf <- function(path) {
  sfobj <- tryCatch(sf::st_read(path, quiet = TRUE), error = function(e) e)
  if (!inherits(sfobj, "error")) {
    if (nrow(sfobj) == 0) return(NULL)
    return(sfobj)
  }
  # st_read can refuse empty/fieldless collections -- confirm via jsonlite
  parsed <- tryCatch(jsonlite::fromJSON(path, simplifyVector = FALSE),
                     error = function(e) NULL)
  if (!is.null(parsed) && identical(parsed[["type"]], "FeatureCollection") &&
      length(parsed[["features"]]) == 0) {
    return(NULL)
  }
  stop(sprintf("unparseable page response: %s", conditionMessage(sfobj)))
}

# ---- Per-year download (hits + paging + merge) --------------------------------
#' Download one year's features: get the expected count via resultType=hits,
#' then page through maxFeatures windows (sorted by id), merge the pages,
#' dedupe by the id property, and write a single GeoJSON. If hits is
#' unavailable, pages blind and stops at the first short/empty page.
#' @param year integer year
#' @param out_file destination path for the merged GeoJSON
#' @return list(ok, hits, n_merged, error)
download_year <- function(year, out_file) {
  message(sprintf("  [%s] year %d: requesting hits count...",
                   format(Sys.time(), "%H:%M:%S"), year))
  hits <- fetch_hits(year)
  if (is.na(hits)) {
    message(sprintf("    hits unavailable for %d -- paging blind (stop on short page)", year))
  } else {
    message(sprintf("    year %d: server reports %d features (~%d pages)",
                     year, hits, max(1L, as.integer(ceiling(hits / page_size)))))
  }

  # Rough upper bound on page count: known hits + slack, or a hard cap when
  # paging blind (60 pages = 60k features, ~3x the largest observed year).
  pages <- if (is.na(hits)) vector("list", 60L) else
    vector("list", max(1L, as.integer(ceiling(hits / page_size)) + 5L))
  n_pages <- 0L
  startindex <- 0L
  repeat {
    page_file <- tempfile(fileext = ".geojson")
    page_ok <- FALSE
    for (try_i in seq_len(max_page_tries)) {
      message(sprintf("  [%s] year %d: page startindex=%d (attempt %d/%d)",
                       format(Sys.time(), "%H:%M:%S"), year, startindex, try_i, max_page_tries))
      if (curl_fetch(build_page_url(year, startindex), page_file, page_timeout)) {
        page_ok <- TRUE
        break
      }
      if (try_i < max_page_tries) Sys.sleep(10)
    }
    if (!page_ok) {
      unlink(page_file)
      return(list(ok = FALSE, hits = hits, n_merged = NA_integer_,
                  error = sprintf("page startindex=%d failed after retries", startindex)))
    }

    page_sf <- tryCatch(read_page_sf(page_file), error = function(e) e)
    unlink(page_file)
    if (inherits(page_sf, "error")) {
      return(list(ok = FALSE, hits = hits, n_merged = NA_integer_,
                  error = sprintf("page startindex=%d: %s", startindex,
                                  conditionMessage(page_sf))))
    }

    n_page <- if (is.null(page_sf)) 0L else nrow(page_sf)
    if (n_page > 0) {
      n_pages <- n_pages + 1L
      if (n_pages > length(pages)) pages <- c(pages, vector("list", 10L))  # rare overflow
      pages[[n_pages]] <- page_sf
    }

    # Stop conditions: short/empty page always ends the loop; with a known
    # hits count we also stop once the next window would start past the end.
    if (n_page < page_size) break
    startindex <- startindex + page_size
    if (!is.na(hits) && startindex >= hits) break
    Sys.sleep(page_sleep)
  }
  pages <- pages[seq_len(n_pages)]

  if (n_pages == 0L) {
    if (year == current_year) {
      # Season may have barely started: write an empty, valid FeatureCollection.
      writeLines('{"type": "FeatureCollection", "features": []}', out_file)
      return(list(ok = TRUE, hits = hits, n_merged = 0L, error = NA_character_))
    }
    return(list(ok = FALSE, hits = hits, n_merged = 0L,
                error = "zero features returned for a completed fire season"))
  }

  merged <- do.call(rbind, pages)
  merged <- merged[!duplicated(merged$id), ]  # safety net (fact 2)
  if (file.exists(out_file)) file.remove(out_file)
  sf::st_write(merged, out_file, driver = "GeoJSON", quiet = TRUE)
  list(ok = TRUE, hits = hits, n_merged = nrow(merged), error = NA_character_)
}

# ---- Validation -----------------------------------------------------------
#' Validate a merged GeoJSON: confirm it parses (as JSON and as sf), is
#' non-empty for completed seasons, and summarize FIREDATE range / AREA_HA.
#' Zero features is only acceptable for `current_year` (season just started);
#' any other year with zero features is a hard error. Also compares the file's
#' feature count to the server's hits count (>2% divergence is flagged --
#' the live current-season layer legitimately moves between requests).
#' @param path path to the GeoJSON file
#' @param year integer year being validated
#' @param hits server-side count from resultType=hits (NA if unavailable)
#' @return named list summarizing the file (n_features, dates, area, flags)
validate_year_file <- function(path, year, hits = NA_integer_) {
  raw_ok <- tryCatch({
    j <- jsonlite::fromJSON(path, simplifyVector = FALSE)
    identical(j[["type"]], "FeatureCollection")
  }, error = function(e) FALSE)
  if (!raw_ok) {
    stop(sprintf("year %d: not a valid GeoJSON FeatureCollection (%s)", year, path))
  }

  sfobj <- tryCatch(sf::st_read(path, quiet = TRUE), error = function(e) NULL)
  n_feat <- if (is.null(sfobj)) 0L else nrow(sfobj)
  if (is.null(sfobj) && year != current_year) {
    stop(sprintf("year %d: sf::st_read() failed to parse %s", year, path))
  }
  if (n_feat == 0 && year != current_year) {
    stop(sprintf("year %d: zero features for a completed fire season (unexpected)", year))
  }

  firedate <- if (n_feat > 0 && "FIREDATE" %in% names(sfobj)) {
    suppressWarnings(as.POSIXct(sfobj[["FIREDATE"]], tz = "UTC"))
  } else {
    as.POSIXct(character(0))
  }
  area_ha_sum <- if (n_feat > 0 && "AREA_HA" %in% names(sfobj)) {
    suppressWarnings(sum(as.numeric(sfobj[["AREA_HA"]]), na.rm = TRUE))
  } else {
    NA_real_
  }
  hits_mismatch <- !is.na(hits) && hits > 0 &&
    abs(n_feat - hits) / hits > 0.02

  list(
    year = year,
    hits = hits,
    n_features = n_feat,
    min_firedate = if (length(stats::na.omit(firedate)) > 0)
      format(min(firedate, na.rm = TRUE)) else NA_character_,
    max_firedate = if (length(stats::na.omit(firedate)) > 0)
      format(max(firedate, na.rm = TRUE)) else NA_character_,
    area_ha_sum = area_ha_sum,
    hits_mismatch = hits_mismatch,
    file_size_bytes = file.size(path)
  )
}

# ---- Main fetch loop --------------------------------------------------------
#' Fetch + validate a single year end-to-end; skips download if the file
#' already exists (idempotent re-runs; hits comparison then unavailable), but
#' always (re-)validates so a corrupt leftover file is still caught.
#' @param year integer year
#' @return named list: status ("ok"/"failed"), plus validate_year_file() fields
process_year <- function(year) {
  out_file <- file.path(snapshot_dir, sprintf("ba_%d.geojson", year))
  hits <- NA_integer_

  if (file.exists(out_file)) {
    message(sprintf("  year %d: %s already exists, skipping download",
                     year, basename(out_file)))
  } else {
    dl <- download_year(year, out_file)
    Sys.sleep(year_sleep)  # be polite to the flaky server regardless of outcome
    if (!dl$ok) {
      return(list(year = year, status = "failed", error = dl$error))
    }
    hits <- dl$hits
  }

  summary_or_err <- tryCatch(
    validate_year_file(out_file, year, hits = hits),
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
    if (file.exists(out_file)) file.remove(out_file)  # clear partial file first
    results[[i]] <- process_year(years[i])
  }
}

# ---- Manifest -----------------------------------------------------------
#' Human-readable file size (B/KB/MB/GB) for the manifest table.
#' @param b numeric byte count (NA tolerated)
#' @return character label
fmt_bytes <- function(b) {
  if (is.na(b)) return("NA")
  units <- c("B", "KB", "MB", "GB")
  i <- 1L
  while (b >= 1024 && i < length(units)) {
    b <- b / 1024
    i <- i + 1L
  }
  sprintf("%.1f %s", b, units[i])
}

manifest_rows <- vapply(results, function(r) {
  if (identical(r$status, "ok")) {
    status_txt <- "OK"
    if (isTRUE(r$hits_mismatch)) {
      status_txt <- sprintf(
        "OK (**merged %d vs hits %d differ >2%% -- live layer moved or paging gap**)",
        r$n_features, r$hits
      )
    }
    sprintf(
      "| %d | %s | %s | %s | %s | %s | %s | %s |",
      r$year,
      ifelse(is.na(r$hits), "--", format(r$hits, big.mark = ",")),
      format(r$n_features, big.mark = ","),
      fmt_bytes(r$file_size_bytes),
      ifelse(is.na(r$min_firedate), "NA", r$min_firedate),
      ifelse(is.na(r$max_firedate), "NA", r$max_firedate),
      ifelse(is.na(r$area_ha_sum), "NA",
             format(round(r$area_ha_sum, 0), big.mark = ",", scientific = FALSE)),
      status_txt
    )
  } else {
    sprintf("| %d | -- | -- | -- | -- | -- | -- | **FAILED: %s** |", r$year, r$error)
  }
}, character(1))

n_ok <- sum(vapply(results, function(r) identical(r$status, "ok"), logical(1)))
n_failed <- length(results) - n_ok

manifest_lines <- c(
  "# EFFIS fetch manifest",
  "",
  sprintf("- **Fetched:** %s", format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z")),
  sprintf("- **Years requested:** %s (%d total)",
          paste(range(years), collapse = "-"), length(years)),
  sprintf("- **Years OK:** %d, **Years failed:** %d", n_ok, n_failed),
  sprintf(paste0("- **Source URL pattern:** `%s?service=WFS&version=1.1.0&request=GetFeature",
                 "&typename=%s&outputformat=geojson&maxFeatures=%d&startindex=<K>&sortby=id",
                 "&filter=<OGC-Filter-XML-on-FIREDATE>` (paged; expected count via",
                 " `resultType=hits`)"),
          effis_base_url, wfs_typename, page_size),
  "",
  "## Per-year summary",
  "",
  "| Year | Hits | Features | File size | Min FIREDATE | Max FIREDATE | Sum AREA_HA | Status |",
  "|---|---|---|---|---|---|---|---|",
  manifest_rows,
  "",
  "## Schema notes",
  "",
  "- Layer: `ms:modis.ba.poly` (WFS GetFeature, GeoJSON output, paged with",
  "  `maxFeatures`/`startindex`/`sortby=id`; uncapped requests hang server-side).",
  "- Properties: `id`, `FIREDATE`, `FINALDATE`, `LASTUPDATE`, `COUNTRY` (ISO2, incl.",
  "  non-EU e.g. DZ/UA), `PROVINCE`, `COMMUNE`, `AREA_HA`, `BROADLEA`, `CONIFER`,",
  "  `MIXED`, `SCLEROPH`, `TRANSIT`, `OTHERNATLC`, `AGRIAREAS`, `ARTIFSURF`,",
  "  `OTHERLC`, `PERCNA2K`, `CLASS`.",
  "- `COUNTRY` is EFFIS's own attribute and is kept as a cross-check only; this",
  "  pipeline's authoritative country tag is computed downstream by maximum",
  "  geometric overlap with reference polygons (see `R/geo.R::tag_countries()`),",
  "  not by trusting `COUNTRY` directly.",
  "",
  "## Coverage & comparability caveats",
  "",
  "- **Archive starts in 2016.** Verified via `resultType=hits`: 2010/2012/2014",
  "  return 0 features in this layer; 2016 is the first year with data (1,331",
  "  features). Pre-2016 seasons are simply absent from `modis.ba.poly` and are",
  "  not fetched.",
  "- Perimeters are EFFIS *rapid* burnt-area estimates from satellite mapping,",
  "  typically covering fires of roughly >= 30-50 ha; smaller fires are",
  "  systematically under-represented.",
  "- **MODIS -> Sentinel-2 transition.** The layer is still named",
  "  `modis.ba.poly` (as of 2026-07) for historical reasons, but EFFIS moved its",
  "  rapid mapping to Sentinel-2-based detection. The jump from ~9.4k features",
  "  (2023) to ~20k (2024) reflects this detection-threshold shift -- smaller",
  "  fires became detectable -- not a doubling of fire activity. Cross-year",
  "  comparisons of feature COUNTS are therefore not apples-to-apples;",
  "  comparisons of burned AREA of large fires are safer.",
  "- Feature counts are checked against the server's `resultType=hits` count;",
  "  a >2% divergence is flagged in the table above (the live current-season",
  "  layer legitimately changes between requests).",
  ""
)

writeLines(manifest_lines, file.path(snapshot_dir, "MANIFEST.md"))
message(sprintf("Wrote manifest: %s", file.path(snapshot_dir, "MANIFEST.md")))
message(sprintf("Done: %d/%d years OK, %d failed.", n_ok, length(years), n_failed))
if (n_failed > 0) {
  message("Failed years: ",
          paste(years[vapply(results, function(r) identical(r$status, "failed"), logical(1))],
                collapse = ", "))
}
