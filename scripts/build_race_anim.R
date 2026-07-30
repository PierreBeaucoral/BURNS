#!/usr/bin/env Rscript
# ==============================================================================
# build_race_anim.R
# "Season race": a two-panel animation that plays the current season back day by
# day, with the map and the envelope chart locked to the same clock.
#
#   LEFT  panel -- Europe. Perimeters accumulate. A fire flares bright on its
#                  detection day (with a centroid halo sized by sqrt(area), so a
#                  megafire reads as a megafire and not as one pixel among
#                  thousands), glows for two more days, then settles to a muted
#                  scar.
#   RIGHT panel -- the site's envelope chart drawing itself: the current-year
#                  cumulative line advancing into the 2017-2025 min-max band,
#                  against the historical median.
#
# The two panels share one frame schedule, so a flare on the map and a step in
# the line are the SAME event. That is the whole point: the 2025 animations
# showed when things happened; this one shows whether it is unusual, as it
# happens.
#
# Why hand-rolled frames instead of gganimate: this needs per-day pacing (hold
# on the biggest days), an age-dependent flare, inline annotations that appear
# only on specific dates, and two panels composited per frame. Driving that
# through transition_states() fights the library; a plain frame loop with
# patchwork + gifski is both simpler and faster.
#
# Usage (from project root):
#   Rscript scripts/build_race_anim.R            # current season, default output
#   Rscript scripts/build_race_anim.R 2025       # rebuild for an archived season
#
# Output: assets/anim/<year>-race.gif
# ==============================================================================

suppressPackageStartupMessages({
  library(sf); library(dplyr); library(ggplot2); library(scales)
  library(lubridate); library(patchwork); library(gifski)
})

Sys.setenv(OGR_GEOJSON_MAX_OBJ_SIZE = "0")

if (!dir.exists("R")) stop("run from the project root (R/ not found here)")
invisible(lapply(list.files("R", pattern = "[.]R$", full.names = TRUE), source))
source(file.path("scripts", "latest_snapshot.R"))

# -------------------- Parameters --------------------
args        <- commandArgs(trailingOnly = TRUE)
YEAR        <- if (length(args)) as.integer(args[1]) else 2026L
HIST_YEARS  <- 2017:2025
START_MONTH <- 6L
END_MONTH   <- 9L

N_HOLD      <- 8L    # extra frames held on each of the biggest burn days
N_TOP       <- 3L    # how many days get a hold + inline annotation
N_END_PAUSE <- 14L   # frames frozen on the final state (makes a usable still)
FPS         <- 12
W_PX        <- 1500
H_PX        <- 780
DPI         <- 110

OUT_DIR <- file.path("assets", "anim")
dir.create(OUT_DIR, recursive = TRUE, showWarnings = FALSE)
OUT_GIF <- file.path(OUT_DIR, sprintf("%d-race.gif", YEAR))

message("Season race: ", YEAR, "  (hist band ", min(HIST_YEARS), "-", max(HIST_YEARS), ")")

# -------------------- Data (all disk-cached by the pipeline) --------------------
snap <- latest_snapshot(); stopifnot(!is.na(snap))
eu   <- get_eu()

envelope <- build_envelope(
  hist_years = HIST_YEARS, year_current = YEAR, snapshot_dir = snap, eu = eu,
  start_month = START_MONTH, end_month = END_MONTH
)
band    <- envelope$band
current <- envelope$current
meta    <- envelope$meta
as_of   <- meta$as_of_date

tagged <- get_tagged_summer(YEAR, snap, eu, START_MONTH, END_MONTH) |>
  filter(ba_date <= as_of)

# Simplify once: every frame redraws the whole accumulated set, and at
# continental zoom ~1 km of detail is invisible. clean_polygons() is required --
# the simplify/intersect chain leaves a few GEOMETRYCOLLECTIONs behind, which
# break downstream sf plotting.
geom_simp <- clean_polygons(
  st_simplify(st_geometry(tagged), dTolerance = 1000, preserveTopology = TRUE)
)
tagged_s <- tagged
st_geometry(tagged_s) <- geom_simp
tagged_s <- tagged_s |> filter(!st_is_empty(st_geometry(tagged_s)))

# Centroids drive the flare halo (suppress the lon/lat warning: we are in 3035,
# an equal-area projected CRS, where centroids are well defined).
cent <- suppressWarnings(st_centroid(tagged_s))
cent_xy <- as.data.frame(st_coordinates(cent))
names(cent_xy) <- c("cx", "cy")
flare <- bind_cols(st_drop_geometry(tagged_s)[, c("ba_date", "area_ha")], cent_xy)

# -------------------- Frame schedule --------------------
season_start <- as.Date(sprintf("%d-%02d-01", YEAR, START_MONTH))
dates        <- seq(season_start, as_of, by = "day")

daily <- st_drop_geometry(tagged_s) |>
  group_by(ba_date) |>
  summarise(day_ha = sum(area_ha, na.rm = TRUE), .groups = "drop")

top_days <- daily |> slice_max(day_ha, n = N_TOP) |> arrange(desc(day_ha))

