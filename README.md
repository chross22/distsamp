# distsamp

Segment aerial line-transect marine mammal survey data for distance sampling and
density surface modeling.

Takes survey data in the format of the North Atlantic Right Whale Consortium
(NARWC) sightings database and produces effort segments — each with a location,
an amount of effort, and counts of what was seen along it — ready for `Distance`
and `dsm`.

## Install

```r
# install.packages("remotes")
remotes::install_github("chross22/distsamp")
```

## Use

```r
library(distsamp)

path <- system.file("extdata", "narwc-example.csv", package = "distsamp")

dat <- read_narwc(path)          # standardise names and types
validate_narwc(dat)              # report problems, never stop

segs <- segment_survey(dat, seg_length = 5, seed = 1)
segs
#> <distsamp_segments>
#>   segments:  20
#>   tracks:    7
#>   total effort: 92.23 km
#>   segment length: median 4.44 km, range 2.22-7.78 km
#>   target length: 5 km   seed: 1
#>   species:   FIWH, RIWH, SEWH

segments_wide(segs)              # one count column per species, for dsm
```

The full walkthrough is in the vignette:

```r
vignette("segmenting-narwc-data", package = "distsamp")
```

## What it does

```
read_narwc  ->  validate_narwc
     |
make_leg_id  ->  flag_circling  ->  flag_effort  ->  point_to_point_effort
     |
split_tracks  ->  track_effort  ->  plan_segments  ->  cut_segments
     |
attach_circling_sightings  ->  segment_midpoints  ->  segment_sightings
```

`segment_survey()` runs all of it. Every stage is also exported, so you can
intervene between them.

Segments are cut following the approach of Becker et al. (2010): divide
continuous portions of survey effort into segments of approximately equal length,
assign sightings to the segment they fall in, and take habitat covariates at each
segment's mid-point. Concretely, fit as many whole segments of the target length
as a continuous track allows, then either give the remainder its own segment or
absorb it into a randomly chosen one, depending on whether it clears half the
target length.

The remainder handling is a property of Becker's `segchopr` implementation rather
than of the published methods, which state the target length but not what happens
to the leftover — see [docs/06-references.md](docs/06-references.md#what-the-published-methods-do-not-cover)
if you are writing this up.

## Grounded in the handbook

Effort criteria, sighting filters, and validation all read from the code books in
Kenney (2021), *The North Atlantic Right Whale Consortium Database: A Guide for
Users and Contributors*, Version 7 — `LEGTYPE` (8.A.20), `LEGSTAGE` (8.A.19),
`IDREL` (8.A.15), `VISIBLTY` (8.A.37), and the rest. `narwc_codes()` prints them.

A few consequences worth knowing:

- **`VISIBLTY` carries two encodings.** Since 2004 it is a distance in nautical
  miles; before that it was a code, folded into the same field as a negative
  number, where `-1` means *clear for at least 2 nautical miles*. A plain
  `VISIBLTY >= 2` test throws away every legacy record. `visibility_ok()` handles
  both.
- **Pilot sightings do not count.** `LEGSTAGE == 6` marks a sighting by someone
  other than an on-duty observer, which handbook 4.2 says "cannot be included in
  a density estimate". Excluded by default, along with `LEGSTAGE == 7`
  (photographic) and `IDREL` 1 and 9.
- **Circling sightings do count, conditionally.** A group sighted from the track
  and then circled has its position recorded off effort. Those are attached back
  to the segment they came from, following the CETAP rule that only further
  groups of the *same species* count with the original.

## Reproducibility

Segmentation makes two random choices. Pass a `seed` and a run repeats exactly;
your session's own random stream is never disturbed.

```r
identical(
  segment_survey(dat, seg_length = 5, seed = 1)$segments,
  segment_survey(dat, seg_length = 5, seed = 1)$segments
)
#> TRUE
```

## Distance methods

```r
dist_methods()
```

`"becker"` (Becker's `segchopr`) and `"kenney"` (Kenney and Winn 1986) are both
selectable — and are the same formula, so they return identical values. The
default `"haversine"` uses the same sphere but is numerically stable at the short
ranges between consecutive survey records, where the law of cosines loses
precision.

## Documentation

`docs/` covers how this was built:
[the plan](docs/01-plan.md),
[implementation notes](docs/02-implementation.md),
[defects found in the original code](docs/03-bug-fixes.md),
[verification](docs/04-verification.md),
[next steps](docs/05-next-steps.md), and
[references](docs/06-references.md) — including how to cite this in a methods
section.

`original/` holds the research scripts this package was built from. They are kept
for reference and excluded from the build.

## References

Becker, E.A., Forney, K.A., Ferguson, M.C., Foley, D.G., Smith, R.C., Barlow, J.
and Redfern, J.V. (2010) Comparing California Current cetacean–habitat models
developed using in situ and remotely sensed sea surface temperature data. *Marine
Ecology Progress Series* 413:163–183. <https://doi.org/10.3354/meps08696>

Hedley, S.L. and Buckland, S.T. (2004) Spatial models for line transect sampling.
*Journal of Agricultural, Biological, and Environmental Statistics* 9:181–199.
<https://doi.org/10.1198/1085711043578>

Miller, D.L., Burt, M.L., Rexstad, E.A. and Thomas, L. (2013) Spatial models for
distance sampling data: recent developments and future directions. *Methods in
Ecology and Evolution* 4:1001–1010.
<https://doi.org/10.1111/2041-210X.12105>

Buckland, S.T., Anderson, D.R., Burnham, K.P., Laake, J.L., Borchers, D.L. and
Thomas, L. (2001) *Introduction to Distance Sampling.* Oxford University Press.

Kenney, R.D. (2021) *The North Atlantic Right Whale Consortium Database: A Guide
for Users and Contributors, Version 7.* NARWC Reference Document 2021-01.

Kenney, R.D. and Winn, H.E. (1986) Cetacean high-use habitats of the northeast
United States continental shelf. *Fishery Bulletin* 84:345–357.

Full list, with what each is relied on for:
[docs/06-references.md](docs/06-references.md).
