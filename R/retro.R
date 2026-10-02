# ==============================================================================
# retro.R
# End-of-season retrospective figures for the 2026 wildfire post:
#   1. country vs its own 2017-2025 range (build_country_vs_history / plot_)
#   2. did the fire move? area-weighted location summary, quoted in prose only
#      (build_fire_locations / summarise_fire_location)
#   3. full ranking, Jan-Sep burned area 2016-2026 (build_ytd_ranking / plot_)
# Burned AREA only (fire counts are not comparable across years: detection
# change in 2023-24). Countries come from tag_countries() (max overlap), never
# from the EFFIS `commune` string. Every heavy step is cached() with the
# snapshot id in the key, so a new snapshot recomputes once.
# Required packages (namespaced calls): sf, dplyr, tidyr, tibble, purrr, ggplot2,
#   scales, lubridate, stats
# Depends on: R/geo.R, R/cache.R, R/pipeline.R, R/theme.R
# ==============================================================================

# Small helper: Jun-Sep window dates for a year
retro_window <- function(year, start_month = 6L, end_month = 9L) {
  last_day <- lubridate::days_in_month(as.Date(sprintf("%d-%02d-01", year, end_month)))
  list(
    start = as.Date(sprintf("%d-%02d-01", year, start_month)),
    end   = as.Date(sprintf("%d-%02d-%02d", year, end_month, last_day))
  )
}

# ------------------------------------------------------------------------------
# Figure 1: country vs own history
# ------------------------------------------------------------------------------

#' Burned area per country and year inside the season window (Jun-Sep).
#' @param years integer vector, historical years plus the current year
#' @param snapshot_dir dated snapshot directory
#' @param eu list(poly, union) from get_eu()
#' @return tibble(year, name_long, ha)
build_country_year_ha <- function(years, snapshot_dir, eu, start_month = 6L,
                                  end_month = 9L, version = 1) {
  key <- sprintf("retro_country_year_%d_%d_%d_%d_snap%s", min(years), max(years),
                 start_month, end_month, basename(snapshot_dir))
  cached(key, {
    purrr::map_dfr(years, function(y) {
      get_tagged_summer(y, snapshot_dir, eu, start_month, end_month) |>
        sf::st_drop_geometry() |>
        dplyr::filter(!is.na(name_long)) |>
        dplyr::group_by(name_long) |>
        dplyr::summarise(ha = sum(area_ha, na.rm = TRUE), .groups = "drop") |>
        dplyr::mutate(year = y)
    })
  }, version = version)
}

#' Country table: current year vs the country's own history range.
#' Zero-burn years are kept as zeros (country-years with no mapped fire).
#' @param hist_years historical years (e.g. 2017:2025)
#' @param year_current current season year
#' @param n_top number of countries with the most current-year burned area
#' @param min_hist_years countries need > 0 ha in at least this many historical
#'   years to count as "having history"
#' @return tibble(name_long, ha_cur, med_hist, min_hist, max_hist, n_hist_pos,
#'   rank_cur [1 = largest of the hist+1 years], ratio_to_median), sorted by ratio
build_country_vs_history <- function(hist_years, year_current, snapshot_dir, eu,
                                     n_top = 14L, min_hist_years = 5L, version = 1) {
  cy <- build_country_year_ha(c(hist_years, year_current), snapshot_dir, eu)
  grid <- tidyr::expand_grid(name_long = unique(cy$name_long),
                             year = c(hist_years, year_current)) |>
    dplyr::left_join(cy, by = c("name_long", "year")) |>
    dplyr::mutate(ha = dplyr::coalesce(ha, 0))

  hist <- grid |>
    dplyr::filter(year %in% hist_years) |>
    dplyr::group_by(name_long) |>
    dplyr::summarise(med_hist = stats::median(ha), min_hist = min(ha),
                     max_hist = max(ha), n_hist_pos = sum(ha > 0), .groups = "drop")
  cur <- grid |> dplyr::filter(year == year_current) |>
    dplyr::select(name_long, ha_cur = ha)

  # rank of the current year among all (hist + current) years, per country
  rk <- grid |>
    dplyr::group_by(name_long) |>
    dplyr::summarise(rank_cur = sum(ha > ha[year == year_current]) + 1L, .groups = "drop")

  cur |>
    dplyr::inner_join(hist, by = "name_long") |>
    dplyr::inner_join(rk, by = "name_long") |>
    dplyr::filter(n_hist_pos >= min_hist_years) |>
    dplyr::slice_max(ha_cur, n = n_top, with_ties = FALSE) |>
    dplyr::mutate(ratio_to_median = ha_cur / pmax(med_hist, 1)) |>
    dplyr::arrange(dplyr::desc(ratio_to_median))
}