# Name every fire that actually drove the day, not just the single biggest.
# On 22 July 2026 a Spanish megafire (Navaluenga, Avila) and a French one
# (Porge, Gironde) burned within ~5,000 ha of each other; labelling only the
# largest would silently present it as a Spain-only day. Keep the top LAB_MAX
# fires, dropping any that contributed less than LAB_SHARE of the day's area,
# but always keep at least one. Country code is included so a reader does not
# have to know which country "Gironde" or "Avila" is in.
LAB_MAX   <- 3L
LAB_SHARE <- 0.10

top_labels <- lapply(seq_len(nrow(top_days)), function(i) {
  d      <- top_days$ba_date[i]
  day_ha <- top_days$day_ha[i]
  flat   <- st_drop_geometry(tagged_s)

  big <- flat |> filter(ba_date == d) |> slice_max(area_ha, n = LAB_MAX)
  keep <- big$area_ha >= LAB_SHARE * day_ha
  keep[1] <- TRUE                       # never drop the day's leading fire
  big <- big[keep, , drop = FALSE]

  header <- sprintf("%s %s: %s across %d fires",
                    day(d), month.abb[month(d)], lab_si_ha(day_ha),
                    sum(flat$ba_date == d))
  lines <- sprintf("%s, %s (%s): %s",
                   big$commune, big$province, big$iso_a2, lab_si_ha(big$area_ha))
  paste(c(header, lines), collapse = "\n")
})
names(top_labels) <- as.character(top_days$ba_date)

hold <- rep(1L, length(dates))
hold[dates %in% top_days$ba_date] <- 1L + N_HOLD
frame_dates <- c(rep(dates, hold), rep(as_of, N_END_PAUSE))
message("frames: ", length(frame_dates), " (", length(dates), " days, ",
        nrow(top_days), " held, ", N_END_PAUSE, " end-pause)")

# -------------------- Fixed extents (must not drift between frames) ----------
# Frame on where the season actually burns. A raw bbox of all perimeters is
# dragged north by a handful of Nordic outliers and leaves half the panel empty,
# so use the 1st-99th percentile of fire centroids weighted by nothing more
# clever than count, then pad. Outlying fires still DRAW (they are simply near
# the edge or just outside); this only chooses the viewport, and the figure
# caption says so.
qx <- quantile(flare$cx, c(0.01, 0.99), names = FALSE)
qy <- quantile(flare$cy, c(0.01, 0.99), names = FALSE)
padx <- 0.06 * diff(qx); pady <- 0.06 * diff(qy)
xlim_map <- c(qx[1] - padx, qx[2] + padx)
ylim_map <- c(qy[1] - pady, qy[2] + pady)

y_max <- max(band$max_ha, na.rm = TRUE) * 1.05
x_rng <- range(band$ref_date)

col_new   <- burns_brand$ember_bright   # today
col_glow  <- burns_brand$ember          # 1-2 days old
col_scar  <- "#8A4A2E"                  # settled scar (muted ember)

frame_dir <- file.path(tempdir(), sprintf("race_%d", YEAR))
unlink(frame_dir, recursive = TRUE); dir.create(frame_dir, recursive = TRUE)

month_lab <- function(d) month.abb[month(d)]

# -------------------- Frame loop --------------------
t_start <- Sys.time()
files <- character(length(frame_dates))

