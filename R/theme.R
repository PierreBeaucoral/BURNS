# ==============================================================================
# theme.R
# Shared ggplot theme used across the wildfire figures. The land-cover palette
# pal_lc and all brand colours now come from R/tokens.R (single source:
# theme/burns-tokens.yml), so figures and the HTML chrome share one palette.
# Exception to the no-library() convention: ggplot2:: namespaced calls
# throughout (per project rule).
# Required packages: ggplot2 (pal_lc/brand: see R/tokens.R -> yaml)
# ==============================================================================

# Load the shared tokens (defines pal_lc, burns_brand, burns_tokens). Guarded so
# re-sourcing theme.R after tokens.R is already loaded is a no-op.
if (!exists("burns_tokens")) source(file.path("R", "tokens.R"))

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