#' Range plot: history min-max segment, median tick, current year dot (log10 ha).
#' @param tbl output of build_country_vs_history()
#' @param year_current label for the highlighted dot
#' @param hist_label e.g. "2017-2025"
#' @return ggplot
plot_country_vs_history <- function(tbl, year_current = 2026L, hist_label = "2017–2025",
                                    col_current = burns_brand$ember) {
  d <- tbl |>
    dplyr::mutate(
      # log axis cannot show 0 ha: values under 10 ha are drawn at the 10 ha axis edge
      dplyr::across(c(ha_cur, med_hist, min_hist, max_hist), ~ pmax(.x, 10)),
      name_long = factor(name_long, levels = rev(name_long))  # largest ratio on top
    )
  ggplot2::ggplot(d, ggplot2::aes(y = name_long)) +
    ggplot2::geom_segment(
      ggplot2::aes(x = min_hist, xend = max_hist, yend = name_long, colour = "range"),
      linewidth = 3.2, lineend = "round", alpha = 0.9
    ) +
    ggplot2::geom_point(
      ggplot2::aes(x = med_hist, colour = "median"), shape = "|", size = 5
    ) +
    ggplot2::geom_point(
      ggplot2::aes(x = ha_cur, colour = "cur"), size = 4
    ) +
    ggplot2::scale_x_log10(
      labels = scales::label_number(big.mark = ",", accuracy = 1),
      breaks = c(10, 100, 1e3, 1e4, 1e5),
      expand = ggplot2::expansion(mult = c(0.02, 0.06))
    ) +
    ggplot2::scale_colour_manual(
      name = NULL,
      values = c(range = "grey78", median = "grey25", cur = col_current),
      breaks = c("range", "median", "cur"),
      labels = c(paste(hist_label, "range"), paste(hist_label, "median"), year_current),
      guide = ggplot2::guide_legend(override.aes = list(
        shape = c(15, 124, 16), size = c(4, 5, 4), linewidth = 0
      ))
    ) +
    ggplot2::labs(
      x = "Burned area, 1 June to 30 September (hectares, log scale)", y = NULL
    ) +
    theme_burns(base_size = 13) +
    ggplot2::theme(
      legend.position = "bottom",
      panel.grid.major.y = ggplot2::element_line(colour = "grey92")
    )
}

# ------------------------------------------------------------------------------
# Figure 2: did the fire move?
# ------------------------------------------------------------------------------

#' Per-perimeter location table (small): year, month, country, area, EPSG:3035
#' centroid (x, y in metres) and WGS84 lon/lat. Only what the location figure needs.
#' @return tibble(year, month, name_long, area_ha, x, y, lon, lat)
build_fire_locations <- function(years, snapshot_dir, eu, start_month = 6L,
                                 end_month = 9L, version = 1) {
  key <- sprintf("retro_locations_%d_%d_%d_%d_snap%s", min(years), max(years),
                 start_month, end_month, basename(snapshot_dir))
  cached(key, {
    purrr::map_dfr(years, function(y) {
      tg <- get_tagged_summer(y, snapshot_dir, eu, start_month, end_month)
      tg <- tg[!sf::st_is_empty(sf::st_geometry(tg)), ]
      cen <- suppressWarnings(sf::st_centroid(sf::st_geometry(tg)))   # EPSG:3035
      xy  <- sf::st_coordinates(cen)
      ll  <- sf::st_coordinates(sf::st_transform(cen, 4326))
      tibble::tibble(
        year = y, month = lubridate::month(tg$ba_date), name_long = tg$name_long,
        area_ha = tg$area_ha, x = xy[, "X"], y = xy[, "Y"], lon = ll[, "X"], lat = ll[, "Y"]
      )
    })
  }, version = version)
}

