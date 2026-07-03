# ==============================================================================
# plots.R
# Shared figure builders used by BOTH index.qmd (tracker) and posts/2026.qmd
# (season post), so the two pages render the exact same envelope chart from
# the exact same cached object. Also holds the gallery-of-scars, Natura 2000,
# and calendar-heatmap figure builders (data prep for these lives in
# pipeline.R; this file only turns already-prepared tibbles/sf into ggplot
# objects). Follows the theme.R precedent: ggplot2 calls are namespaced, no
# library() here. scale_fill_viridis_c() ships with ggplot2 (viridisLite
# dependency already present) -- no extra package needed.
# Required packages: ggplot2, scales, lubridate, dplyr, tibble
# Depends on: R/helpers.R (lab_si_ha, to_num), R/theme.R (theme_burns, pal_lc)
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
      y = "Cumulative burned area since 1 June (ha)"
    ) +
    theme_burns(base_size = 12)
}

#' Gallery of scars: small-multiples specimen sheet of the top-n current-year
#' fires plus a same-scale Paris reference circle, all drawn on one shared
#' coord window (facet_wrap default = fixed scales/coords across panels).
#' @param gallery list returned by build_gallery_scars() (R/pipeline.R)
#' @param ncol number of facet columns
#' @return a ggplot object
plot_gallery_scars <- function(gallery, ncol = 4L) {
  panels <- gallery$panels
  half   <- gallery$half_side
  pal_gallery <- c(pal_lc, "Reference (Paris outline)" = "grey75")

  ggplot2::ggplot(panels) +
    ggplot2::geom_sf(ggplot2::aes(fill = dominant_lc), color = "grey25", linewidth = 0.15) +
    ggplot2::scale_fill_manual(values = pal_gallery, breaks = names(pal_lc), name = "Land cover") +
    ggplot2::facet_wrap(~panel_label, ncol = ncol) +
    ggplot2::coord_sf(xlim = c(-half, half), ylim = c(-half, half), expand = FALSE, datum = NA) +
    theme_burns(base_size = 10, map = TRUE) +
    ggplot2::theme(
      strip.text = ggplot2::element_text(size = 8, lineheight = 0.9),
      legend.position = "bottom"
    )
}

#' Natura 2000 trend: share of burned area falling inside Natura 2000
#' protected sites, one point per year, current year highlighted.
#' @param natura_trend tibble from build_natura_trend() (year, share, ...)
#' @param year_current integer, year to highlight
#' @param col_current highlight color (matches the page's orange-red accent)
#' @return a ggplot object
plot_natura_trend <- function(natura_trend, year_current, col_current = "#D64A05") {
  df <- natura_trend |>
    dplyr::mutate(
      is_current = year == year_current,
      col = ifelse(is_current, col_current, "#2E7D32")
    )

  ggplot2::ggplot(df, ggplot2::aes(x = factor(year), y = share)) +
    ggplot2::geom_segment(
      ggplot2::aes(xend = factor(year), y = 0, yend = share, color = col),
      linewidth = 1.1
    ) +
    ggplot2::geom_point(ggplot2::aes(color = col, size = is_current)) +
    ggplot2::scale_color_identity() +
    ggplot2::scale_size_manual(values = c(`TRUE` = 4.2, `FALSE` = 2.8), guide = "none") +
    ggplot2::scale_y_continuous(labels = scales::label_percent(accuracy = 1),
                                 expand = ggplot2::expansion(mult = c(0, 0.12))) +
    ggplot2::labs(x = NULL, y = "Share of burned area inside Natura 2000") +
    theme_burns(base_size = 12)
}

#' 2026 map of perimeters colored by PERCNA2K (share of each perimeter's
#' area inside Natura 2000): a colorblind-safe sequential scale (viridis)
#' from grey (0%, unprotected) through the scale's high end (100%, fully
#' inside a protected site).
#' @param tagged_current sf, current-year tagged perimeters (must include percna2k)
#' @param eu list(poly, union) from get_eu()
#' @return a ggplot object
plot_natura_map <- function(tagged_current, eu) {
  df <- tagged_current |> dplyr::mutate(percna2k = to_num(percna2k))

  ggplot2::ggplot() +
    ggplot2::geom_sf(data = eu$poly, fill = "grey95", color = "grey70", linewidth = 0.15) +
    # Many perimeters are small enough that fill alone is sub-pixel at
    # continental zoom; mapping color = fill too means the outline itself
    # still shows the Natura 2000 share for tiny fires.
    ggplot2::geom_sf(data = df, ggplot2::aes(fill = percna2k, color = percna2k), linewidth = 0.35) +
    ggplot2::scale_fill_viridis_c(
      option = "viridis", na.value = "grey80",
      labels = scales::label_percent(scale = 1),
      name = "Share of perimeter\ninside Natura 2000"
    ) +
    ggplot2::scale_color_viridis_c(option = "viridis", na.value = "grey80", guide = "none") +
    ggplot2::coord_sf() +
    theme_burns(base_size = 11, map = TRUE) +
    ggplot2::theme(legend.position = "right")
}

#' Fire-year calendar heatmap: year (rows) x ISO week (columns), fill =
#' weekly Europe-clipped burned area on a square-root scale (chosen over log
#' because many weeks have genuinely zero burned area, which log cannot
#' display; sqrt handles zero natively while still compressing the
#' July-August peaks enough to keep late-winter/spring variation visible).
#' Grey tiles are weeks of the current (in-progress) year that have not
#' happened yet -- NA, not zero.
#' @param grid tibble from prepare_calendar_grid() (year, iso_week, area_ha)
#' @param year_current integer, current in-progress year (drawn on top row, highlighted)
#' @param cutoff_week integer, ISO week of the current year's last mapped date
#' @return a ggplot object
plot_calendar_heatmap <- function(grid, year_current, cutoff_week) {
  grid <- grid |>
    dplyr::mutate(year_f = factor(year, levels = sort(unique(year), decreasing = TRUE)))

  # Approximate month gridlines: ISO week of the 1st of each month in a
  # representative non-leap year, labeled with month abbreviations.
  month_starts <- as.Date(sprintf("2021-%02d-01", 1:12))
  week_breaks  <- lubridate::isoweek(month_starts)

  cutoff_seg <- tibble::tibble(
    x = cutoff_week + 0.5, y = which(sort(unique(grid$year), decreasing = TRUE) == year_current)
  )

  ggplot2::ggplot(grid, ggplot2::aes(x = iso_week, y = year_f, fill = area_ha)) +
    ggplot2::geom_tile(color = "white", linewidth = 0.2) +
    ggplot2::geom_segment(
      data = cutoff_seg,
      ggplot2::aes(x = x, xend = x, y = y - 0.5, yend = y + 0.5),
      inherit.aes = FALSE, color = "#D64A05", linewidth = 0.9, linetype = "22"
    ) +
    ggplot2::scale_fill_viridis_c(
      option = "inferno", trans = "sqrt", na.value = "grey88",
      labels = lab_si_ha, name = "Weekly burned\narea"
    ) +
    ggplot2::scale_x_continuous(
      breaks = week_breaks, labels = month.abb, expand = ggplot2::expansion(mult = c(0.01, 0.01))
    ) +
    ggplot2::labs(x = NULL, y = NULL) +
    theme_burns(base_size = 11) +
    ggplot2::theme(
      panel.grid = ggplot2::element_blank(),
      axis.text.x = ggplot2::element_text(size = 8.5)
    )
}
