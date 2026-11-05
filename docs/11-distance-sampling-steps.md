# Distance sampling, step by step

*C. H. Ross. 2026-11-05. Distributed with the package source.*

## 1. Scope

The steps from a NARWC survey file to an abundance estimate, each with the
code that runs it. Every code block was run, in order, on the package fixture
(`inst/extdata/narwc-example.csv`). The numbers quoted are from that run.

For what each function does internally, see `docs/10-code-guide.md`.

| Section | Function | Package |
|---|---|---|
| 2. Read | `read_narwc()` | narwcr, re-exported |
| 3. Prepare | `prepare_survey()` | distsamp |
| 4. Check | `validate_narwc()`, `diagnose_pipeline()` | distsamp |
| 5. Segment | `segment_survey()` | distsamp |
| 6. Inspect | `segs$segments`, `segs$detections` | distsamp |
| 7. Detection table | `detection_data()` | distsamp |
| 8. Detection function | `ds()` | Distance |
| 9. Density surface inputs | `segments_as_sf()` | distsamp, sf |
| 10. Density surface | `dsm()` | dsm |
| 11. Abundance | `predict()`, `dsm_var_gam()` | dsm |

## 2. Read

```r
library(distsamp)
path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
dat  <- read_narwc(path)
```

Column names are standardised and the mapping is printed. Result: 113 records.

## 3. Prepare

```r
dat <- prepare_survey(dat, platform = "aerial")
```

In order: line occupations (`LEGNO3`), line state filled (`LEGSTAGE`),
platform filter by speed, effort flags (`OnOff.Effort`). Result: 101 of 113
records on effort.

The order is fixed. Filtering the platform before line occupations merges
occupations and counts the ferry between them as effort.

## 4. Check

```r
findings <- validate_narwc(dat)
diagnose_pipeline(dat, seg_length = 5)
```

`validate_narwc()` returns one row per rule broken (2 on the fixture).
`diagnose_pipeline()` reports, stage by stage, what each step kept and why.
Run both before trusting any number from a new extract
(`docs/08-onboarding-a-real-extract.md`).

## 5. Segment

```r
segs <- segment_survey(dat, seg_length = 5, seed = 1)
```

On-effort track is cut into segments of about 5 km. Steps of Section 3 that
have not run are run here, except the platform filter. Perpendicular distances
are attached to sightings. Circling sightings are added to the group they were
counted with. `seed` makes the cut reproducible.

Main options:

| Argument | Default | Effect |
|---|---|---|
| `seg_length` | required | target segment length, km |
| `seed` | `NULL` | reproducible segmentation |
| `species` | all | restrict sightings |
| `distance_units` | `"m"` | units of `distance` |
| `circling` | `"same_species"` | which circling sightings are kept |
| `circling_distance` | `"with_group"` | circled animals join their group; `"break_off"` makes them separate detections |
| `circling_max_gap_km` | `seg_length` | furthest a group may be from the break-off |

Result: 20 segments, 92.23 km of effort (all of it), 8 detections.

## 6. Inspect

```r
segs$segments      # one row per segment: seg_id, seg_eff (km), mid_lat, mid_lon
segs$detections    # one row per sighting: seg_id, size, distance, distance_source
table(segs$detections$distance_source)
```

`distance_source` names where each distance came from: `angle`, `exact`,
`strip`, or for circling sightings `circling`/`break_off`. On the fixture all
8 are `angle`.

## 7. Detection table

```r
flat <- detection_data(segs, area = 5811)
```

One row per detection, plus one row per segment with no detection, in the
shape `Distance` expects. `area` is the study area in km²; it has no default.
Circling detections are left out by default.

Exact distances give a `distance` column; `STRIP` bins give `distbegin` and
`distend`. Never both: `ds()` reads the bin columns as binned data.

## 8. Detection function

```r
library(Distance)
fit <- ds(flat, key = "hn", adjustment = NULL, truncation = "10%",
          convert_units = 0.001)
summary(fit)
```

`convert_units = 0.001` because distances are in m and effort in km. Leaving
it out scales abundance by 1000.

Result: half-normal, average detection probability 0.772, 7 detections after
truncation. Abundance from the design-based estimate: 936.6 in 5,811 km².

This assumes detection on the line is certain, `g(0) = 1`. For aerial whale
surveys it is not (`docs/07-fitting-architecture.md`, Section 5).

