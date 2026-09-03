# Session Report — BURNS (Europe Wildfire Season Tracker)

## 2026-07-02/03 — Project overhaul: 2026 follow-up + season-tracker infrastructure

**Operations:**
- Initialized git repo (`main`); `.gitignore` for snapshots/renders/gifs
- `R/` helper library extracted from `wildfires-europe-2025-local.qmd` (helpers.R, geo.R, flags.R, cache.R, theme.R) — flag machinery deduplicated (was 3× copy-paste), year-parameterized `filter_summer()`, single `tag_countries()`
- Quarto website scaffold: `_quarto.yml`, `index.qmd` (tracker placeholder), `about.qmd`, `README.md`, `.github/workflows/render.yml` (weekly Jun–Sep cron + Pages deploy, inactive until pushed)
- `scripts/fetch_effis.R` + `scripts/latest_snapshot.R`: paged WFS download (maxFeatures=1000 + startindex + sortby=id), resultType=hits pre-count, retries, per-year GeoJSON snapshots, MANIFEST.md
- Snapshot `DATA/snapshots/2026-07-03/`: years 2016–2026 (~440 MB; 2020 refetched after one corrupt server page)

**Decisions:**
- Workers = Sonnet agents, critics = Opus agents, Fable orchestrates (user directive, saved to memory)
- Envelope baseline is 2017–2025, NOT 2008–2025 — WFS archive starts 2016 (verified: 2010/2012/2014 = 0 features)
- Cross-year claims use burned AREA of large fires, not counts — MODIS→Sentinel-2 shift doubles counts 2023→2024 (9.4k → 20.2k detection-threshold artifact)
- Country tagging stays max-geometric-overlap (EFFIS COUNTRY attribute kept as cross-check only)
- Phase 2 reframed (user, 2026-07-03): season just started → 2026 page is a polished *state-of-the-season* visual landscape, not a retrospective
- No git push / GitHub deploy without explicit user confirmation

**Results:**
- coder-critic (Opus) on R/ helpers: 85/100 PASS; blocking NBSP fix + 3 hardening items applied and verified
- Website scaffold renders data-free (agent self-score 92; formal critic review pending with Phase 3 leaflet work)
- EFFIS endpoint verified live: uncapped queries hang; capped+paged work; documented in script header + manifest

**Commits:**
- `6588a72` Phase 1a: R/ helper library
- `a6f717d` Phase 1c + 3 scaffold: website, GH Action, fetch pipeline
- (pending) data snapshot manifest + 2020 completion

**Status:**
- Done: Phase 1a (helpers, critic-passed), 1b (endpoint research), 1c (fetch pipeline + snapshot), website scaffold
- Pending: Phase 2 — parameterized 2026 state-of-the-season page (envelope chart, normalized rankings, recurrence analysis, 2026-vs-2025) with emphasis on visual quality; Phase 3 remainder — leaflet interactive map, critic review of scaffold; final render + quality gate; user decision on GitHub publish

## 2026-07-03 (evening) — Phase 2/2b/3 complete: season page, new viz, quality gate

**Operations:**
- posts/2026.qmd built (envelope, hero map, leaflet, countries+flags, re-burn, land cover) then extended with gallery of scars, Natura 2000 analysis, calendar heatmap
- index.qmd upgraded to live tracker (3 headline numbers + shared envelope)
- Writer polish pass (winter-fires narrative thread, connective flow, Aude line)
- Both Opus critics ran; all blockers fixed; 2 residual one-liners applied by orchestrator
- Deploy model reworked: CI render deleted, scripts/update_site.sh local flow

**Decisions:**
- Local-render-and-publish over CI rendering (EFFIS server too flaky for CI; data 550 MB; rnaturalearthhires off-CRAN) — critic-recommended, experience-confirmed
- ALL cache keys snapshot-aware (stale-weekly-data trap closed)

**Results:**
- writer-critic (Opus): 91/100 PASS; winter-surge figure independently verified real (180,638 ha, 6,620 perimeters, no artifact)
- coder-critic (Opus): 74 FAIL round 1 → 92/100 PASS round 2; all four headline numbers logic-verified
- Headline findings: summer-to-date at 201% of median; 181k ha burned Jan-May (peak week 23 Feb); re-burn 42.7% (France 67% re-burn vs Iberia mostly new ground); Natura 2000 share 24% vs 32% median
- 4 real bugs caught by verify loops: GEOMETRYCOLLECTION-EMPTY silent drop, %V strptime silent failure, summarise() sequencing, NBSP regex

