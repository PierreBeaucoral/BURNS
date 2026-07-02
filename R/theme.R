# ==============================================================================
# theme.R
# Shared land-cover color palette and ggplot theme used across the wildfire
# figures. Exception to the no-library() convention: this file may use
# ggplot2:: namespaced calls throughout (per project rule).
# Required packages: ggplot2
# ==============================================================================

#' Color-blind-safe, semantically meaningful palette for EFFIS land-cover
#' composition classes (broad-leaved, conifer, mixed, sclerophyllous, etc.)
pal_lc <- c(
  "Broad-leaved forest"         = "#2E7D32",  # deep leaf green
  "Coniferous forest"           = "#00512D",  # dark pine
  "Mixed forest"                = "#4CAF50",  # mid forest green
  "Sclerophyllous veg."         = "#E64A19",  # hot Mediterranean orange
  "Transitional woodland-shrub" = "#8C6D31",  # olive/brown scrub
  "Agricultural areas"          = "#DDAA33",  # golden fields
  "Artificial surfaces"         = "#6E6E6E",  # urban grey
  "Other natural LC"            = "#3E8EC4",  # light blue (natural/open)
  "Other LC"                    = "#9B59B6"   # lavender (misc/unknown)
)

#' Shared minimal theme matching the recurring theme() settings across the
#' wildfire figures (blank grid on maps, grey caption/subtitle text, etc.)
#' @param base_size base font size, passed to theme_minimal()
#' @param map logical; if TRUE, also blank panel grid + axis text/title (for
#'   geom_sf maps); if FALSE, keep axis text and only blank minor gridlines
#' @return a ggplot2 theme object
theme_burns <- function(base_size = 12, map = FALSE) {
  base <- ggplot2::theme_minimal(base_size = base_size) +
    ggplot2::theme(
      plot.subtitle = ggplot2::element_text(colour = "grey25"),
      plot.caption  = ggplot2::element_text(colour = "grey30")
    )

  if (map) {
    return(
      base + ggplot2::theme(
        panel.grid = ggplot2::element_blank(),
        axis.text  = ggplot2::element_blank(),
        axis.title = ggplot2::element_blank()
      )
    )
  }

  base + ggplot2::theme(
    panel.grid.minor   = ggplot2::element_blank(),
    panel.grid.major.y = ggplot2::element_blank()
  )
}