## 9. Density surface inputs

```r
pts <- segments_as_sf(segs, "midpoints")
aea <- "+proj=aea +lat_1=40 +lat_2=46 +lat_0=43 +lon_0=-69 +datum=WGS84 +units=km"
xy  <- sf::st_coordinates(sf::st_transform(pts, aea))

segment.data <- data.frame(
  Sample.Label = segs$segments$seg_id,
  Effort       = segs$segments$seg_eff,
  X            = xy[, 1],
  Y            = xy[, 2]
)

used <- fit$ddf$data
observation.data <- data.frame(
  object       = used$object,
  Sample.Label = used$Sample.Label,
  size         = used$size,
  distance     = used$distance
)
```

Midpoints are projected to an equal-area projection in km before modelling.
Observations are taken from the detections the detection function was fitted
to (`fit$ddf$data`), so truncated detections are excluded and `object`
matches.

## 10. Density surface

```r
library(dsm)
mod <- dsm(count ~ s(X, Y, k = 5),
           ddf.obj = fit,
           segment.data = segment.data,
           observation.data = observation.data,
           family = tw(), method = "REML",
           convert.units = 0.001)
summary(mod)
```

Count per segment is modelled as a smooth of position, with the segment's
searched area as offset. `convert.units = 0.001` for the same reason as in
Section 8. `k = 5` only because the fixture has 20 segments; a real survey
supports more.

Result: 22.1% deviance explained.

## 11. Abundance

```r
grid <- expand.grid(
  X = seq(min(xy[, 1]), max(xy[, 1]), by = 5),
  Y = seq(min(xy[, 2]), max(xy[, 2]), by = 5)
)
grid$off.set <- 25                                   # cell area, km^2
grid$N <- predict(mod, newdata = grid, off.set = grid$off.set,
                  type = "response")
sum(grid$N)

v <- dsm_var_gam(mod, pred.data = grid, off.set = grid$off.set)
summary(v)
```

Abundance is predicted on a grid of 5 × 5 km cells and summed. The grid here
is the bounding box of the segments; a real analysis predicts over the study
area, with the same covariates the model used.

Result: 99 cells, 352.4 animals, CV 0.61. This differs from Section 8 because
it covers only the bounding box, not the 5,811 km² study area.

## 12. Units

| Quantity | Unit |
|---|---|
| `seg_eff`, `Effort` | km |
| `distance` | m (default) or km |
| `area`, `off.set` | km² |
| `convert_units`, `convert.units` | 0.001 for m distances and km effort; 1 for km and km |

## 13. Limitations

- The fixture is synthetic and small. The fits above show the code runs; the
  estimates mean nothing.
- `g(0) = 1` is assumed throughout. Availability and perception bias are not
  corrected.
- Detection-function model selection (keys, adjustments, covariates) belongs
  to the dsfit package, and project choices to the dsmfit repository. This
  chapter fits one model of each.

## 14. Verification performed

| Check | Result |
|---|---|
| Every code block, run in order on the fixture | Runs without error. Numbers above are from that run. |
| `ds()` on a flatfile of exact distances | Failed before this date: `detection_data()` emitted all-NA `distbegin`/`distend`, which `ds()` reads as binned data. Corrected; test added in `tests/testthat/test-detection-data.R`. |
| Vignette `from-segments-to-density.Rmd` fitting code | Not run by `R CMD check` (`eval = FALSE`). Missing `convert_units` in `ds()` and `convert.units` in `dsm()`, and referred to an undefined `df_data`. Corrected to the code in Sections 8–10. |

## 15. References

Buckland, S.T., Anderson, D.R., Burnham, K.P., Laake, J.L., Borchers, D.L. and
Thomas, L. (2001) *Introduction to Distance Sampling.* Oxford University Press.

Miller, D.L., Burt, M.L., Rexstad, E.A. and Thomas, L. (2013) Spatial models
for distance sampling data: recent developments and future directions.
*Methods in Ecology and Evolution* 4(11):1001–1010.

Miller, D.L., Rexstad, E., Thomas, L., Marshall, L. and Laake, J.L. (2019)
Distance sampling in R. *Journal of Statistical Software* 89(1):1–28.

Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database: A
Guide for Users and Contributors, Version 8.* NARWC Reference Document 2023-01.
