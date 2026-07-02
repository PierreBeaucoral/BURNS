# ==============================================================================
# helpers.R
# Small utility functions used across the BURNS wildfire pipeline: numeric
# parsing, robust date parsing, and a shared "hectares, SI-scaled" label
# formatter for ggplot axes.
# Required packages (namespaced calls only, no library() here):
#   readr, lubridate, scales
# ==============================================================================

#' Parse a numeric column that may use EU-style decimal commas / NBSP spacing
#' @param x vector (character or numeric) to coerce to numeric
#' @return numeric vector
to_num <- function(x) {
  if (is.numeric(x)) return(x)
  x <- trimws(as.character(x))
  x <- gsub("\u00A0|\\s", "", x)   # remove spaces / NBSP
  x <- gsub(",", ".", x)           # EU decimal comma -> dot
  readr::parse_number(x, locale = readr::locale(decimal_mark = "."))
}

#' Parse dates from heterogeneous formats (Date, POSIXt, or various string orders)
#' @param x vector to coerce to Date
#' @return Date vector
parse_date_any <- function(x) {
  if (inherits(x, "Date")) return(x)
  if (inherits(x, "POSIXt")) return(as.Date(x))
  s <- as.character(x)
  s <- substr(s, 1, 19)
  y <- suppressWarnings(lubridate::parse_date_time(
    s, orders = c("Ymd", "Y-m-d", "dmy", "d-m-Y", "m/d/Y", "d/m/Y", "Ymd HMS", "Y-m-d H:M:S")
  ))
  as.Date(y)
}

#' Shared label formatter: SI-scaled hectares (e.g. "12k ha") for ggplot axes
lab_si_ha <- scales::label_number(scale_cut = scales::cut_si("ha"))
