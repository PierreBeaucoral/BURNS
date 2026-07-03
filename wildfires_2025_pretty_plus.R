# wildfires_2025_pretty_plus.R
# Pretty+ workflow using ONLY local data:
# - Burnt area perimeters: data/effis_layer/modis.ba.poly.shp
# - Severity rasters:     data/severity/severity_YYYY.tiff (2018..2024 available)
# - Country totals 2023:  data/report_2023.xlsx  (optional cross-check)

# ---- Packages ----
pkgs <- c("sf","dplyr","stringr","lubridate","ggplot2","readxl","forcats",
          "rnaturalearth","rnaturalearthdata","janitor","scales","patchwork")
to_i <- pkgs[!(pkgs %in% rownames(installed.packages()))]
if(length(to_i)) install.packages(to_i, Ncpus = max(1, parallel::detectCores()-1))
suppressPackageStartupMessages({
  library(sf); library(dplyr); library(stringr); library(lubridate); library(ggplot2)
  library(readxl); library(forcats); library(rnaturalearth); library(janitor); library(scales); library(patchwork)
})

# ---- Paths (local only) ----
shp_path <- "data/effis_layer/modis.ba.poly.shp"
sev_dir  <- "data/severity"
ctry_tot_2023 <- "data/report_2023.xlsx"

stopifnot(file.exists(shp_path))

# ---- Europe polygons (EU27 + EFTA + UK) ----
eu_keep <- c(
  "AT","BE","BG","HR","CY","CZ","DK","EE","FI","FR","DE","GR","HU","IE","IT","LV","LT","LU","MT","NL",
  "PL","PT","RO","SK","SI","ES","SE",   # EU27
  "NO","IS","CH","LI",                  # EFTA
  "GB"                                  # UK
)
eu_poly <- rnaturalearth::ne_countries(scale = "medium", returnclass = "sf") |>
  select(iso_a2, name_long, geometry) |>
  filter(iso_a2 %in% eu_keep) |>
  st_transform(3035)  # LAEA Europe

# ---- Read burnt-area perimeters (local shapefile) ----
ba_all <- suppressWarnings(st_read(shp_path, quiet = TRUE)) |> janitor::clean_names()

# Detect a date column (schema-robust)
# ---- Detect & parse date column (robust to schema) ----
cand_names <- tolower(names(ba_all))
# common possibilities seen in EFFIS-like layers
wanted <- c("firedate","lastupdate","acq_date","acqdate","date","startdate","start_date")

hit <- intersect(wanted, cand_names)
if (length(hit) == 0) {
  stop("No date-like column found. Available names: ",
       paste(names(ba_all), collapse = ", "))
}

date_col <- hit[1]  # prefer the first match (e.g., firedate)
raw <- ba_all[[date_col]]

# Parse to Date
if (inherits(raw, "Date")) {
  ba_date <- raw
} else if (inherits(raw, "POSIXt")) {
  ba_date <- as.Date(raw)
} else {
  s <- as.character(raw)
  s <- substr(s, 1, 19)         # trim long timestamps if present
  # try multiple common formats
  ba_date <- suppressWarnings(lubridate::parse_date_time(
    s,
    orders = c("Ymd","Y-m-d","dmy","d-m-Y","m/d/Y","d/m/Y","Ymd HMS","Y-m-d H:M:S")
  ))
  ba_date <- as.Date(ba_date)
}

# if many NAs and we have a backup column (e.g., lastupdate), try it
if (sum(is.na(ba_date)) > 0 && "lastupdate" %in% cand_names && date_col != "lastupdate") {
  raw2 <- ba_all[["lastupdate"]]
  s2 <- as.character(raw2); s2 <- substr(s2, 1, 19)
  ba_date2 <- suppressWarnings(lubridate::parse_date_time(
    s2,
    orders = c("Ymd","Y-m-d","dmy","d-m-Y","m/d/Y","d/m/Y","Ymd HMS","Y-m-d H:M:S")
  ))
  ba_date2 <- as.Date(ba_date2)
  ba_date[is.na(ba_date)] <- ba_date2[is.na(ba_date)]
}

if (all(is.na(ba_date))) {
  stop("Failed to parse dates from ", date_col, " (and backup if tried).")
}

ba_all <- ba_all |> dplyr::mutate(ba_date = ba_date)


# Harmonise date
ba_all <- ba_all |>
  mutate(ba_date = ymd(str_sub(as.character(.data[[date_col]]), 1, 10))) |>
  filter(!is.na(ba_date))

# ---- Filter Summer 2025 ----
summer_start <- ymd("2025-06-01"); summer_end <- ymd("2025-08-31")
ba_2025 <- ba_all |> filter(ba_date >= summer_start, ba_date <= summer_end)

# Project + clip to EU
ba_2025 <- ba_2025 |> st_make_valid() |> st_transform(3035)
ba_2025_eu <- suppressWarnings(st_intersection(ba_2025, st_union(eu_poly)))

