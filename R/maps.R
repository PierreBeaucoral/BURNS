# ==============================================================================
# maps.R
# Overview map of a season's fires for the final assessment page.
#
# At continental scale individual outlines are sub-pixel, so each fire is drawn
# as a circle whose AREA is proportional to burned area (sqrt radius scaling),
# coloured by period. Two zoomed insets (Iberia, western Balkans) carry the
# place labels for the biggest fires there; fires elsewhere are labelled on the
# main panel. Labels use province + country, never the EFFIS commune string
# (re-attributed between snapshots).
# Required packages: sf, ggplot2, patchwork, ggrepel, scales, dplyr
# Requires theme.R (theme_burns) to be sourced first.
# ==============================================================================

#' Default inset windows for plot_overview_map()
#' @return named list of lon/lat boxes c(xmin, xmax, ymin, ymax) in EPSG:4326
overview_insets <- function() {
  list(
    "Iberia and south-west France" = c(-9.8, 3.6, 36.0, 45.2),
    "Western Balkans"              = c(14.8, 24.0, 40.3, 46.4)
  )
}

#' Label a fire as "Province, Country" (country only when province is not Latin
#' script, which would not render in the plot font)
#' @param province,country character vectors
#' @return character vector
overview_place_label <- function(province, country) {
  latin <- !is.na(province) & grepl("^[\\p{Latin}0-9 .,'()/-]+$", province, perl = TRUE) &
    province != "N.A."
  ifelse(latin, paste0(province, ", ", country), country)
}

