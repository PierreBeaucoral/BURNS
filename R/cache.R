# ==============================================================================
# cache.R
# Simple disk-cache wrapper for expensive computations (e.g., geometry ops,
# tile downloads). Base R only -- no package dependencies.
# ==============================================================================

#' Evaluate an expression and cache its result to disk as an .rds file, keyed
#' by name; subsequent calls with the same key read the cached .rds instead of
#' re-evaluating expr.
#' CONTRACT: key MUST encode all inputs that affect the result (e.g.
#' "tag_2025_6_8"); changing helper logic requires clearing DATA/cache/rds.
#' Alternatively, bump `version` to bust stale caches centrally without
#' touching every call site.
#' MANDATORY KEY INPUT -- snapshot identifier: any object derived (directly or
#' transitively) from DATA/snapshots/<date>/ba_<year>.geojson files MUST
#' encode the snapshot identifier (basename(snapshot_dir), e.g. "20260703")
#' in its key. A same-named snapshot directory can be re-fetched with revised
#' EFFIS perimeters (rapid mapping is corrected over time), so a key that
#' omits the snapshot would silently keep serving a stale .rds after a
#' re-fetch. This is in addition to, not instead of, encoding the other
#' inputs (year, window, tolerance, etc.).
#' @param key character string identifying the cached object (used as file name)
#' @param expr expression to evaluate if no cache file is present (lazily evaluated)
#' @param cache_dir directory to store cached .rds files in, created if missing
#' @param version integer appended to the file name (<key>_v<version>.rds);
#'   bump it to invalidate all caches written under earlier versions
#' @return the value of expr (freshly computed or loaded from cache)
cached <- function(key, expr, cache_dir = "DATA/cache/rds", version = 1) {
  stopifnot(is.character(key), length(key) == 1L, nzchar(key))

  if (!dir.exists(cache_dir)) dir.create(cache_dir, recursive = TRUE)
  cache_file <- file.path(cache_dir, sprintf("%s_v%s.rds", key, version))

  if (file.exists(cache_file)) {
    return(readRDS(cache_file))
  }

  result <- expr
  saveRDS(result, cache_file)
  result
}