**Commits:**
- `ed50fa5` Phase 2 season page; `21ebec3` Phase 2b viz; `08b6c11` writer polish; `74f48fb` critic fixes; (pending) residual one-liners

**Status:**
- Done: full pipeline, website, 2026 page, quality gate passed (aggregate ~91-92)
- Pending: user decision on GitHub publish (gh repo + quarto publish gh-pages); September retrospective ideas in quality_reports/viz_ideas_2026.md

## 2026-08-20 19:10 — Weekly update: 2026-08-20 snapshot (data through 20 Aug)

**Operations:**
- Fetched `DATA/snapshots/2026-08-20/` (11/11 years OK). Settled years 2016-2025 hardlinked
  from the 2026-07-27 snapshot, so only the live 2026 layer downloaded (~85 MB, no disk cost
  for the archive). `fetch_effis.R` skips existing files but still re-validates them.
- Rebuilt `assets/anim/2026-race.gif` (119 frames) via `scripts/build_race_anim.R 2026`.
  Note: `update_site.sh` does NOT rebuild the animation; it must be run separately.
- Revised the data-driven prose in `posts/2026.qmd` against recomputed numbers.
- `scripts/update_site.sh --no-fetch`: completeness gate PASS, `quarto render` clean.

**Decisions:**
- Kept the hardlink-and-fetch-current-year pattern of the previous five weekly updates
  (faster, and the volume is at 99% capacity) rather than refetching the full archive.
- Did not hardcode the new re-burn percentages into prose; kept the claim qualitative to
  avoid re-creating the weekly staleness problem that this update had to fix.
- Did not publish. Publishing remains a separate explicit user action.

**Results:**
- 2026 layer grew 12,602 -> 15,220 features; Europe-clipped season total (1 Jun -> 20 Aug)
  589,216 ha across 2,771 fires, 189% of the 2017-2025 median (was 373.6% on 26 Jul).
- Season ranking flipped: 2026 is 2nd of 10 at this date behind **2025** (954,710 ha),
  no longer "behind only 2022". Post's headline verdict rewritten accordingly.
- 2026 did not slow down: ~10,000 ha/day since 26 Jul vs ~6,200 ha/day before. The ratio
  fell only because the median season does its own heavy burning in August. Prose now makes
  this distinction explicitly so the softer ratio does not read as good news.
- Largest fire of 2026 changed: Niebla, Huelva (43,772 ha, 6 Aug) overtook Navaluenga
  (42,458 ha, 22 Jul). Added the August/Andalusia + Aragón surge to the Spain section.
- 22 July animation figures all revised by EFFIS (42,458 / 37,162 / 87,327 ha step / 612%).
  "That single day is most of the gap" was false (now 32%); rewritten.
- Re-burn claim re-verified and holds: Spain 7.7% re-burn vs France 24.5%, Portugal 29.3%,
  Italy 29.3%; Europe-wide 20.3%.

**LEARN entries:**
- [LEARN:gotcha] Selecting a fire by EFFIS `commune` name is unstable across snapshots.
  The 2026-07-23 Madrid fire was mapped under "San Martín de Valdeiglesias" on 26 Jul and
  under "Navas del Rey" on 20 Aug. The commune-name filter silently fell through to an
  unrelated 35 ha fire, and `round(35, -3)` would have published "added about 0 hectares".
  Impact: a silent, plausible-looking wrong number in published prose.
  Apply: select named fires by `province` (stable) plus date/rank, never by commune string.
  Fixed in the `france-spain-numbers` chunk with an explanatory comment.
- [LEARN:workflow] The weekly update is four steps, not two: fetch -> rebuild race animation
  -> revise the hardcoded prose in posts/2026.qmd -> render. `update_site.sh` covers only
  fetch and render; the animation and the prose are manual and easy to forget.

**Commits:**
- (pending user decision) prose revision + rebuilt animation

**Status:**
- Done: snapshot, animation, prose revision, render, output verified against rendered HTML
- Pending: user decision on `git commit` and `quarto publish gh-pages --no-prompt`
- Watch: volume is at ~99% capacity. Old snapshots (2026-07-03 alone is ~523 MB of
  non-shared files) and 861 MB of `DATA/cache/rds` are the reclaimable candidates, but
  snapshots are the project's reproducibility record so deletion is a user decision.

## 2026-08-21 09:55 — Published the 20 Aug build + fixed the og-image publish regression

