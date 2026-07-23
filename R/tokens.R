# ==============================================================================
# tokens.R
# Single-source brand tokens for the whole project. Reads theme/burns-tokens.yml
# (the ONE place hex values are defined) and exposes them to R, so ggplot
# figures and the HTML/SCSS chrome cannot drift apart. theme/build-tokens.R
# regenerates the SCSS mirror of the same file at render time.
# Required packages: yaml
# ==============================================================================

#' Project brand tokens, read from the shared YAML source.
#' @return nested list: fonts, brand, light, dark, land_cover
burns_tokens <- local({
  path <- file.path("theme", "burns-tokens.yml")
  if (!file.exists(path)) {
    stop("burns-tokens.yml not found at ", path,
         " (run from project root; execute-dir: project handles this).")
  }
  yaml::read_yaml(path)
})

#' Named brand colours, flattened for convenient use in plots
#' (e.g. burns_brand$ember).
burns_brand <- burns_tokens$brand

#' Land-cover palette as a named character vector. Drop-in replacement for the
#' old literal in theme.R; still named pal_lc for backward compatibility.
pal_lc <- unlist(burns_tokens$land_cover)
