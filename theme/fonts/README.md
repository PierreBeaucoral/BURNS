# Local fonts (offline-safe)

The theme references these files; add them here once and the site renders with
no network dependency. Both families are open source (SIL OFL 1.1).

Expected files (from the official IBM Plex distribution, e.g.
https://github.com/IBM/plex or Google Fonts export):

    IBMPlexSans-Regular.woff2
    IBMPlexSans-Medium.woff2
    IBMPlexSans-SemiBold.woff2
    IBMPlexSans-Bold.woff2
    IBMPlexMono-Regular.woff2
    IBMPlexMono-Medium.woff2

Until they are present, `theme/_burns-fonts.scss` falls back to the system
sans/mono stack, so nothing breaks. This directory is intentionally the only
place fonts are fetched; `quarto render` never reaches the network.