**Operations:**
- `quarto publish gh-pages --no-prompt` timed out at 10 min: it RE-RENDERS by default and never
  reached the push. Re-ran as `quarto publish gh-pages --no-render --no-prompt` (the `_site/` from
  2026-08-20 was already verified), which published in seconds.
- Restored `assets/og-image.png` into `_site/assets/` and republished.
- Added a `resources:` key to `_quarto.yml` so the og-image is copied on every render.
- Removed strays left by the timed-out publish: `posts/2026.rmarkdown`, root `site_libs/`.

**Decisions:**
- Published only after explicit user approval (standing rule honoured).
- Fixed the og-image at the source (project `resources:`) rather than hand-restoring it, which is
  what happened on 2026-08-10 and would have recurred every week.

**Results:**
- Live site now at `881ccd9`, "as of 20 August 2026" on index and season page.
- All 14 figures changed vs the 10 Aug build and are confirmed live (envelope-1.png 84,884 ->
  128,557 bytes, verified by curl against the public URL).
- Reader-reported "figures still 10 Aug" was browser caching, not a stale publish: Quarto gives
  figures stable filenames, so a returning browser reuses cached PNGs while re-fetching the HTML.
  GitHub Pages sends `cache-control: max-age=600`, so it self-clears in 10 minutes; Cmd+Shift+R
  is the immediate fix.

**LEARN entries:**
- [LEARN:gotcha] `quarto publish gh-pages` re-renders by default. With this project's render cost
  that exceeds a 10-minute command budget and the push never happens, leaving `posts/*.rmarkdown`
  and a root `site_libs/` behind. Apply: when `_site/` is already rendered and verified, always
  publish with `--no-render`.
- [LEARN:gotcha] Quarto copies `favicon:` automatically but NOT the `open-graph`/`twitter-card`
  `image:`, because nothing links to it from page content, so a clean publish drops it. Apply:
  keep `assets/og-image.png` listed under project `resources:` (done 2026-08-21).
- [LEARN:gotcha] Check `origin/gh-pages`, not the local `gh-pages` ref, when asking what is live.
  The local ref was 3 weeks stale and led to a wrong "the live site says 26 July" claim.

**Commits:**
- gh-pages: `34825d5` then `881ccd9` (site builds; main still uncommitted)

**Status:**
- Done: live site updated to the 20 Aug snapshot and verified over HTTP
- Pending: `main` still has uncommitted work (`posts/2026.qmd`, `_quarto.yml`, rebuilt GIF,
  `SESSION_REPORT.md`) awaiting a weekly-update commit

## 2026-08-25 16:20 — Weekly update: 2026-08-25 snapshot (data through 24 Aug)

**Operations:**
- Checked the live site first (per user request): `origin/gh-pages` at `881ccd9`, "as of
  20 August 2026", og-image present. Live build was 5 days stale.
- Fetched `DATA/snapshots/2026-08-25/` (11/11 years OK), settled years hardlinked from 08-20.
- Recomputed prose facts; rebuilt `assets/anim/2026-race.gif` (123 frames); revised
  `posts/2026.qmd`; `update_site.sh --no-fetch` rendered clean.
- Verified against rendered HTML: index 619 kha / 2,997 / 189%, both pages "as of 24 August".

**Decisions:**
- Did NOT write "the season is ending" despite the pace collapse, because most of the recent
  drop is EFFIS mapping lag (see Results). Added a callout quantifying the backfill instead.
- Left the envelope verdict ("second only to 2025", 1.9x median) unchanged: recomputation
  confirmed it still holds, so no edit was warranted.
- Disk pressure resolved externally: 118 GB free now (was 3.8 GB), so no cache/snapshot pruning.

**Results:**
- Season (1 Jun -> 24 Aug): 619,299 ha / 2,997 fires / 189.1% of median. Rank 2 of 10,
  still behind only 2025 (962,815 ha). Season age 12.0 weeks.
- Pace fell: ~9,680 ha/day (26 Jul -> 24 Aug) -> 6,188 ha/day (last 14 d) -> 2,907 (last 7 d).
- **Backfill quantified:** the same calendar window (1 Jun - 20 Aug) read 589,216 ha in the
  08-20 snapshot and 614,226 ha in the 08-25 snapshot: +25,010 ha (+4.2%) added retroactively.
  This is why the recent-days slowdown must not be read as the season ending.