# Compute area (ha)
area_col <- names(ba_2025_eu)[stringr::str_detect(names(ba_2025_eu), "area.*ha|ba_ha")]
if (length(area_col)) {
  ba_2025_eu <- ba_2025_eu |> mutate(area_ha = as.numeric(.data[[area_col[1]]]))
} else {
  ba_2025_eu <- ba_2025_eu |> mutate(area_ha = as.numeric(st_area(geometry)) / 10000)
}

# Attach country via centroid-in-polygon
cent <- st_point_on_surface(ba_2025_eu)
country_join <- st_join(st_as_sf(cent), eu_poly, join = st_within, left = TRUE) |>
  st_drop_geometry() |>
  select(iso_a2, name_long)

ba_2025_eu <- bind_cols(ba_2025_eu, country_join)

message(sprintf("Summer 2025: %d scars; total burned %.1f k ha",
                nrow(ba_2025_eu), sum(ba_2025_eu$area_ha, na.rm=TRUE)/1000))

# ---- Viz: Hero, Facets, Top-10 ----
theme_map <- theme_minimal(base_size = 11) +
  theme(panel.grid = element_blank(), axis.text = element_blank(), axis.title = element_blank())

p_base <- ggplot() +
  geom_sf(data = eu_poly, fill = "grey95", color = "grey70", linewidth = 0.15)

hero <- p_base +
  geom_sf(data = ba_2025_eu, aes(geometry = geometry), fill = "red", color = NA, alpha = 0.25) +
  labs(
    title = "Europe — Burn-scar perimeters (Jun–Aug 2025)",
    subtitle = "EFFIS rapid perimeters (≥ ~30–50 ha), local data",
    caption = "Perimeters: EFFIS (local shapefile)."
  ) + theme_map

ba_2025_eu <- ba_2025_eu |> mutate(month = factor(month(ba_date, label = TRUE, abbr = TRUE),
                                                  levels = c("Jun","Jul","Aug")))
facet <- p_base +
  geom_sf(data = ba_2025_eu, fill = "red", color = NA, alpha = 0.25) +
  facet_wrap(~ month, ncol = 3) +
  labs(title = "Monthly burn-scar perimeters — Summer 2025",
       caption = "Perimeters: EFFIS (local shapefile).") +
  theme_map

ctry_2025 <- ba_2025_eu |>
  st_drop_geometry() |>
  group_by(name_long) |>
  summarise(burned_ha = sum(area_ha, na.rm = TRUE), n_fires = dplyr::n()) |>
  arrange(desc(burned_ha)) |>
  slice_head(n = 10) |>
  mutate(name_long = fct_reorder(name_long, burned_ha))

bars <- ggplot(ctry_2025, aes(x = burned_ha, y = name_long)) +
  geom_col() +
  scale_x_continuous(labels = label_number(scale_cut = cut_si("ha"))) +
  labs(
    title = "Top-10 countries — total burned area (Jun–Aug 2025)",
    x = "Burned area (ha)", y = NULL,
    caption = "Area = polygon area (ha) from EFFIS perimeters."
  ) +
  theme_minimal(base_size = 11)

# ---- Multi-year comparison (2017, 2022, 2023, 2025) using the same local layer ----
get_burnt_summer_from_local <- function(y, eu_poly, ba_all){
  out <- ba_all |>
    filter(ba_date >= as.Date(paste0(y,"-06-01")), ba_date <= as.Date(paste0(y,"-08-31"))) |>
    st_make_valid() |> st_transform(3035) |>
    st_intersection(st_union(eu_poly))
  ac <- names(out)[str_detect(names(out), "area.*ha|ba_ha")]
  out <- if (length(ac)) mutate(out, area_ha = as.numeric(.data[[ac[1]]])) else
    mutate(out, area_ha = as.numeric(st_area(geometry))/10000)

  cent <- st_point_on_surface(out)
  j <- st_join(st_as_sf(cent), eu_poly, join = st_within, left = TRUE) |>
    st_drop_geometry() |> select(iso_a2, name_long)
  out <- bind_cols(out, j) |> mutate(year = y)
  out
}

yrs <- c(2017, 2022, 2023, 2025)
multi <- dplyr::bind_rows(lapply(yrs, get_burnt_summer_from_local, eu_poly = eu_poly, ba_all = ba_all))

ctry_multi <- multi |>
  st_drop_geometry() |>
  group_by(name_long, year) |>
  summarise(burned_ha = sum(area_ha, na.rm = TRUE), .groups = "drop")

# Dumbbell 2025 vs 2017
dd <- ctry_multi |>
  filter(year %in% c(2017, 2025)) |>
  tidyr::pivot_wider(names_from = year, values_from = burned_ha, values_fill = 0) |>
  mutate(delta = `2025` - `2017`) |>
  arrange(desc(`2025`)) |>
  slice_head(n = 20) |>
  mutate(name_long = fct_reorder(name_long, `2025`))