#' Per-year location summary of Jun-Sep burned area: area-weighted centroid
#' (computed in EPSG:3035, then converted to lon/lat), area-weighted median
#' latitude/longitude, and the share of area north of `lat_cut` (default 45 N).
#' Europe-wide centroids are dominated by a few big fires and by distant
#' outliers (Scandinavia 2018, 2023), so the figure uses the full area-weighted
#' distributions (median, share north of lat_cut) rather than a centroid trend;
#' the centroid is still returned.
#' @param loc output of build_fire_locations()
#' @return tibble(year, ha, lon, lat, med_lat, med_lon, share_north, rank_* of the
#'   last year in loc for med_lat, med_lon and share_north [1 = most north/east])
summarise_fire_location <- function(loc, lat_cut = 45) {
  wq <- function(v, w, p) {           # weighted quantile (step function)
    o <- order(v); v <- v[o]; w <- w[o]
    v[which(cumsum(w) / sum(w) >= p)[1]]
  }
  s <- loc |>
    dplyr::filter(!is.na(area_ha), area_ha > 0) |>
    dplyr::group_by(year) |>
    dplyr::summarise(
      ha = sum(area_ha), cx = stats::weighted.mean(x, area_ha),
      cy = stats::weighted.mean(y, area_ha),
      med_lat = wq(lat, area_ha, 0.5), med_lon = wq(lon, area_ha, 0.5),
      share_north = sum(area_ha[lat > lat_cut]) / sum(area_ha), .groups = "drop"
    )
  ll <- sf::st_coordinates(sf::st_transform(
    sf::st_as_sf(s, coords = c("cx", "cy"), crs = 3035), 4326))
  last <- which.max(s$year)
  s |>
    dplyr::mutate(lon = ll[, "X"], lat = ll[, "Y"],
                  rank_med_lat = rank(-med_lat)[last], rank_med_lon = rank(-med_lon)[last],
                  rank_share_north = rank(-share_north)[last]) |>
    dplyr::select(year, ha, lon, lat, med_lat, med_lon, share_north, dplyr::starts_with("rank_"))
}

# ------------------------------------------------------------------------------
# Figure 3: Jan-Sep ranking
# ------------------------------------------------------------------------------

#' Daily burned area (Europe-clipped, no country tag) for one full calendar year.
#' Uses clip_europe_year() (benchmarked 17-61 s/year); only a ~365-row table is
#' cached, never the geometries.
#' @return tibble(ba_date, area_ha)
build_daily_europe_ha <- function(year, snapshot_dir, eu, version = 1) {
  key <- sprintf("retro_daily_europe_%d_snap%s", year, basename(snapshot_dir))
  cached(key, {
    clip_europe_year(year, snapshot_dir, eu) |>
      sf::st_drop_geometry() |>
      dplyr::group_by(ba_date) |>
      dplyr::summarise(area_ha = sum(area_ha, na.rm = TRUE), .groups = "drop")
  }, version = version)
}

#' Jan-May and Jun-Sep burned area per year, 2016-current.
#' @param years e.g. 2016:2026
#' @return tibble(year, period [Jan-May / Jun-Sep], ha, total_ha, rank [1 = most],
#'   low_confidence [TRUE for the first archive year])
build_ytd_ranking <- function(years, snapshot_dir, eu, first_year = min(years), version = 1) {
  d <- purrr::map_dfr(years, function(y) {
    build_daily_europe_ha(y, snapshot_dir, eu) |>
      dplyr::mutate(
        year = y,
        period = dplyr::case_when(
          ba_date <= as.Date(sprintf("%d-05-31", y)) ~ "Jan–May",
          ba_date <= as.Date(sprintf("%d-09-30", y)) ~ "Jun–Sep",
          TRUE ~ NA_character_
        )
      ) |>
      dplyr::filter(!is.na(period))
  })
  tot <- d |>
    dplyr::group_by(year, period) |>
    dplyr::summarise(ha = sum(area_ha), .groups = "drop") |>
    tidyr::complete(year, period, fill = list(ha = 0))
  rk <- tot |>
    dplyr::group_by(year) |>
    dplyr::summarise(total_ha = sum(ha), .groups = "drop") |>
    dplyr::mutate(rank = rank(-total_ha, ties.method = "min"),
                  low_confidence = year == first_year)
  dplyr::left_join(tot, rk, by = "year")
}

