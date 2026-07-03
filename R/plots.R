# ==============================================================================
# plots.R
# Shared figure builders used by BOTH index.qmd (tracker) and posts/2026.qmd
# (season post), so the two pages render the exact same envelope chart from
# the exact same cached object. Follows the theme.R precedent: ggplot2 calls
# are namespaced, no library() here.
# Required packages: ggplot2, scales, lubridate
# Depends on: R/helpers.R (lab_si_ha), R/theme.R (theme_burns)
# ==============================================================================

#' Envelope chart: current-season daily cumulative burned area against the
#' min-max band + median of the historical years, on a shared season-day grid.
#' Direct labels instead of a legend; the current year's line stops at its
#' last data point with an "as of <date>" annotation.
#' @param envelope list returned by build_envelope() (see R/pipeline.R)
#' @param col_current line color for the current year (colorblind-safe orange
#'   against the grey band; no red/green contrast)
#' @return a ggplot object (no title -- captions live in Quarto fig-cap)
plot_envelope <- function(envelope, col_current = "#D64A05") {
  band    <- envelope$band
  current <- envelope$current
  meta    <- envelope$meta

  # English month labels regardless of system locale (month.abb is not localized)
  month_lab <- function(d) month.abb[lubridate::month(d)]

  as_of_lab <- paste(
    lubridate::day(meta$as_of_date), month.name[lubridate::month(meta$as_of_date)]
  )
  end_point <- current[nrow(current), ]

  # Data-driven direct-label anchors
  band_anchor <- band[band$ref_date == as.Date(sprintf("%d-08-20", meta$year_current)), ]
  med_anchor  <- band[nrow(band), ]

  ggplot2::ggplot() +
    ggplot2::geom_ribbon(
      data = band,
      ggplot2::aes(x = ref_date, ymin = min_ha, ymax = max_ha),
      fill = "grey80", alpha = 0.55
    ) +
    ggplot2::geom_line(
      data = band,
      ggplot2::aes(x = ref_date, y = median_ha),
      color = "grey35", linewidth = 0.6, linetype = "22"
    ) +
    ggplot2::geom_line(
      data = current,
      ggplot2::aes(x = ba_date, y = cum_ha),
      color = col_current, linewidth = 1.3, lineend = "round"
    ) +
    ggplot2::geom_point(
      data = end_point,
      ggplot2::aes(x = ba_date, y = cum_ha),
      color = col_current, size = 2.8
    ) +
    ggplot2::annotate(
      "text",
      x = end_point$ba_date + 3, y = end_point$cum_ha,
      label = sprintf(
        "%d: %s\nas of %s", meta$year_current, lab_si_ha(end_point$cum_ha), as_of_lab
      ),
      hjust = 0, vjust = 0.5, size = 3.6, fontface = "bold", color = col_current,
      lineheight = 0.95
    ) +
    ggplot2::annotate(
      "text",
      x = band_anchor$ref_date, y = (band_anchor$min_ha + band_anchor$max_ha) / 2,
      label = sprintf("range %d–%d", min(meta$hist_years), max(meta$hist_years)),
      color = "grey45", size = 3.6
    ) +
    ggplot2::annotate(
      "text",
      x = med_anchor$ref_date, y = med_anchor$median_ha,
      label = sprintf("median %d–%d", min(meta$hist_years), max(meta$hist_years)),
      hjust = 1, vjust = -0.6, color = "grey35", size = 3.4
    ) +
    ggplot2::scale_x_date(
      date_breaks = "1 month", labels = month_lab, expand = ggplot2::expansion(mult = c(0.01, 0.09))
    ) +
    ggplot2::scale_y_continuous(labels = lab_si_ha, expand = ggplot2::expansion(mult = c(0, 0.05))) +
    ggplot2::labs(
      x = NULL,
      y = "Cumulative burned area since 1 June (ha)",
      caption = paste(
        "EFFIS rapid perimeters (≈ ≥30–50 ha), Europe-clipped (EU27 + EFTA + UK + Balkans).",
        "Areas from polygon geometry in EPSG:3035; season window 1 Jun–30 Sep.",
        sep = "\n"
      )
    ) +
    theme_burns(base_size = 12)
}