p_dumbbell_25_17 <- ggplot(dd) +
  geom_segment(aes(x = `2017`, xend = `2025`, y = name_long, yend = name_long),
               linewidth = 0.6, alpha = 0.5) +
  geom_point(aes(x = `2017`, y = name_long), size = 2) +
  geom_point(aes(x = `2025`, y = name_long), size = 2) +
  scale_x_continuous(labels = label_number(scale_cut = cut_si("ha"))) +
  labs(
    title = "Burned area — Summer 2025 vs 2017 (Top 20 countries)",
    x = "Burned area (ha)", y = NULL,
    caption = "EFFIS perimeters (local). Small fires <~30–50 ha under-represented."
  ) +
  theme_minimal(base_size = 11)


# Small-multiple bars for years, using Top-10 by 2025
topN <- ctry_multi |>
  filter(year == 2025) |>
  arrange(desc(burned_ha)) |>
  slice_head(n = 10) |>
  pull(name_long)

p_bars_multi <- ctry_multi |>
  filter(name_long %in% topN) |>
  mutate(name_long = forcats::fct_relevel(name_long, !!!topN)) |>
  ggplot(aes(y = name_long, x = burned_ha, fill = factor(year))) +
  geom_col(position = "dodge") +
  scale_x_continuous(labels = label_number(scale_cut = cut_si("ha"))) +
  labs(
    title = "Top-10 (by 2025) — Summer burned area across years",
    x = "Burned area (ha)", y = NULL, fill = "Year"
  ) +
  theme_minimal(base_size = 11)

# ---- Optional: Severity 2018–2024 trends (uses local GeoTIFFs) ----
if (dir.exists(sev_dir)) {
  if (!requireNamespace("terra", quietly = TRUE)) install.packages("terra")
  library(terra)
  sev_files <- list.files(sev_dir, pattern="severity_\\d{4}\\.tiff$", full.names=TRUE)
  if (length(sev_files)) {
    eu_bbox <- st_bbox(eu_poly); eu_ext <- terra::ext(eu_bbox["xmin"], eu_bbox["xmax"], eu_bbox["ymin"], eu_bbox["ymax"])
    sev_stack <- lapply(sev_files, function(fp){
      yr <- stringr::str_extract(basename(fp), "\\d{4}")
      r <- terra::rast(fp) |> terra::project("EPSG:3035") |> terra::crop(eu_ext)
      data.frame(year = yr, value = terra::values(r))
    })
    sev_df <- dplyr::bind_rows(sev_stack) |>
      dplyr::filter(!is.na(value)) |>
      dplyr::mutate(class = factor(value, levels=c(1,2,3), labels=c("Low","Moderate","High")))

    sev_summary <- sev_df |>
      dplyr::group_by(year, class) |>
      dplyr::summarise(pixels = dplyr::n(), .groups="drop") |>
      dplyr::group_by(year) |>
      dplyr::mutate(share = pixels/sum(pixels))

    p_sev <- ggplot(sev_summary, aes(x=year, y=share, fill=class)) +
      geom_col() +
      scale_y_continuous(labels=scales::percent) +
      labs(title="Fire severity distribution in Europe (local rasters)",
           x=NULL, y="Share of burned pixels", fill="Severity",
           caption = "Severity classes assumed: 1=Low, 2=Moderate, 3=High") +
      theme_minimal(base_size=12)
  }
}

# ---- Optional cross-check: country totals 2023 (local XLSX) ----
if (file.exists(ctry_tot_2023)) {
  if (!requireNamespace("ggrepel", quietly = TRUE)) install.packages("ggrepel")
  library(ggrepel)
  ct2023 <- tryCatch({
    readxl::read_xlsx(ctry_tot_2023) |> janitor::clean_names()
  }, error = function(e) NULL)

  if (!is.null(ct2023)) {
    cand_cntry <- names(ct2023)[str_detect(names(ct2023), "country|name")]
    cand_ba    <- names(ct2023)[str_detect(names(ct2023), "burn|area|ha")]
    if (length(cand_cntry) && length(cand_ba)) {
      ct2023_small <- ct2023 |>
        rename(country = all_of(cand_cntry[1]), burned_ha_official = all_of(cand_ba[1])) |>
        mutate(country = as.character(country))

      poly2023 <- ctry_multi |>
        filter(year == 2023) |>
        select(name_long, burned_ha) |>
        mutate(country = name_long)

      crosscheck_2023 <- poly2023 |>
        left_join(ct2023_small, by = "country") |>
        mutate(diff = burned_ha - burned_ha_official)

      p_cc <- ggplot(crosscheck_2023, aes(burned_ha_official, burned_ha, label = country)) +
        geom_abline(linetype = 2) +
        geom_point() +
        ggrepel::geom_text_repel(size = 2.7) +
        scale_x_continuous(labels = label_number_si()) +
        scale_y_continuous(labels = label_number_si()) +
        labs(title = "Polygon sums vs. official 2023 country totals",
             x = "Official burned area (ha, 2023 XLSX)", y = "Polygon-based burned area (ha)",
             caption = "Expect differences due to thresholds, timing, and mapping criteria.") +
        theme_minimal(base_size = 11)
    }
  }
}

# End of script