#' Stacked bars sorted by total (largest at the top).
#' @param tbl output of build_ytd_ranking()
#' @return ggplot
plot_ytd_ranking <- function(tbl, year_current = 2026L, col_current = burns_brand$ember) {
  ord <- tbl |> dplyr::distinct(year, total_ha, low_confidence) |>
    dplyr::arrange(total_ha)
  lab <- ord |>
    dplyr::mutate(
      ylab = factor(ifelse(low_confidence, paste0(year, "*"), as.character(year)),
                    levels = ifelse(low_confidence, paste0(year, "*"), as.character(year)))
    )
  d <- tbl |>
    dplyr::left_join(dplyr::select(lab, year, ylab), by = "year") |>
    dplyr::mutate(
      fill_key = dplyr::case_when(
        year == year_current & period == "Jan–May" ~ "cur_spring",
        year == year_current ~ "cur_summer",
        period == "Jan–May" ~ "hist_spring",
        TRUE ~ "hist_summer"
      ),
      fill_key = factor(fill_key, levels = c("hist_spring", "hist_summer",
                                             "cur_spring", "cur_summer"))
    )
  tot_lab <- lab |> dplyr::mutate(txt = scales::label_number(big.mark = ",", accuracy = 1)(total_ha))
  ggplot2::ggplot(d, ggplot2::aes(y = ylab, x = ha, fill = fill_key)) +
    ggplot2::geom_col(width = 0.72, position = ggplot2::position_stack(reverse = TRUE), alpha = ifelse(d$low_confidence, 0.55, 1)) +
    ggplot2::geom_text(
      data = tot_lab, ggplot2::aes(y = ylab, x = total_ha, label = txt),
      inherit.aes = FALSE, hjust = -0.1, size = 3.6, colour = "grey20"
    ) +
    ggplot2::scale_fill_manual(
      name = NULL,
      values = c(hist_spring = "grey82", hist_summer = "grey50",
                 cur_spring = "#F0A878", cur_summer = col_current),
      labels = c("Jan–May, 2016–2025", "Jun–Sep, 2016–2025",
                 paste("Jan–May,", year_current), paste("Jun–Sep,", year_current)),
      guide = ggplot2::guide_legend(nrow = 1)
    ) +
    ggplot2::scale_x_continuous(
      labels = scales::label_number(big.mark = ","),
      expand = ggplot2::expansion(mult = c(0, 0.12))
    ) +
    ggplot2::labs(x = "Burned area, 1 January to 30 September (hectares)", y = NULL) +
    theme_burns(base_size = 13) +
    ggplot2::theme(legend.position = "bottom")
}

# ==============================================================================
# Final-assessment additions: land-cover dots, concentration curve, re-burn by
# country, and "what the last month of mapping added"
# ==============================================================================

# ------------------------------------------------------------------------------
# Land cover: 2026 against pooled and typical-year composition
# ------------------------------------------------------------------------------

#' Land-cover burned hectares per class and year (Jun-Sep window), from the
#' country-tagged summer perimeters. Cached per snapshot.
#' @param years integer vector (history plus current year)
#' @param lc_cols character vector of land-cover share columns (percent)
#' @return tibble(year, class, lc_ha)
build_landcover_year_ha <- function(years, snapshot_dir, eu, lc_cols, start_month = 6L,
                                    end_month = 9L, version = 1) {
  key <- sprintf("retro_lc_year_%d_%d_%d_%d_snap%s", min(years), max(years),
                 start_month, end_month, basename(snapshot_dir))
  cached(key, {
    purrr::map_dfr(years, function(y) {
      get_tagged_summer(y, snapshot_dir, eu, start_month, end_month) |>
        sf::st_drop_geometry() |>
        dplyr::mutate(dplyr::across(dplyr::all_of(lc_cols), to_num)) |>
        dplyr::summarise(dplyr::across(dplyr::all_of(lc_cols),
                                       ~ sum(.x / 100 * area_ha, na.rm = TRUE))) |>
        tidyr::pivot_longer(dplyr::everything(), names_to = "class", values_to = "lc_ha") |>
        dplyr::mutate(year = y)
    })
  }, version = version)
}

#' Land-cover composition of the current season against two historical
#' references over the same window: (a) pooled area-weighted share of all
#' historical years, (b) the median and interquartile range of each year's own
#' shares ("typical year").
#' @param hist_years historical years, e.g. 2017:2025
#' @param year_current current season year
#' @param lc_cols,lc_labels land-cover column names and display labels
#' @return tibble(class, label, share_cur, share_pooled, share_med, share_q25,
#'   share_q75, diff_pp [current minus typical year, percentage points]),
#'   sorted by share_cur descending
build_landcover_compare <- function(hist_years, year_current, snapshot_dir, eu,
                                    lc_cols, lc_labels) {
  d <- build_landcover_year_ha(c(hist_years, year_current), snapshot_dir, eu, lc_cols)
  shares <- d |>
    dplyr::group_by(year) |>
    dplyr::mutate(share = lc_ha / sum(lc_ha)) |>
    dplyr::ungroup()
  hist <- shares |> dplyr::filter(year %in% hist_years)
  pooled <- hist |>
    dplyr::group_by(class) |>
    dplyr::summarise(lc_ha = sum(lc_ha), .groups = "drop") |>
    dplyr::mutate(share_pooled = lc_ha / sum(lc_ha)) |>
    dplyr::select(class, share_pooled)
  typical <- hist |>
    dplyr::group_by(class) |>
    dplyr::summarise(share_med = stats::median(share),
                     share_q25 = stats::quantile(share, 0.25, names = FALSE),
                     share_q75 = stats::quantile(share, 0.75, names = FALSE),
                     .groups = "drop")
  shares |>
    dplyr::filter(year == year_current) |>
    dplyr::select(class, share_cur = share) |>
    dplyr::inner_join(pooled, by = "class") |>
    dplyr::inner_join(typical, by = "class") |>
    dplyr::mutate(label = unname(lc_labels[class]),
                  diff_pp = 100 * (share_cur - share_med)) |>
    dplyr::arrange(dplyr::desc(share_cur))
}

