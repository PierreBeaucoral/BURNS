# ==============================================================================
# plots.R
# Shared figure builders used by BOTH index.qmd (tracker) and posts/2026.qmd.
# Brand colours (ember, vegetation green) now come from burns_brand
# (R/tokens.R, single source theme/burns-tokens.yml) instead of literal hex,
# so figures and the HTML chrome cannot drift apart. Follows the theme.R
# precedent: ggplot2 calls are namespaced, no library() here.
# Required packages: ggplot2, scales, lubridate, dplyr, tibble, patchwork
#   (patchwork used only by plot_fire_sizes(); attached in the qmd setup)
# Depends on: R/helpers.R (lab_si_ha, to_num), R/theme.R + R/tokens.R
#   (theme_burns, pal_lc, burns_brand)
# ==============================================================================

#' Envelope chart: current-season daily cumulative burned area against the
#' min-max band + median of the historical years, on a shared season-day grid.
#' @param envelope list returned by build_envelope() (see R/pipeline.R)
#' @param col_current line color for the current year (brand ember; colorblind-
#'   safe against the grey band, no red/green contrast)
#' @return a ggplot object (no title -- captions live in Quarto fig-cap)
plot_envelope <- function(envelope, col_current = burns_brand$ember) {
  band    <- envelope$band
  current <- envelope$current
  meta    <- envelope$meta

  month_lab <- function(d) month.abb[lubridate::month(d)]

  as_of_lab <- paste(
    lubridate::day(meta$as_of_date), month.name[lubridate::month(meta$as_of_date)]
  )
  end_point <- current[nrow(current), ]

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
      label = sprintf("range %d-%d", min(meta$hist_years), max(meta$hist_years)),
      color = "grey45", size = 3.6
    ) +
    ggplot2::annotate(
      "text",
      x = med_anchor$ref_date, y = med_anchor$median_ha,
      label = sprintf("median %d-%d", min(meta$hist_years), max(meta$hist_years)),
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
#' @param col_current highlight color (brand ember)
#' @return a ggplot object
plot_natura_trend <- function(natura_trend, year_current, col_current = burns_brand$ember) {
  df <- natura_trend |>
    dplyr::mutate(
      is_current = year == year_current,
      col = ifelse(is_current, col_current, burns_brand$veg_green)
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
#' area inside Natura 2000): colorblind-safe sequential viridis from grey
#' (0%, unprotected) to the scale's high end (100%, fully inside a site).
#' @param tagged_current sf, current-year tagged perimeters (must include percna2k)
#' @param eu list(poly, union) from get_eu()
#' @return a ggplot object
plot_natura_map <- function(tagged_current, eu) {
  df <- tagged_current |> dplyr::mutate(percna2k = to_num(percna2k))

  ggplot2::ggplot() +
    ggplot2::geom_sf(data = eu$poly, fill = "grey95", color = "grey70", linewidth = 0.15) +
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
#' weekly Europe-clipped burned area on a square-root scale. Grey tiles are
#' weeks of the current (in-progress) year that have not happened yet.
#' @param grid tibble from prepare_calendar_grid() (year, iso_week, area_ha)
#' @param year_current integer, current in-progress year (top row, highlighted)
#' @param cutoff_week integer, ISO week of the current year's last mapped date
#' @return a ggplot object
plot_calendar_heatmap <- function(grid, year_current, cutoff_week) {
  grid <- grid |>
    dplyr::mutate(year_f = factor(year, levels = sort(unique(year), decreasing = TRUE)))

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
      inherit.aes = FALSE, color = burns_brand$ember, linewidth = 0.9, linetype = "22"
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

#' Fire-size distribution: two histograms stacked on a shared logarithmic
#' size axis, telling the "most fires are small, most hectares come from a few
#' big ones" story in one figure. Top panel counts fires per size band; bottom
#' panel sums the burned hectares per size band (a weight = area_ha histogram
#' on the same bins). A dashed vertical line marks the rough 30 ha floor of the
#' older MODIS-era mapping, so the reader sees how much of the current year now
#' falls below the size EFFIS used to catch. Area comes from the Europe-clipped
#' geometry (tagged_full$area_ha), matching every other figure on the page.
#' @param tagged_full sf, current-year Europe-clipped perimeters (needs area_ha)
#' @param old_floor numeric, legacy MODIS-era minimum mapped size (ha), default 30
#' @param col_fire fill for the fire-count panel (brand ember, figure data series)
#' @param n_bins number of log-spaced bins spanning the observed size range
#' @return a patchwork of two vertically stacked ggplot objects (shared x)
plot_fire_sizes <- function(tagged_full, old_floor = 30, col_fire = burns_brand$ember, n_bins = 30L) {
  areas <- tagged_full$area_ha
  areas <- areas[is.finite(areas) & areas > 0]     # log axis needs strictly positive
  df <- tibble::tibble(area_ha = areas)

  # Log-spaced bin edges across the full observed range (shared by both panels
  # so the two histograms are directly comparable band for band).
  brks <- 10^seq(log10(min(df$area_ha)), log10(max(df$area_ha)), length.out = n_bins + 1L)

  x_scale <- ggplot2::scale_x_log10(
    breaks = c(1, 3, 10, 30, 100, 300, 1000, 3000, 10000, 30000),
    labels = scales::label_comma(),
    expand = ggplot2::expansion(mult = c(0.02, 0.02))
  )
  floor_line <- ggplot2::geom_vline(
    xintercept = old_floor, linetype = "22", color = "grey30", linewidth = 0.7
  )

  p_count <- ggplot2::ggplot(df, ggplot2::aes(x = area_ha)) +
    ggplot2::geom_histogram(breaks = brks, fill = col_fire, color = "white", linewidth = 0.1) +
    floor_line +
    x_scale +
    ggplot2::scale_y_continuous(
      labels = scales::label_comma(), expand = ggplot2::expansion(mult = c(0, 0.08))
    ) +
    ggplot2::labs(x = NULL, y = "Number of fires") +
    theme_burns(base_size = 12) +
    ggplot2::theme(axis.text.x = ggplot2::element_blank())

  p_area <- ggplot2::ggplot(df, ggplot2::aes(x = area_ha, weight = area_ha)) +
    ggplot2::geom_histogram(breaks = brks, fill = "grey55", color = "white", linewidth = 0.1) +
    floor_line +
    x_scale +
    ggplot2::scale_y_continuous(
      labels = lab_si_ha, expand = ggplot2::expansion(mult = c(0, 0.08))
    ) +
    ggplot2::labs(x = "Fire size (hectares, log scale)", y = "Burned area (ha)") +
    theme_burns(base_size = 12)

  patchwork::wrap_plots(p_count, p_area, ncol = 1L)
}