#' Overview map of a season's fires: area-proportional circles plus insets
#'
#' @param tagged sf of fire perimeters (EPSG:3035) with `area_ha`, `ba_date`,
#'   `province`, `name_long`
#' @param eu list from get_eu(); `eu$poly` is the Europe outline
#' @param summer_start Date; fires before it are "January-May". Defaults to
#'   1 June of the latest fire year.
#' @param n_labels number of largest fires to label
#' @param insets named list of lon/lat boxes (see overview_insets())
#' @param size_breaks hectare values shown in the size legend
#' @param max_size point size of the largest legend break
#' @param base_size base font size
#' @return a patchwork object (no title; caption belongs in the document)
plot_overview_map <- function(tagged, eu, summer_start = NULL, n_labels = 10L,
                              insets = overview_insets(),
                              size_breaks = c(1000, 10000, 40000),
                              max_size = 13, base_size = 13) {
  yr <- as.integer(format(max(tagged$ba_date, na.rm = TRUE), "%Y"))
  if (is.null(summer_start)) summer_start <- as.Date(sprintf("%d-06-01", yr))
  pal <- c("January–May" = "#3E8EC4", "Summer (from 1 June)" = "#D64A05")

  cent <- suppressWarnings(sf::st_centroid(sf::st_geometry(tagged)))
  xy <- sf::st_coordinates(cent)
  d <- sf::st_drop_geometry(tagged)[, c("area_ha", "ba_date", "province", "name_long")]
  d$x <- xy[, 1]; d$y <- xy[, 2]
  d <- d[is.finite(d$area_ha) & d$area_ha > 0, ]
  d$period <- factor(ifelse(d$ba_date < summer_start, names(pal)[1], names(pal)[2]),
                     levels = names(pal))
  d <- d[order(-d$area_ha), ]          # big circles first = drawn underneath
  d$place <- overview_place_label(d$province,
                                  sub("Bosnia and Herzegovina", "Bosnia-Herz.", d$name_long))
  d$rank <- seq_len(nrow(d))
  lab <- d[d$rank <= n_labels, ]

  # Inset windows in EPSG:3035
  box_sf <- function(b) {
    sf::st_as_sfc(sf::st_bbox(c(xmin = b[1], xmax = b[2], ymin = b[3], ymax = b[4]),
                              crs = 4326)) |>
      sf::st_segmentize(0.1) |> sf::st_transform(3035)
  }
  boxes <- lapply(insets, box_sf)
  in_box <- function(x, y, bx) {
    bb <- sf::st_bbox(bx); x >= bb["xmin"] & x <= bb["xmax"] & y >= bb["ymin"] & y <= bb["ymax"]
  }
  lab$inset <- 0L
  for (i in seq_along(boxes)) lab$inset[lab$inset == 0L & in_box(lab$x, lab$y, boxes[[i]])] <- i

  size_scale <- ggplot2::scale_size_area(
    max_size = max_size, limits = c(0, max(size_breaks)),
    breaks = size_breaks, labels = scales::label_comma(),
    name = "Circle area proportional to burned area (hectares)",
    oob = scales::squish
  )
  fill_scale <- ggplot2::scale_fill_manual(values = pal, name = NULL)
  colour_scale <- ggplot2::scale_colour_manual(values = pal, name = NULL)

  # Shared layers; `label_df` rows get repelled text
  base_layers <- function(win_x, win_y, label_df, label_size, lw = 0.2, top_pad = 0) {
    list(
      ggplot2::geom_sf(data = eu$poly, fill = "grey95", colour = "grey72",
                       linewidth = 0.15, inherit.aes = FALSE),
      ggplot2::geom_point(data = d, ggplot2::aes(x, y, size = area_ha, fill = period,
                                                 colour = period),
                          shape = 21, alpha = 0.45, stroke = lw),
      ggrepel::geom_text_repel(
        data = label_df, ggplot2::aes(x, y, label = place),
        inherit.aes = FALSE, size = label_size, colour = "grey10", fontface = "bold",
        min.segment.length = 0, segment.colour = "grey30", segment.size = 0.3,
        box.padding = 0.8, point.padding = 0.2, max.overlaps = Inf, seed = 1,
        bg.colour = "white", bg.r = 0.15, force = 6, force_pull = 0.5,
        xlim = win_x, ylim = c(win_y[1], win_y[2] - top_pad * diff(win_y))
      ),
      size_scale, fill_scale, colour_scale,
      ggplot2::coord_sf(xlim = win_x, ylim = win_y, expand = FALSE, crs = sf::st_crs(3035))
    )
  }

  # Main panel window: fire extent, padded
  rx <- range(d$x); ry <- range(d$y)
  px <- 0.04 * diff(rx); py <- 0.04 * diff(ry)
  win_x <- c(rx[1] - px, rx[2] + px); win_y <- c(ry[1] - py, ry[2] + py)

  main_lab <- lab[lab$inset == 0L, ]
  box_df <- do.call(rbind, lapply(seq_along(boxes), function(i) {
    b <- sf::st_bbox(boxes[[i]])
    data.frame(xmin = b[[1]], ymin = b[[2]], xmax = b[[3]], ymax = b[[4]],
               tag = LETTERS[i])
  }))

  p_main <- ggplot2::ggplot() +
    base_layers(win_x, win_y, main_lab, label_size = base_size * 0.30) +
    ggplot2::geom_rect(data = box_df, inherit.aes = FALSE,
                       ggplot2::aes(xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax),
                       fill = NA, colour = "grey25", linewidth = 0.5) +
    ggplot2::geom_label(data = box_df, inherit.aes = FALSE,
                        ggplot2::aes(x = xmin, y = ymax, label = tag),
                        size = base_size * 0.30, fontface = "bold", hjust = 0, vjust = 0,
                        linewidth = 0, fill = "white", label.padding = grid::unit(0.15, "lines")) +
    theme_burns(base_size = base_size, map = TRUE) +
    ggplot2::theme(legend.position = "bottom", legend.box = "vertical",
                   legend.title.position = "top",
                   legend.margin = ggplot2::margin(0, 0, 0, 0)) +
    ggplot2::guides(
      fill = ggplot2::guide_legend(order = 1, override.aes = list(size = 5, alpha = 0.7)),
      colour = "none",
      size = ggplot2::guide_legend(order = 2, nrow = 1,
                                   override.aes = list(fill = "grey60", colour = "grey30",
                                                       alpha = 0.6))
    )

  inset_plot <- function(i) {
    b <- sf::st_bbox(boxes[[i]])
    ggplot2::ggplot() +
      base_layers(c(b[["xmin"]], b[["xmax"]]), c(b[["ymin"]], b[["ymax"]]),
                  lab[lab$inset == i, ], label_size = base_size * 0.32, lw = 0.25,
                  top_pad = 0.10) +
      ggplot2::annotate("label", x = b[["xmin"]], y = b[["ymax"]],
                        label = paste0(LETTERS[i], "  ", names(boxes)[i]),
                        hjust = 0, vjust = 1, size = base_size * 0.30, fontface = "bold",
                        linewidth = 0, fill = "white") +
      theme_burns(base_size = base_size, map = TRUE) +
      ggplot2::theme(legend.position = "none",
                     panel.border = ggplot2::element_rect(colour = "grey25", fill = NA,
                                                          linewidth = 0.5))
  }
  # Iberia is taller than wide, the Balkans squarer: give height by aspect
  asp <- vapply(boxes, function(bx) {
    b <- sf::st_bbox(bx); (b[["ymax"]] - b[["ymin"]]) / (b[["xmax"]] - b[["xmin"]])
  }, numeric(1))
  right <- patchwork::wrap_plots(lapply(seq_along(boxes), inset_plot), ncol = 1,
                                 heights = asp)
  patchwork::wrap_plots(p_main, right, nrow = 1L, widths = c(1.35, 1))
}