#' Paired-dot plot: 2026 (orange) vs typical year (grey, IQR whiskers) vs
#' pooled history (hollow diamond), with the 2026-minus-typical gap labelled.
#' @param tbl output of build_landcover_compare()
#' @param hist_label e.g. "2017-2025"
#' @return ggplot
plot_landcover_compare <- function(tbl, year_current = 2026L, hist_label = "2017-2025",
                                   col_current = burns_brand$ember) {
  d <- tbl |>
    dplyr::mutate(
      label = factor(label, levels = rev(label)),
      gap_lab = sprintf("%+.1f pp", diff_pp)
    )
  x_max <- max(d$share_cur, d$share_q75, d$share_pooled)
  k_cur <- paste(year_current)
  k_typ <- sprintf("Typical year, %s (median, IQR)", hist_label)
  k_pool <- sprintf("Pooled %s", hist_label)
  ggplot2::ggplot(d, ggplot2::aes(y = label)) +
    ggplot2::geom_segment(
      ggplot2::aes(x = share_q25, xend = share_q75, yend = label, colour = k_typ),
      linewidth = 1.6, lineend = "round", alpha = 0.7, show.legend = FALSE
    ) +
    ggplot2::geom_point(ggplot2::aes(x = share_med, colour = k_typ, shape = k_typ), size = 3.6) +
    ggplot2::geom_point(ggplot2::aes(x = share_pooled, colour = k_pool, shape = k_pool),
                        size = 3.4, stroke = 1) +
    ggplot2::geom_point(ggplot2::aes(x = share_cur, colour = k_cur, shape = k_cur), size = 4.4) +
    ggplot2::geom_text(
      ggplot2::aes(x = x_max * 1.12, label = gap_lab, fontface = "bold"),
      hjust = 0, size = 4, colour = "grey15"
    ) +
    ggplot2::annotate("text", x = x_max * 1.12, y = nrow(d) + 0.75, hjust = 0, size = 3.6,
                      colour = "grey30", label = sprintf("%d vs typical", year_current)) +
    ggplot2::scale_colour_manual(
      name = NULL,
      values = stats::setNames(c(col_current, "grey45", "grey25"), c(k_cur, k_typ, k_pool)),
      breaks = c(k_cur, k_typ, k_pool)
    ) +
    ggplot2::scale_shape_manual(
      name = NULL,
      values = stats::setNames(c(16, 16, 5), c(k_cur, k_typ, k_pool)),
      breaks = c(k_cur, k_typ, k_pool)
    ) +
    ggplot2::scale_x_continuous(
      labels = scales::label_percent(accuracy = 1),
      expand = ggplot2::expansion(mult = c(0.02, 0.22))
    ) +
    ggplot2::coord_cartesian(clip = "off") +
    ggplot2::labs(x = sprintf("Share of burned area, 1 June to 30 September"), y = NULL) +
    theme_burns(base_size = 13) +
    ggplot2::theme(legend.position = "bottom", legend.direction = "vertical",
                   plot.margin = ggplot2::margin(14, 8, 4, 4))
}

# ------------------------------------------------------------------------------
# Concentration of burned area in the largest fires
# ------------------------------------------------------------------------------

