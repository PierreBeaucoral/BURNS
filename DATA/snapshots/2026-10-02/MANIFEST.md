# EFFIS fetch manifest

- **Fetched:** 2026-10-02 13:50:20 CEST
- **Years requested:** 2026-2026 (1 total)
- **Years OK:** 1, **Years failed:** 0
- **Source URL pattern:** `https://maps.effis.emergency.copernicus.eu/effis?service=WFS&version=1.1.0&request=GetFeature&typename=ms:modis.ba.poly&outputformat=geojson&maxFeatures=1000&startindex=<K>&sortby=id&filter=<OGC-Filter-XML-on-FIREDATE>` (paged; expected count via `resultType=hits`)

## Per-year summary

| Year | Hits | Features | File size | Min FIREDATE | Max FIREDATE | Sum AREA_HA | Status |
|---|---|---|---|---|---|---|---|
| 2026 | 18,634 | 18,635 | 128.4 MB | 2025-12-31 23:00:00 | 2026-10-01 10:17:00 | 1,929,781 | OK |

## Schema notes

- Layer: `ms:modis.ba.poly` (WFS GetFeature, GeoJSON output, paged with
  `maxFeatures`/`startindex`/`sortby=id`; uncapped requests hang server-side).
- Properties: `id`, `FIREDATE`, `FINALDATE`, `LASTUPDATE`, `COUNTRY` (ISO2, incl.
  non-EU e.g. DZ/UA), `PROVINCE`, `COMMUNE`, `AREA_HA`, `BROADLEA`, `CONIFER`,
  `MIXED`, `SCLEROPH`, `TRANSIT`, `OTHERNATLC`, `AGRIAREAS`, `ARTIFSURF`,
  `OTHERLC`, `PERCNA2K`, `CLASS`.
- `COUNTRY` is EFFIS's own attribute and is kept as a cross-check only; this
  pipeline's authoritative country tag is computed downstream by maximum
  geometric overlap with reference polygons (see `R/geo.R::tag_countries()`),
  not by trusting `COUNTRY` directly.

## Coverage & comparability caveats

- **Archive starts in 2016.** Verified via `resultType=hits`: 2010/2012/2014
  return 0 features in this layer; 2016 is the first year with data (1,331
  features). Pre-2016 seasons are simply absent from `modis.ba.poly` and are
  not fetched.
- Perimeters are EFFIS *rapid* burnt-area estimates from satellite mapping,
  typically covering fires of roughly >= 30-50 ha; smaller fires are
  systematically under-represented.
- **MODIS -> Sentinel-2 transition.** The layer is still named
  `modis.ba.poly` (as of 2026-07) for historical reasons, but EFFIS moved its
  rapid mapping to Sentinel-2-based detection. The jump from ~9.4k features
  (2023) to ~20k (2024) reflects this detection-threshold shift -- smaller
  fires became detectable -- not a doubling of fire activity. Cross-year
  comparisons of feature COUNTS are therefore not apples-to-apples;
  comparisons of burned AREA of large fires are safer.
- Feature counts are checked against the server's `resultType=hits` count;
  a >2% divergence is flagged in the table above (the live current-season
  layer legitimately changes between requests).

