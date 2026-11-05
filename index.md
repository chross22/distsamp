# distsamp

Segments NARWC line-transect survey data for distance sampling and
density surface models (`Distance`, `dsm`).

Input format: Kenney, R.D. (2023) *The North Atlantic Right Whale
Consortium Database: A Guide for Users and Contributors, Version 8.*
[Handbook
(PDF)](https://www.narwc.org/uploads/1/1/6/6/116623219/narwc_users_guide__v8_.pdf).

## Install

``` r

remotes::install_github("chross22/distsamp")
```

Depends on [narwcr](https://github.com/chross22/narwcr), installed
automatically.

## Example data

``` r

path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
```

Synthetic. No real NARWC records are included.

## Read

``` r

library(distsamp)
dat <- read_narwc(path)
```

## Prepare

``` r

dat <- prepare_survey(dat, platform = "aerial")
```

Builds line occupations, fills `LEGSTAGE`, filters by platform, flags
effort.

## Check

``` r

validate_narwc(dat)
diagnose_pipeline(dat, seg_length = 5)
plot_survey(dat, "occupations")
```

## Segment

``` r

segs <- segment_survey(dat, seg_length = 5, seed = 1)

segs$segments     # one row per segment
segs$detections   # one row per sighting, with distance
segments_wide(segs)
plot(segs, what = "segments")
```

`seed` makes the segmentation reproducible.

## Detection table

``` r

flat <- detection_data(segs, area = 5811)   # area in km^2
```

## Fit

``` r

library(Distance)
fit <- ds(flat, key = "hn", convert_units = 0.001)   # m distances, km effort
```

Full steps to an abundance estimate:
[docs/11-distance-sampling-steps.md](https://camilleross.org/distsamp/docs/11-distance-sampling-steps.md).

## Shipboard surveys

``` r

sea  <- prepare_survey(dat, platform = "vessel")
segs <- segment_survey(sea, seg_length = 10, platform = "vessel", seed = 1)
platform_defaults("vessel")
```

## Units

| Column     | Unit                                        |
|------------|---------------------------------------------|
| `seg_eff`  | km                                          |
| `distance` | m (default) or km (`distance_units = "km"`) |

## Other functions

``` r

narwc_codes("LEGTYPE")            # handbook code books
filter_days(dat, years = 2024)    # subset by date
dist_methods()                    # along-track distance formulas
```

## Documentation

| Topic | File |
|----|----|
| Analysis steps | [docs/11-distance-sampling-steps.md](https://camilleross.org/distsamp/docs/11-distance-sampling-steps.md) |
| Code guide | [docs/10-code-guide.md](https://camilleross.org/distsamp/docs/10-code-guide.md) |
| New dataset | [docs/08-onboarding-a-real-extract.md](https://camilleross.org/distsamp/docs/08-onboarding-a-real-extract.md) |
| Shipboard surveys | [docs/09-shipboard-surveys.md](https://camilleross.org/distsamp/docs/09-shipboard-surveys.md) |
| Defects fixed from original code | [docs/03-bug-fixes.md](https://camilleross.org/distsamp/docs/03-bug-fixes.md) |
| References | [docs/06-references.md](https://camilleross.org/distsamp/docs/06-references.md) |
| All documents | [docs/README.md](https://camilleross.org/distsamp/docs/README.md) |

``` r

vignette("segmenting-narwc-data", package = "distsamp")
vignette("from-segments-to-density", package = "distsamp")
```

## Citing distsamp

``` r

citation("distsamp")
```

Returns the package, the segmentation method (Becker et al. 2010) and
the data format (Kenney 2023). Report the `seed` used.