#' Concentration curve: cumulative share of burned area held by the largest
#' fires, for one year or several (ranked largest first, Jun-Sep window).
#' @param years integer vector
#' @return tibble(year, rank_share [share of fires, largest first], cum_share, n_fires,
#'   total_ha)
build_concentration <- function(years, snapshot_dir, eu, start_month = 6L,
                                end_month = 9L, version = 1) {
  key <- sprintf("retro_concentration_%d_%d_%d_%d_snap%s", min(years), max(years),
                 start_month, end_month, basename(snapshot_dir))
  cached(key, {
    purrr::map_dfr(years, function(y) {
      a <- get_tagged_summer(y, snapshot_dir, eu, start_month, end_month) |>
        sf::st_drop_geometry() |>
        dplyr::filter(is.finite(area_ha), area_ha > 0) |>
        dplyr::pull(area_ha) |>
        sort(decreasing = TRUE)
      tibble::tibble(year = y, rank_share = seq_along(a) / length(a),
                     cum_share = cumsum(a) / sum(a), n_fires = length(a),
                     total_ha = sum(a))
    })
  }, version = version)
}

#' Area share held by the largest p of fires, interpolated at rank share p.
#' @param conc output of build_concentration() for one year
#' @param p fire share (0-1), e.g. 0.01
top_share <- function(conc, p) {
  # ceiling so "top 1%" means at least ceiling(p * n) fires
  k <- ceiling(p * conc$n_fires[1])
  conc$cum_share[k]
}

#' Concentration curve plot (log x). Current year in orange with the top 1% and
#' top 10% points labelled; optional faint grey curves for earlier years.
#' @param conc output of build_concentration() including the current year
#' @param show_history draw earlier years as faint grey curves
#' @return ggplot
plot_concentration <- function(conc, year_current = 2026L, show_history = FALSE,
                               col_current = burns_brand$ember) {
  cur <- conc |> dplyr::filter(year == year_current)
  marks <- tibble::tibble(p = c(0.01, 0.10)) |>
    dplyr::mutate(
      k = ceiling(p * cur$n_fires[1]),
      x = k / cur$n_fires[1],
      y = cur$cum_share[k],
      lab = sprintf("Largest %d%% of fires:\n%s of burned area", round(100 * p),
                    scales::label_percent(accuracy = 1)(y))
    )
  g <- ggplot2::ggplot()
  if (show_history) {
    g <- g + ggplot2::geom_line(
      data = conc |> dplyr::filter(year != year_current),
      ggplot2::aes(rank_share, cum_share, group = year),
      colour = "grey70", linewidth = 0.5, alpha = 0.8
    )
  }
  g +
    ggplot2::geom_line(data = cur, ggplot2::aes(rank_share, cum_share),
                       colour = col_current, linewidth = 1.4) +
    ggplot2::geom_point(data = marks, ggplot2::aes(x, y), colour = col_current, size = 3.6) +
    ggplot2::geom_text(data = marks, ggplot2::aes(x, y, label = lab), hjust = -0.08,
                       vjust = 1.4, size = 4, lineheight = 0.95, colour = "grey15") +
    ggplot2::scale_x_log10(
      breaks = c(1e-3, 1e-2, 1e-1, 1), labels = scales::label_percent(accuracy = 0.1, drop0trailing = TRUE),
      expand = ggplot2::expansion(mult = c(0.02, 0.05))
    ) +
    ggplot2::scale_y_continuous(labels = scales::label_percent(accuracy = 1),
                                limits = c(0, 1), expand = ggplot2::expansion(mult = c(0, 0.03))) +
    ggplot2::labs(x = "Share of fires, ranked largest first (log scale)",
                  y = "Cumulative share of burned area") +
    theme_burns(base_size = 13) +
    ggplot2::theme(panel.grid.major.y = ggplot2::element_line(colour = "grey90"))
}

# ------------------------------------------------------------------------------
# Re-burn by country
# ------------------------------------------------------------------------------

#' Per country: 2026 burned area and the part overlapping the mapped
#' historical footprint (2017-2025 scars, simplified at 100 m). Each country's
#' perimeters are intersected with the footprint separately. Cached per snapshot.
#' @param tagged_current sf of the current year's tagged perimeters (name_long)
#' @param footprint sfc from get_historical_footprint()
#' @param tag cache label identifying the current-year window (e.g. "full2026")
#' @return tibble(name_long, total_ha, reburn_ha, reburn_share, no_overlap_ha)
build_reburn_by_country <- function(tagged_current, footprint, snapshot_dir, tag = "full",
                                    version = 1) {
  key <- sprintf("retro_reburn_country_%s_snap%s", tag, basename(snapshot_dir))
  cached(key, {
    ctry <- tagged_current |> dplyr::filter(!is.na(name_long))
    purrr::map_dfr(unique(ctry$name_long), function(cty) {
      r <- compute_reburn(ctry[ctry$name_long == cty, ], footprint)
      tibble::tibble(name_long = cty, total_ha = r$total_ha, reburn_ha = r$reburn_ha)
    }) |>
      dplyr::mutate(reburn_ha = pmin(reburn_ha, total_ha),  # 100 m simplification can overshoot
                    reburn_share = reburn_ha / total_ha,
                    no_overlap_ha = total_ha - reburn_ha)
  }, version = version)
}