- Balkans surge while Iberia flattened: Bosnia 26,256 -> 35,361 ha (now 5th in Europe),
  Serbia 13,558 -> 21,143, N. Macedonia +2,839, Albania +2,015. A backfilled 13,920 ha fire
  at Kovin, Serbia (21 Jul) entered the top ten.
- The `_quarto.yml` `resources:` fix from 21 Aug worked: og-image.png was copied into
  `_site/assets/` automatically, with no manual restore step.

**LEARN entries:**
- [LEARN:technical] EFFIS backfills earlier dates between snapshots (+4.2% for the same
  1 Jun-20 Aug window in 5 days). Any "the pace is slowing" claim computed from the last
  7-14 days is biased downward. Apply: before writing a slowdown narrative, diff the OLD
  snapshot's envelope cache against the NEW one at the SAME date; quote that delta as the
  uncertainty. Cached envelopes make this a two-line check.
- [LEARN:gotcha] The scratchpad directory is wiped between sessions, so helper scripts written
  there (numbers.R/verify.R) must be recreated each week. `nohup Rscript <missing file>` fails
  instantly and the monitor then waits forever on a DONE marker that never comes.
- [LEARN:gotcha] fetch_effis.R prints "Done: 11/11 years OK" (lowercase "years"); a monitor
  grepping case-sensitively for "Years OK" never matches and times out.

**Commits:**
- (pending) still uncommitted on main: posts/2026.qmd, _quarto.yml, assets/anim/2026-race.gif,
  SESSION_REPORT.md (covers BOTH the 20 Aug and 25 Aug updates)

**Status:**
- Done: snapshot, animation, prose, render, verification
- Pending: user decision on commit and on `quarto publish gh-pages --no-render --no-prompt`

## 2026-09-03 14:45 — Weekly update: 2026-09-03 snapshot (data through 2 Sep)

**Operations:**
- Live site check: `origin/gh-pages` at `153292e` (25 Aug build). Main clean at `bcd9704`.
- Fetched `DATA/snapshots/2026-09-03/` (11/11 years OK; 2016-2025 hardlinked from 08-25,
  only 2026 downloaded: 16,455 features, 99 MB, last perimeter dated 2 Sep).
- Recomputed prose facts (scratchpad numbers.R); rebuilt `assets/anim/2026-race.gif`
  (132 frames, 1.2 MB); 12 exact-match prose edits in `posts/2026.qmd`;
  `update_site.sh --no-fetch` rendered clean (exit 0, no leftover .rmarkdown/site_libs).
- Verified rendered HTML: both pages "as of 2 September 2026"; index 3,419 fires / 184%;
  post carries 669,000 ha, thirteen weeks, 647,000 backfill figure, Italy +15,000.

**Decisions:**
- Envelope verdict unchanged ("second only to 2025"): rank 2 of 10 confirmed (2025 983 kha
  at this date, 2017 655 kha, 2026 669 kha).
- Replaced the 25 Aug "Balkans surge" paragraph with this week's movers (Italy +15,167 ha,
  Montenegro +10,176, Bosnia +6,767, N. Macedonia +3,863, Serbia +3,478); Iberia flat
  (Spain +1,371, Portugal +1,163). "Centre of gravity moving east and south".
- Kept the backfill callout and refreshed it rather than writing "season over": pace is
  2,141 ha/day (last 7 d), 3,235 (14 d), 8,208 since 26 Jul, but the 1 Jun-24 Aug window
  grew from 619,299 to 646,743 ha between snapshots (+27,444, +4.4%).
- Softened the 22 July claim from "about a third of the gap" to "less than a third" (29%).
- 22 Jul / 6 Aug / Huelva / Huesca figures re-checked, all still match; no edit.

**Results:**
- Season (1 Jun -> 2 Sep): 668,635 ha / 3,419 fires / 183.6% of median (364,106 ha).
  Full-year 2026: 849,291 ha / 10,037 perimeters. Season age 13.3 weeks.
- Late-August fires were Italian and Balkan: Gravina in Puglia 3,455 ha (25 Aug), Saraj MK
  1,212, Mongiuffi Melia (Messina) 1,164, Ciminna (Palermo) 921, Craco (Matera) 845.

**Commits:**
- (pending) uncommitted on main: posts/2026.qmd, assets/anim/2026-race.gif, SESSION_REPORT.md

**Status:**
- Done: snapshot, animation, prose, render, HTML verification
- Pending: user decision on commit and on `quarto publish gh-pages --no-render --no-prompt`
