# ==============================================================================
# latest_snapshot.R
# Tiny helper: locate the most recent DATA/snapshots/<YYYY-MM-DD> directory.
# Used by site pages (index.qmd / tracker) to always read the freshest fetch
# without hardcoding a date.
# Required packages: none (base R only)
# ==============================================================================

#' Return the path to the newest dated snapshot directory under
#' DATA/snapshots/. Directory names sort correctly as strings because they
#' follow ISO 8601 (YYYY-MM-DD).
#' @param snapshots_root relative path to the snapshots root, default
#'   "DATA/snapshots"
#' @return character path to the latest snapshot directory, or NA_character_
#'   if none exist
latest_snapshot <- function(snapshots_root = file.path("DATA", "snapshots")) {
  if (!dir.exists(snapshots_root)) return(NA_character_)

  candidates <- list.dirs(snapshots_root, full.names = FALSE, recursive = FALSE)
  candidates <- candidates[grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", candidates)]
  if (length(candidates) == 0) return(NA_character_)

  file.path(snapshots_root, max(candidates))
}
