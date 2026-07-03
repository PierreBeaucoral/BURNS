#!/usr/bin/env bash
# ==============================================================================
# update_site.sh
# Local weekly refresh-and-render flow for the BURNS wildfire tracker.
# Replaces the old CI-render model (formerly .github/workflows/render.yml,
# now deleted). Reasons the render moved local:
#   - EFFIS's WFS server is too flaky for unattended CI fetching (uncapped
#     requests hang, intermittent 502/500s -- see scripts/fetch_effis.R
#     header for the verified server facts and the retry/paging logic that
#     compensates for it; that fragility is manageable interactively but not
#     safe to leave unattended on a CI schedule).
#   - The raw per-year GeoJSON snapshots are too heavy to commit to the repo
#     (tens to hundreds of MB per year; DATA/snapshots/ is git-ignored).
#   - rnaturalearthhires (needed for the Europe reference polygons) is not on
#     CRAN -- it ships from the ropensci r-universe only -- which complicates
#     an automated CI install.
# So the fetch + render happens locally, on demand (weekly during fire
# season), and only the rendered _site/ is ever published.
#
# Steps:
#   1. Fetch today's EFFIS snapshot: Rscript scripts/fetch_effis.R with a
#      years arg covering the full archive (2016:<current year>).
#   2. Completeness gate: abort unless every expected ba_<year>.geojson
#      (2016..current year) exists in today's snapshot directory.
#   3. quarto render (abort on nonzero exit).
#   4. Print (but do NOT run) the `quarto publish gh-pages` command --
#      publishing is the user's explicit, separate action.
#
# Usage:
#   scripts/update_site.sh              # fetch + gate + render + print publish command
#   scripts/update_site.sh --no-fetch   # skip step 1 (render an existing snapshot)
#
# Testing the completeness gate without touching the EFFIS server: source
# this file (functions only run, nothing executes) and call check_completeness
# directly against an existing snapshot directory, e.g.:
#   source scripts/update_site.sh
#   check_completeness "DATA/snapshots/2026-07-03" 2016 2026
#
# Inputs:  DATA/snapshots/<today>/ (created by scripts/fetch_effis.R)
# Outputs: _site/ (via quarto render); no publish side effect
# ==============================================================================

CURRENT_YEAR="$(date +%Y)"
ARCHIVE_START_YEAR=2016
SNAPSHOT_DATE="$(date +%Y-%m-%d)"
SNAPSHOT_DIR="DATA/snapshots/${SNAPSHOT_DATE}"

#' Completeness gate: confirm every expected ba_<year>.geojson file
#' (start_year..end_year inclusive) exists in snapshot_dir. Prints a clear
#' per-year report; returns (does not exit -- safe to call when sourced)
#' non-zero if anything is missing.
#' @param snapshot_dir path to the dated snapshot directory to check
#' @param start_year integer, first expected year (archive start, 2016)
#' @param end_year integer, last expected year (current year)
#' @return 0 if all years present, 1 otherwise
check_completeness() {
  local snapshot_dir="$1"
  local start_year="$2"
  local end_year="$3"
  local missing=()
  local y
  local f

  if [[ ! -d "$snapshot_dir" ]]; then
    echo "ERROR: snapshot directory not found: $snapshot_dir" >&2
    return 1
  fi

  echo "Completeness gate: checking ${start_year}..${end_year} in ${snapshot_dir}"
  for (( y = start_year; y <= end_year; y++ )); do
    f="${snapshot_dir}/ba_${y}.geojson"
    if [[ -f "$f" ]]; then
      echo "  OK   ba_${y}.geojson"
    else
      echo "  MISS ba_${y}.geojson"
      missing+=("$y")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: snapshot ${snapshot_dir} is missing ba_<year>.geojson for: ${missing[*]}" >&2
    echo "       Re-run scripts/fetch_effis.R for the missing year(s) before rendering." >&2
    return 1
  fi

  echo "Completeness gate: PASS (${start_year}..${end_year} all present)"
  return 0
}

# ---- Main (only runs when executed directly, not when sourced) -------------
# Lets `source scripts/update_site.sh` load check_completeness() for testing
# without triggering a fetch, a render, or `set -e` in the caller's shell.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail

  # --- Root check: refuse to run from the wrong working directory (INV-16) ---
  if [[ ! -d "R" ]]; then
    echo "ERROR: update_site.sh must be run from the project root (R/ not found here)." >&2
    exit 1
  fi

  DO_FETCH=1
  for arg in "$@"; do
    case "$arg" in
      --no-fetch) DO_FETCH=0 ;;
      *)
        echo "Unrecognized argument: $arg (expected --no-fetch)" >&2
        exit 1
        ;;
    esac
  done

  if [[ "$DO_FETCH" -eq 1 ]]; then
    echo "== Step 1/3: fetching EFFIS snapshot (${ARCHIVE_START_YEAR}:${CURRENT_YEAR}) =="
    Rscript scripts/fetch_effis.R "${ARCHIVE_START_YEAR}:${CURRENT_YEAR}"
  else
    echo "== Step 1/3: skipped (--no-fetch) =="
  fi

  echo "== Step 2/3: completeness gate =="
  if ! check_completeness "$SNAPSHOT_DIR" "$ARCHIVE_START_YEAR" "$CURRENT_YEAR"; then
    echo "ABORTED: today's snapshot is incomplete; not rendering." >&2
    exit 1
  fi

  echo "== Step 3/3: quarto render =="
  if ! quarto render; then
    echo "ABORTED: quarto render failed (nonzero exit)." >&2
    exit 1
  fi

  echo ""
  echo "================================================================"
  echo "Render complete: _site/ is up to date with snapshot ${SNAPSHOT_DATE}."
  echo "Publishing is a separate, explicit step -- run it yourself when ready:"
  echo ""
  echo "    quarto publish gh-pages --no-prompt"
  echo ""
  echo "================================================================"
fi