for (i in seq_along(frame_dates)) {
  d <- frame_dates[i]

  acc <- tagged_s[tagged_s$ba_date <= d, ]
  age <- as.integer(d - acc$ba_date)
  scars  <- acc[age > 2, ]
  glows  <- acc[age >= 1 & age <= 2, ]
  newest <- acc[age == 0, ]

  fl <- flare[flare$ba_date == d, , drop = FALSE]
  # Persistent centroid dots. At continental zoom a typical perimeter is well
  # under one pixel, so polygons alone make the accumulating season look empty.
  # The dots guarantee every mapped fire registers; the polygons still carry
  # the real shape of the big ones.
  fa <- flare[flare$ba_date <= d, , drop = FALSE]
  fa$age <- as.integer(d - fa$ba_date)

  p_map <- ggplot() +
    geom_sf(data = eu$poly, fill = "grey94", color = "grey78", linewidth = 0.15)

  if (nrow(scars))
    p_map <- p_map + geom_sf(data = scars, fill = col_scar, colour = col_scar,
                             alpha = 0.55, linewidth = 0.05)
  if (any(fa$age > 2))
    p_map <- p_map +
      geom_point(data = fa[fa$age > 2, ], aes(x = cx, y = cy, size = area_ha),
                 colour = col_scar, alpha = 0.45, stroke = 0, show.legend = FALSE)
  if (nrow(glows))
    p_map <- p_map + geom_sf(data = glows, fill = col_glow, colour = col_glow,
                             alpha = 0.80, linewidth = 0.07)
  if (any(fa$age >= 1 & fa$age <= 2))
    p_map <- p_map +
      geom_point(data = fa[fa$age >= 1 & fa$age <= 2, ],
                 aes(x = cx, y = cy, size = area_ha),
                 colour = col_glow, alpha = 0.75, stroke = 0, show.legend = FALSE)
  if (nrow(newest))
    p_map <- p_map + geom_sf(data = newest, fill = col_new, colour = col_new,
                             alpha = 0.95, linewidth = 0.10)
  if (nrow(fl))
    p_map <- p_map +
      geom_point(data = fl, aes(x = cx, y = cy, size = area_ha),
                 colour = col_new, alpha = 0.95, stroke = 0, show.legend = FALSE) +
      # Hollow ring: the "flare". It rides the SAME size scale (x5 area, so
      # ~2.2x the radius of its own dot), which keeps the ring proportional to
      # sqrt(area) rather than being a decorative fixed-size marker.
      geom_point(data = transform(fl, ring = area_ha * 5),
                 aes(x = cx, y = cy, size = ring),
                 shape = 21, colour = col_new, fill = NA,
                 stroke = 1.0, alpha = 0.55, show.legend = FALSE)

  p_map <- p_map +
    scale_size_area(max_size = 11) +   # area-proportional: radius ~ sqrt(ha)
    coord_sf(xlim = xlim_map, ylim = ylim_map, expand = FALSE) +
    labs(x = NULL, y = NULL) +
    theme_burns(base_size = 12, map = TRUE)

  # ---- right: envelope drawing itself ----
  cur <- current[current$ba_date <= d, ]
  tip <- cur[nrow(cur), ]

  p_line <- ggplot() +
    geom_ribbon(data = band, aes(x = ref_date, ymin = min_ha, ymax = max_ha),
                fill = "grey80", alpha = 0.55) +
    geom_line(data = band, aes(x = ref_date, y = median_ha),
              color = "grey35", linewidth = 0.6, linetype = "22") +
    # guard: a 1-row series is a point, not a line (ggplot warns otherwise)
    {if (nrow(cur) > 1)
       geom_line(data = cur, aes(x = ba_date, y = cum_ha),
                 color = burns_brand$ember, linewidth = 1.4, lineend = "round")
     else NULL} +
    geom_point(data = tip, aes(x = ba_date, y = cum_ha),
               color = burns_brand$ember, size = 3.1) +
    annotate("text", x = tip$ba_date + 2.5, y = tip$cum_ha,
             label = lab_si_ha(tip$cum_ha), hjust = 0, vjust = 0.5,
             size = 4.1, fontface = "bold", color = burns_brand$ember) +
    scale_x_date(limits = x_rng, date_breaks = "1 month", labels = month_lab,
                 expand = expansion(mult = c(0.01, 0.10))) +
    scale_y_continuous(limits = c(0, y_max), labels = lab_si_ha,
                       expand = expansion(mult = c(0, 0))) +
    labs(x = NULL, y = "Cumulative burned area since 1 June (ha)") +
    theme_burns(base_size = 12)

  # Inline annotation on the headline days, held for the duration of the hold.
  key <- as.character(d)
  if (!is.null(top_labels[[key]])) {
    p_line <- p_line +
      annotate("label", x = x_rng[1] + 2, y = y_max * 0.95,
               label = top_labels[[key]], hjust = 0, vjust = 1, size = 3.9,
               fontface = "bold", colour = burns_brand$ember_deep,
               fill = alpha("white", 0.88), label.size = 0)
  }

  # ---- readout ----
  med_now <- band$median_ha[band$ref_date == d]
  pct <- if (length(med_now) && !is.na(med_now) && med_now > 1e-9) {
    sprintf("%.0f%% of a typical season by this date", 100 * tip$cum_ha / med_now)
  } else "early season: no historical median yet"

  combined <- (p_map | p_line) +
    plot_layout(widths = c(1, 1.15)) +
    plot_annotation(
      title    = sprintf("%s %s %d", day(d), month.name[month(d)], YEAR),
      subtitle = pct,
      theme = theme(
        plot.title    = element_text(face = "bold", size = 19,
                                     colour = burns_brand$forest_deep),
        plot.subtitle = element_text(size = 13, colour = burns_brand$ember_deep)
      )
    )

  f <- file.path(frame_dir, sprintf("f%04d.png", i))
  ggsave(f, combined, width = W_PX / DPI, height = H_PX / DPI,
         units = "in", dpi = DPI, bg = "white")
  files[i] <- f

  if (i %% 20 == 0 || i == length(frame_dates)) {
    el <- as.numeric(Sys.time() - t_start, units = "secs")
    message(sprintf("  frame %d/%d  (%.2f s/frame, ~%.1f min left)",
                    i, length(frame_dates), el / i,
                    (length(frame_dates) - i) * (el / i) / 60))
  }
}

# -------------------- Encode --------------------
message("encoding ", length(files), " frames -> ", OUT_GIF)
gifski(files, gif_file = OUT_GIF, width = W_PX, height = H_PX,
       delay = 1 / FPS, progress = FALSE)
unlink(frame_dir, recursive = TRUE)

message(sprintf("done: %s (%.1f MB, %.1f min total)",
                OUT_GIF, file.size(OUT_GIF) / 1024^2,
                as.numeric(Sys.time() - t_start, units = "mins")))
