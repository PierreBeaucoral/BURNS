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

#' Spread label y-positions so neighbours sit at least `min_gap` apart (a
#' small dependency-free stand-in for ggrepel on one vertical axis; labels
#' keep their order and are pushed apart symmetrically).
#' @param y numeric vector of anchor positions
#' @param min_gap minimum separation, in y units
#' @return numeric vector of adjusted positions, same order as y
spread_labels <- function(y, min_gap) {
  o <- order(y)
  ys <- y[o]
  for (iter in seq_len(50L)) {
    moved <- FALSE
    for (i in seq_len(length(ys) - 1L)) {
      d <- ys[i + 1L] - ys[i]
      if (d < min_gap - 1e-9) {
        shift <- (min_gap - d) / 2
        ys[i] <- ys[i] - shift
        ys[i + 1L] <- ys[i + 1L] + shift
        moved <- TRUE
      }
    }
    if (!moved) break
  }
  out <- numeric(length(y))
  out[o] <- ys
  out
}

#' Envelope chart: current-season daily cumulative burned area against every
#' historical season (faint grey lines), the middle-50% band and the median of
#' those seasons, on a shared season-day grid. Optionally a weekly-bars panel
#' for the current season underneath, and a shaded "still being mapped" zone
#' over the most recent days (EFFIS keeps filling in recent dates for weeks:
#' between the 3 Sep and 2 Oct 2026 snapshots the area dated 1 Jun-2 Sep grew
#' 5.0%). The band shows variation ACROSS OBSERVED YEARS, not uncertainty.
#' @param envelope list returned by build_envelope() (see R/pipeline.R)
#' @param col_current line color for the current year (brand ember; colorblind-
#'   safe against the grey history, no red/green contrast)
#' @param weekly logical; add the aligned weekly-bars panel (default TRUE)
#' @param provisional_days days at the end of the current line shaded as
#'   "still being mapped" (default 14; 0 or NULL switches it off)
#' @param base_size base font size (14 survives shrinking to ~400 px wide)
#' @param note logical; print the "grey lines / grey band" reading note in the
#'   top-left corner (switch off when the current line runs high early and
#'   would sit under it, e.g. country envelopes; captions carry it anyway)
#' @return a ggplot (weekly = FALSE) or patchwork (weekly = TRUE) object (no
#'   title -- captions live in Quarto fig-cap)
plot_envelope <- function(envelope, col_current = burns_brand$ember, weekly = TRUE,
                          provisional_days = 14L, base_size = 14, note = TRUE) {
  band    <- envelope$band
  current <- envelope$current
  meta    <- envelope$meta
  hist_years <- meta$hist_years
  yr_rng <- sprintf("%d-%d", min(hist_years), max(hist_years))
  show_prov <- !is.null(provisional_days) && provisional_days > 0

  month_lab <- function(d) month.abb[lubridate::month(d)]

  # Historical trajectories on the reference (current-year) calendar
  hist_lines <- envelope$hist_daily |>
    dplyr::left_join(envelope$ref_dates, by = "day_idx")
  iqr <- hist_lines |>
    dplyr::group_by(ref_date) |>
    dplyr::summarise(
      q25 = stats::quantile(cum_ha, 0.25, names = FALSE),
      q75 = stats::quantile(cum_ha, 0.75, names = FALSE), .groups = "drop"
    )

  end_point <- current[nrow(current), ]
  x_min <- min(band$ref_date)
  x_max <- max(band$ref_date)
  # Identical limits and expansion in both panels so the dates line up exactly
  # (coord xlim, not scale limits: the right-edge labels sit outside the data)
  x_lim <- c(x_min - 1, x_max + 0.27 * as.numeric(x_max - x_min))
  month_breaks <- seq(x_min, x_max + 1, by = "month")
  x_scale <- function(y_max) {
    list(
      ggplot2::scale_x_date(breaks = month_breaks, labels = month_lab),
      ggplot2::coord_cartesian(xlim = x_lim, ylim = c(0, y_max), expand = FALSE)
    )
  }

  # Direct labels at the right edge: previous year, max and min year, median,
  # and the current year; de-collided vertically.
  last_idx <- max(hist_lines$day_idx)
  ends <- hist_lines |>
    dplyr::filter(day_idx == last_idx) |>
    dplyr::select(year, cum_ha)
  # previous year, max, min, plus every year that finished above the current
  # one, so prose like "behind only 2022 and 2025" can be checked on the chart
  notable <- unique(c(max(hist_years), ends$year[which.max(ends$cum_ha)],
                      ends$year[which.min(ends$cum_ha)],
                      ends$year[ends$cum_ha > current$cum_ha[nrow(current)]]))
  lab_df <- dplyr::bind_rows(
    ends |> dplyr::filter(year %in% notable) |>
      dplyr::transmute(label = as.character(year), y = cum_ha, type = "hist"),
    tibble::tibble(label = "median", y = band$median_ha[band$day_idx == last_idx],
                   type = "median"),
    tibble::tibble(label = sprintf("%d: %s", meta$year_current, lab_si_ha(end_point$cum_ha)),
                   y = end_point$cum_ha, type = "current")
  )
  y_top <- max(c(hist_lines$cum_ha, current$cum_ha))
  lab_df$y_lab <- spread_labels(lab_df$y, min_gap = 0.075 * y_top)
  # spreading can push the lowest label below the axis, where it is clipped:
  # lift the whole stack (gaps unchanged) so it starts at 3% of the panel
  lab_df$y_lab <- lab_df$y_lab + max(0, 0.03 * y_top - min(lab_df$y_lab))
  lab_df$col <- c(hist = "grey30", median = "grey30", current = col_current)[lab_df$type]
  lab_df$face <- ifelse(lab_df$type == "current", "bold", "plain")
  lab_x <- x_max + 3

  p <- ggplot2::ggplot() +
    ggplot2::geom_ribbon(
      data = iqr, ggplot2::aes(x = ref_date, ymin = q25, ymax = q75),
      fill = "grey70", alpha = 0.45
    ) +
    ggplot2::geom_line(
      data = hist_lines, ggplot2::aes(x = ref_date, y = cum_ha, group = year),
      color = "grey60", linewidth = 0.35, alpha = 0.7
    ) +
    ggplot2::geom_line(
      data = band, ggplot2::aes(x = ref_date, y = median_ha),
      color = "grey25", linewidth = 0.8, linetype = "22"
    )

  if (show_prov) {
    prov_start <- meta$as_of_date - provisional_days + 1L
    p <- p +
      ggplot2::annotate(
        "rect", xmin = prov_start, xmax = meta$as_of_date + 0.5,
        ymin = -Inf, ymax = Inf, fill = col_current, alpha = 0.10
      ) +
      # vertical, inside the shaded strip: never collides with the median or
      # the historical lines' end labels
      ggplot2::annotate(
        "text", x = prov_start + 0.5 * provisional_days, y = 0.03 * y_top,
        label = "still being mapped", angle = 90, hjust = 0, vjust = 0.5,
        size = 3.8, color = "grey30"
      )
  }

  p <- p +
    ggplot2::geom_line(
      data = current, ggplot2::aes(x = ba_date, y = cum_ha),
      color = col_current, linewidth = 1.6, lineend = "round"
    ) +
    ggplot2::geom_point(
      data = end_point, ggplot2::aes(x = ba_date, y = cum_ha),
      color = col_current, size = 3
    ) +
    ggplot2::geom_text(
      data = lab_df,
      ggplot2::aes(x = lab_x, y = y_lab, label = label, color = col, fontface = face),
      hjust = 0, size = 4.4, show.legend = FALSE
    ) +
    ggplot2::scale_color_identity() +
    (if (note) ggplot2::annotate(
      "text", x = x_min + 2, y = y_top, hjust = 0, vjust = 1, size = 4.2,
      color = "grey30", lineheight = 0.95,
      label = sprintf(paste0("Grey lines: each season %s.\nGrey band: middle half",
                             " of those seasons\n(variation across years, not uncertainty)."),
                      yr_rng)
    )) +
    x_scale(y_top * 1.07) +
    ggplot2::scale_y_continuous(labels = lab_si_ha) +
    ggplot2::labs(x = NULL, y = "Cumulative burned area\nsince 1 June (ha)") +
    theme_burns(base_size = base_size)

  if (!weekly) return(p)

  # Weekly bars (Monday-start weeks) for the current season only
  wk <- current |>
    dplyr::mutate(week = lubridate::floor_date(ba_date, "week", week_start = 1)) |>
    dplyr::group_by(week) |>
    dplyr::summarise(ha = sum(area_ha), .groups = "drop") |>
    dplyr::mutate(
      mid = week + 3.5,
      provisional = show_prov & (week + 6) > (meta$as_of_date - provisional_days)
    )
  p_wk <- ggplot2::ggplot(wk, ggplot2::aes(x = mid, y = ha, alpha = provisional)) +
    ggplot2::geom_col(width = 6, fill = col_current) +
    ggplot2::scale_alpha_manual(values = c(`FALSE` = 1, `TRUE` = 0.45), guide = "none") +
    x_scale(max(wk$ha) * 1.12) +
    ggplot2::scale_y_continuous(labels = lab_si_ha) +
    ggplot2::labs(x = NULL, y = "Burned area\nper week (ha)") +
    theme_burns(base_size = base_size)

  # wrap_plots(), not `/`: the operator only dispatches once patchwork is
  # loaded, and index.qmd never attaches it.
  patchwork::wrap_plots(p, p_wk, ncol = 1L, heights = c(3, 1))
}

