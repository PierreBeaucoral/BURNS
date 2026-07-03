# EFFIS fetch manifest

- **Fetched:** 2026-07-03 11:09:15 WEST
- **Years requested:** 2016-2026 (11 total)
- **Years OK:** 11, **Years failed:** 0 (2020 completed 13:44 via fallback fetch)
- **Source URL pattern:** `https://maps.effis.emergency.copernicus.eu/effis?service=WFS&version=1.1.0&request=GetFeature&typename=ms:modis.ba.poly&outputformat=geojson&maxFeatures=1000&startindex=<K>&sortby=id&filter=<OGC-Filter-XML-on-FIREDATE>` (paged; expected count via `resultType=hits`)

## Per-year summary

| Year | Hits | Features | File size | Min FIREDATE | Max FIREDATE | Sum AREA_HA | Status |
|---|---|---|---|---|---|---|---|
| 2016 | -- | 1,331 | 2.2 MB | 2016-02-07 | 2016-12-31 | 542,412 | OK |
| 2017 | 3,114 | 3,114 | 29.7 MB | 2017-01-07 | 2017-12-30 | 1,376,079 | OK |
| 2018 | 1,212 | 1,212 | 12.5 MB | 2018-01-02 | 2018-12-31 | 204,850 | OK |
| 2019 | 3,864 | 3,864 | 49.4 MB | 2019-01-01 | 2019-12-31 | 789,704 | OK |
| 2020 | 6,773 | 6,773 | 112 MB | 2020-01-01 | 2020-12-28 | 1,114,415 | OK (fallback: half-year windows × 500-feature pages after repeated server failures on 1000-feature pages; merged count matches hits exactly) |
| 2021 | 7,317 | 7,317 | 21.2 MB | 2021-01-04 10:02:12 | 2021-12-31 22:05:00 | 1,114,115 | OK |
| 2022 | 13,157 | 13,157 | 45.0 MB | 2022-01-01 | 2022-12-31 10:45:00 | 1,401,028 | OK |
| 2023 | 9,372 | 9,372 | 33.0 MB | 2023-01-01 | 2023-12-31 12:31:00 | 908,242 | OK |
| 2024 | 20,160 | 20,160 | 66.1 MB | 2024-01-02 11:04:00 | 2024-12-31 12:46:00 | 1,871,119 | OK |
| 2025 | 23,188 | 23,188 | 110.4 MB | 2025-01-01 00:09:00 | 2025-12-31 14:12:00 | 2,242,731 | OK |
| 2026 | 10,344 | 10,346 | 41.6 MB | 2026-01-01 | 2026-07-03 00:28:00 | 423,710 | OK |

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