#' Ranked horizontal bars: share of each country's 2026 burned area that
#' overlaps mapped 2017-2025 scars, hectares labelled. Wording is deliberately
#' "overlaps" / "no overlap", never "first-time burn".
#' @param tbl output of build_reburn_by_country()
#' @param n_top number of countries (by 2026 area)
#' @return ggplot
plot_reburn_by_country <- function(tbl, n_top = 12L, hist_label = "2017-2025",
                                   col_current = burns_brand$ember) {
  d <- tbl |>
    dplyr::slice_max(total_ha, n = n_top, with_ties = FALSE) |>
    dplyr::arrange(reburn_share) |>
    dplyr::mutate(name_long = factor(name_long, levels = name_long),
                  lab = sprintf("%s of %s ha", scales::label_number(big.mark = ",", accuracy = 1)(reburn_ha),
                                scales::label_number(big.mark = ",", accuracy = 1)(total_ha)))
  k_ov <- sprintf("Overlaps mapped %s scars", hist_label)
  k_no <- sprintf("No overlap with mapped %s scars", hist_label)
  long <- d |>
    dplyr::transmute(name_long, share_ov = reburn_share, share_no = 1 - reburn_share) |>
    tidyr::pivot_longer(c(share_ov, share_no), names_to = "kind", values_to = "share") |>
    dplyr::mutate(kind = factor(ifelse(kind == "share_ov", k_ov, k_no), levels = c(k_no, k_ov)))
  ggplot2::ggplot(long, ggplot2::aes(share, name_long, fill = kind)) +
    ggplot2::geom_col(width = 0.7) +
    ggplot2::geom_text(data = d, ggplot2::aes(x = 1.02, y = name_long, label = lab),
                       inherit.aes = FALSE, hjust = 0, size = 3.7, colour = "grey15") +
    ggplot2::scale_fill_manual(name = NULL, values = stats::setNames(c("grey82", col_current), c(k_no, k_ov)),
                               breaks = c(k_ov, k_no), guide = ggplot2::guide_legend(ncol = 1)) +
    ggplot2::scale_x_continuous(labels = scales::label_percent(accuracy = 1),
                                breaks = c(0, 0.25, 0.5, 0.75, 1),
                                expand = ggplot2::expansion(mult = c(0, 0.42))) +
    ggplot2::coord_cartesian(clip = "off") +
    ggplot2::labs(x = "Share of 2026 burned area (labels: overlapping of total)", y = NULL) +
    theme_burns(base_size = 13) +
    ggplot2::theme(legend.position = "bottom")
}

# ------------------------------------------------------------------------------
# What the last month of mapping added (two snapshots of the 2026 file)
# ------------------------------------------------------------------------------

#' Europe-clipped 2026 perimeters of one snapshot, one row per EFFIS id, with
#' the raw date fields kept. Cached per snapshot.
#' @return tibble(id, ba_date, firedate, lastupdate, finaldate, area_ha)
read_snapshot_2026 <- function(snapshot_dir, eu, year = 2026L, version = 1) {
  key <- sprintf("retro_snapshot_%d_clipped_snap%s", year, basename(snapshot_dir))
  cached(key, {
    x <- clip_europe_year(year, snapshot_dir, eu)
    nm <- intersect(c("id", "ba_date", "firedate", "lastupdate", "finaldate", "area_ha"), names(x))
    x |> sf::st_drop_geometry() |> dplyr::select(dplyr::all_of(nm)) |>
      dplyr::group_by(id) |>
      dplyr::summarise(ba_date = min(ba_date),
                       dplyr::across(dplyr::any_of(c("firedate", "lastupdate", "finaldate")),
                                     ~ dplyr::first(as.character(.x))),
                       area_ha = sum(area_ha), .groups = "drop")
  }, version = version)
}