#' Gallery of scars: small-multiples specimen sheet of the top-n current-year
#' fires plus a same-scale Paris reference circle, all drawn on one shared
#' coord window (facet_wrap default = fixed scales/coords across panels). One
#' common scale bar (drawn once, in the reference panel) gives the real size.
#' @param gallery list returned by build_gallery_scars() (R/pipeline.R)
#' @param ncol number of facet columns
#' @param bar_km length of the common scale bar, in km
#' @param base_size base font size
#' @return a ggplot object
plot_gallery_scars <- function(gallery, ncol = 4L, bar_km = 10, base_size = 14) {
  panels <- gallery$panels
  half   <- gallery$half_side
  pal_gallery <- c(pal_lc, "Reference (Paris outline)" = "grey75")

  # Scale bar in the last (reference) panel, lower left; label above it
  ref_panel <- levels(panels$panel_label)[nlevels(panels$panel_label)]
  x0 <- -half + 0.08 * half
  y0 <- -half + 0.12 * half
  bar <- tibble::tibble(
    panel_label = factor(ref_panel, levels = levels(panels$panel_label)),
    x = x0, xend = x0 + bar_km * 1000, y = y0,
    xm = x0 + bar_km * 500, ylab = y0 + 0.07 * half,
    lab = sprintf("%d km", as.integer(bar_km))
  )

  # Strip text: shorten the reference label and wrap long place names so the
  # strips are not clipped at phone-friendly font sizes.
  wrap_one <- function(x) {
    x <- sub("\\(circle, equal-area, ([0-9,]+) ha\\)", "\\1 ha circle", x)
    parts <- strsplit(x, "\n", fixed = TRUE)[[1]]
    parts[1] <- paste(strwrap(parts[1], width = 24), collapse = "\n")
    paste(parts, collapse = "\n")
  }
  strip_wrap <- function(labs) {
    lapply(labs, function(x) vapply(as.character(x), wrap_one, character(1), USE.NAMES = FALSE))
  }

  ggplot2::ggplot(panels) +
    ggplot2::geom_sf(ggplot2::aes(fill = dominant_lc), color = "grey25", linewidth = 0.15) +
    ggplot2::geom_segment(
      data = bar, ggplot2::aes(x = x, xend = xend, y = y, yend = y),
      linewidth = 1.4, color = "grey10", lineend = "butt", inherit.aes = FALSE
    ) +
    ggplot2::geom_text(
      data = bar, ggplot2::aes(x = xm, y = ylab, label = lab),
      size = 4.4, fontface = "bold", color = "grey10", vjust = 0, inherit.aes = FALSE
    ) +
    ggplot2::scale_fill_manual(values = pal_gallery, breaks = names(pal_lc), name = "Land cover") +
    ggplot2::facet_wrap(~panel_label, ncol = ncol, labeller = strip_wrap) +
    ggplot2::coord_sf(xlim = c(-half, half), ylim = c(-half, half), expand = FALSE, datum = NA) +
    theme_burns(base_size = base_size, map = TRUE) +
    ggplot2::theme(
      strip.text = ggplot2::element_text(size = base_size - 3, lineheight = 0.95, face = "bold"),
      legend.position = "bottom",
      legend.text = ggplot2::element_text(size = base_size - 3)
    ) +
    ggplot2::guides(fill = ggplot2::guide_legend(nrow = 2, byrow = TRUE))
}

#' Natura 2000 trend: share of EU-27 burned area falling inside Natura 2000
#' sites, one dot per year, with the 2017-2025 median as a reference line and
#' the current year labelled directly. Lower panel: the absolute hectares
#' inside Natura 2000 (the share can move because the denominator moves).
#' @param natura_trend tibble from build_natura_trend() (year, share,
#'   natura_ha, eu_ha, ...)
#' @param year_current integer, year to highlight
#' @param col_current highlight color (brand ember)
#' @param base_size base font size
#' @return a patchwork object
plot_natura_trend <- function(natura_trend, year_current, col_current = burns_brand$ember,
                              base_size = 14) {
  df <- natura_trend |>
    dplyr::mutate(
      is_current = year == year_current,
      col = ifelse(is_current, col_current, "grey45")
    )
  hist_med <- stats::median(df$share[!df$is_current], na.rm = TRUE)
  cur <- df[df$is_current, ]
  hist_rng <- sprintf("%d-%d", min(df$year[!df$is_current]), max(df$year[!df$is_current]))
  x_scale <- ggplot2::scale_x_continuous(
    breaks = sort(unique(df$year)), labels = function(x) sprintf("'%02d", x %% 100),
    expand = ggplot2::expansion(add = c(0.6, 0.6))
  )

  p_share <- ggplot2::ggplot(df, ggplot2::aes(x = year, y = share)) +
    ggplot2::geom_hline(yintercept = hist_med, linetype = "22", color = "grey30") +
    ggplot2::annotate(
      "text", x = min(df$year) - 0.4, y = hist_med, hjust = 0, vjust = -0.7, size = 4.2,
      color = "grey30", label = sprintf("median %s: %s", hist_rng,
                                        scales::percent(hist_med, accuracy = 1))
    ) +
    ggplot2::geom_point(ggplot2::aes(color = col, size = is_current)) +
    ggplot2::geom_text(
      data = cur, ggplot2::aes(label = scales::percent(share, accuracy = 1)),
      vjust = -1.2, size = 4.6, fontface = "bold", color = col_current
    ) +
    ggplot2::scale_color_identity() +
    ggplot2::scale_size_manual(values = c(`TRUE` = 5, `FALSE` = 3.4), guide = "none") +
    ggplot2::scale_y_continuous(
      labels = scales::label_percent(accuracy = 1), limits = c(0, NA),
      expand = ggplot2::expansion(mult = c(0, 0.15))
    ) +
    x_scale +
    ggplot2::labs(x = NULL, y = "Share of EU-27 burned area\ninside Natura 2000") +
    theme_burns(base_size = base_size) +
    ggplot2::theme(axis.text.x = ggplot2::element_blank())

  p_ha <- ggplot2::ggplot(df, ggplot2::aes(x = year, y = natura_ha)) +
    ggplot2::geom_col(ggplot2::aes(fill = col), width = 0.6) +
    ggplot2::geom_text(
      ggplot2::aes(label = scales::label_number(scale = 1e-3, suffix = "k", accuracy = 1)(natura_ha)),
      vjust = -0.4, size = 4, color = "grey25"
    ) +
    ggplot2::scale_fill_identity() +
    ggplot2::scale_y_continuous(labels = lab_si_ha, expand = ggplot2::expansion(mult = c(0, 0.22))) +
    x_scale +
    ggplot2::labs(x = "Season (1 June to the same cut-off date each year)",
                  y = "Hectares inside\nNatura 2000") +
    theme_burns(base_size = base_size)

  patchwork::wrap_plots(p_share, p_ha, ncol = 1L, heights = c(2.2, 1))
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
#' weekly Europe-clipped burned area on a square-root scale (light = little,
#' dark = a lot). Three cell types are drawn explicitly and keyed in a legend
#' strip: true zero weeks (palest tile), weeks of the current year that have
#' not happened yet (grey), and weeks with no data (white with a cross). The
#' current year's peak week and the archive's biggest week carry direct labels.
#' @param grid tibble from prepare_calendar_grid() (year, iso_week, area_ha);
#'   area_ha NA = future (current year, after cutoff) or missing (any other)
#' @param year_current integer, current in-progress year (bottom row)
#' @param cutoff_week integer, ISO week of the current year's last mapped date
#' @param base_size base font size
#' @return a patchwork object (heatmap above a one-line key for the cell types)
plot_calendar_heatmap <- function(grid, year_current, cutoff_week, base_size = 14) {
  yrs <- sort(unique(grid$year), decreasing = TRUE)   # position 1 = current year
  n_row <- length(yrs)
  grid <- grid |>
    dplyr::mutate(
      ypos = match(year, yrs),                         # numeric rows: no discrete-scale surprises
      cell = dplyr::case_when(
        is.na(area_ha) & year == year_current & iso_week > cutoff_week ~ "future",
        is.na(area_ha) ~ "missing",
        area_ha == 0 ~ "zero",
        TRUE ~ "burned"
      )
    )

  month_starts <- as.Date(sprintf("2021-%02d-01", 1:12))
  week_breaks  <- lubridate::isoweek(month_starts)

  col_zero <- "#eef3f6"      # palest, cool: "nothing burned"
  col_future <- "grey72"
  burned <- grid[grid$cell == "burned", ]

  # Direct labels: current-year peak week and archive-wide biggest week
  cur <- burned[burned$year == year_current, ]
  pk_cur <- cur[which.max(cur$area_ha), ]
  pk_all <- burned[which.max(burned$area_ha), ]
  if (pk_cur$year == pk_all$year && pk_cur$iso_week == pk_all$iso_week) {
    ann <- tibble::tibble(
      ypos = pk_cur$ypos, iso_week = pk_cur$iso_week,
      lab = sprintf("%d peak week and biggest in archive: %s", pk_cur$year,
                    lab_si_ha(pk_cur$area_ha))
    )
  } else {
    ann <- tibble::tibble(
      ypos = c(pk_cur$ypos, pk_all$ypos), iso_week = c(pk_cur$iso_week, pk_all$iso_week),
      lab = c(sprintf("%d peak week: %s", pk_cur$year, lab_si_ha(pk_cur$area_ha)),
              sprintf("Biggest week in archive: %d, %s", pk_all$year, lab_si_ha(pk_all$area_ha)))
    )
  }
  # Labels live in the margin above (top half rows) or below (bottom half),
  # joined to their cell by a thin line; two labels on one side face away from
  # each other so they cannot collide.
  ann$above <- ann$ypos > n_row / 2
  ann <- ann[order(ann$above, ann$iso_week), ]
  ann$hj <- ave(ann$iso_week, ann$above, FUN = function(w) if (length(w) > 1) c(1, 0) else 1)
  ann$x <- ann$iso_week + ifelse(ann$hj == 1, 0.5, -0.5)
  ann$y_lab <- ifelse(ann$above, n_row + 0.75, 0.25)
  ann$y_cell <- ifelse(ann$above, ann$ypos + 0.5, ann$ypos - 0.5)
  ann$y_seg <- ifelse(ann$above, n_row + 0.55, 0.45)

  cutoff_seg <- tibble::tibble(x = cutoff_week + 0.5, y = 1)

  p <- ggplot2::ggplot() +
    ggplot2::geom_tile(
      data = grid[grid$cell == "zero", ], ggplot2::aes(x = iso_week, y = ypos),
      fill = col_zero, width = 1, height = 1
    ) +
    ggplot2::geom_tile(
      data = grid[grid$cell == "future", ], ggplot2::aes(x = iso_week, y = ypos),
      fill = col_future, width = 1, height = 1
    ) +
    ggplot2::geom_tile(
      data = burned, ggplot2::aes(x = iso_week, y = ypos, fill = area_ha),
      width = 1, height = 1
    ) +
    ggplot2::geom_segment(
      data = cutoff_seg, ggplot2::aes(x = x, xend = x, y = y - 0.5, yend = y + 0.5),
      color = "grey15", linewidth = 0.8, linetype = "22"
    ) +
    ggplot2::geom_segment(
      data = ann, ggplot2::aes(x = iso_week, xend = iso_week, y = y_cell, yend = y_seg),
      color = "grey15", linewidth = 0.5
    ) +
    ggplot2::geom_text(
      data = ann, ggplot2::aes(x = x, y = y_lab, label = lab, hjust = hj,
                               vjust = ifelse(above, 0, 1)),
      size = 4.2, fontface = "bold", color = "grey10"
    ) +
    ggplot2::scale_fill_gradientn(
      colours = viridisLite::rocket(256, begin = 0, end = 0.88, direction = -1),
      trans = "sqrt", labels = lab_si_ha, breaks = c(0, 50e3, 150e3, 300e3),
      name = "Weekly burned area (square-root scale)",
      guide = ggplot2::guide_colourbar(title.position = "top", barwidth = grid::unit(18, "lines"))
    ) +
    ggplot2::scale_x_continuous(
      breaks = week_breaks, labels = month.abb, expand = ggplot2::expansion(mult = c(0.005, 0.005))
    ) +
    ggplot2::scale_y_continuous(
      breaks = seq_len(n_row), labels = yrs, expand = ggplot2::expansion(add = c(0.5, 0.5))
    ) +
    ggplot2::coord_cartesian(ylim = c(-0.5, n_row + if (any(ann$above)) 1.4 else 0.5), expand = FALSE) +
    ggplot2::labs(x = NULL, y = NULL) +
    theme_burns(base_size = base_size) +
    ggplot2::theme(
      panel.grid = ggplot2::element_blank(),
      axis.text.x = ggplot2::element_text(size = base_size - 2),
      legend.position = "bottom"
    )

  # Key for the three non-gradient cell types (a colourbar cannot show them)
  key <- tibble::tibble(
    x = c(0, 4.4, 10), lab = c("zero hectares burned", "not yet happened", "no data"),
    fill = c(col_zero, col_future, "white")
  )
  p_key <- ggplot2::ggplot(key) +
    ggplot2::geom_tile(ggplot2::aes(x = x, y = 0, fill = fill), width = 0.5, height = 0.8,
                       color = "grey60", linewidth = 0.3) +
    ggplot2::geom_point(data = key[key$lab == "no data", ], ggplot2::aes(x = x, y = 0),
                        shape = 4, size = 2.5, color = "grey40") +
    ggplot2::geom_text(ggplot2::aes(x = x + 0.4, y = 0, label = lab), hjust = 0,
                       size = base_size * 0.3) +
    ggplot2::scale_fill_identity() +
    ggplot2::coord_cartesian(xlim = c(-0.4, 14.5), ylim = c(-0.6, 0.6), expand = FALSE) +
    ggplot2::theme_void()

  patchwork::wrap_plots(p, p_key, ncol = 1L, heights = c(1, 0.07))
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