#' Decompose the change in total mapped 2026 area between two snapshots by EFFIS id.
#' @param old_dir,new_dir snapshot directories (e.g. 2026-09-03 and 2026-10-02)
#' @param old_cut Date: last day covered by the old snapshot (2026-09-02)
#' @param start,end window of perimeter dates kept in both snapshots (default: the
#'   1 Jun - 30 Sep season window, so totals tie to the post's season figures)
#' @return list(table = tibble(step, ha), id_check = list(n_old, n_new, n_matched,
#'   n_removed, n_added, n_date_changed), old = tibble, new = tibble)
build_mapping_additions <- function(old_dir, new_dir, eu, old_cut = as.Date("2026-09-02"),
                                    start = as.Date("2026-06-01"), end = as.Date("2026-09-30")) {
  old <- read_snapshot_2026(old_dir, eu) |> dplyr::filter(ba_date >= start, ba_date <= end)
  new <- read_snapshot_2026(new_dir, eu) |> dplyr::filter(ba_date >= start, ba_date <= end)
  both <- dplyr::inner_join(old, new, by = "id", suffix = c("_old", "_new"))
  added <- dplyr::anti_join(new, old, by = "id")
  removed <- dplyr::anti_join(old, new, by = "id")
  steps <- tibble::tibble(
    step = c("Snapshot 2026-09-03", "Dated after 2 Sep (new dates)",
             "New perimeters dated on or before 2 Sep (late additions)",
             "Revisions to existing perimeters", "Perimeters removed",
             "Final snapshot 2026-10-02"),
    ha = c(sum(old$area_ha),
           sum(added$area_ha[added$ba_date > old_cut]),
           sum(added$area_ha[added$ba_date <= old_cut]),
           sum(both$area_ha_new - both$area_ha_old),
           -sum(removed$area_ha),
           sum(new$area_ha))
  )
  list(
    table = steps,
    id_check = list(n_old = nrow(old), n_new = nrow(new), n_matched = nrow(both),
                    n_removed = nrow(removed), n_added = nrow(added),
                    n_date_changed = sum(both$ba_date_old != both$ba_date_new),
                    n_revised_area = sum(abs(both$area_ha_new - both$area_ha_old) > 0.01),
                    n_after_cut_in_old = sum(old$ba_date > old_cut)),
    old = old, new = new
  )
}

#' Waterfall from the earlier snapshot total to the final total.
#' @param tbl the `table` element of build_mapping_additions()
#' @return ggplot
plot_mapping_waterfall <- function(tbl, col_current = burns_brand$ember) {
  n <- nrow(tbl)
  d <- tbl |>
    dplyr::mutate(
      i = dplyr::row_number(),
      is_total = i %in% c(1L, n),
      end = ifelse(is_total, ha, NA_real_),
      cum_after = cumsum(ifelse(is_total & i == n, 0, ha)),
      ymin = ifelse(is_total, 0, cum_after - ha),
      ymax = ifelse(is_total, ha, cum_after),
      kind = dplyr::case_when(is_total ~ "Total", ha >= 0 ~ "Added", TRUE ~ "Removed"),
      step_lab = factor(step, levels = rev(step)),
      lab = scales::label_number(big.mark = ",", accuracy = 1, style_positive = "plus")(ha)
    )
  d$lab[d$is_total] <- scales::label_number(big.mark = ",", accuracy = 1)(d$ha[d$is_total])
  d$step_lab <- factor(retro_wrap(d$step, 26), levels = rev(retro_wrap(d$step, 26)))
  ggplot2::ggplot(d, ggplot2::aes(y = step_lab, fill = kind)) +
    ggplot2::geom_rect(ggplot2::aes(xmin = ymin, xmax = ymax, ymin = as.numeric(step_lab) - 0.36,
                                    ymax = as.numeric(step_lab) + 0.36)) +
    ggplot2::geom_text(ggplot2::aes(x = pmax(ymin, ymax), label = lab), hjust = -0.1, size = 3.8,
                       colour = "grey15") +
    ggplot2::scale_fill_manual(name = NULL, breaks = c("Total", "Added", "Removed"),
                               values = c(Total = "grey55", Added = col_current, Removed = "#1F78B4")) +
    ggplot2::scale_x_continuous(labels = scales::label_number(big.mark = ","),
                                expand = ggplot2::expansion(mult = c(0, 0.15))) +
    ggplot2::labs(x = "Mapped 2026 burned area (hectares)", y = NULL) +
    theme_burns(base_size = 13) +
    ggplot2::theme(legend.position = "none")
}

# base-R word wrap so the waterfall needs no extra package
retro_wrap <- function(x, width) vapply(x, function(s) paste(strwrap(s, width), collapse = "\n"), "")
