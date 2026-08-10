# distsamp

<!-- badges: start -->
[![R-CMD-check](https://github.com/chross22/distsamp/actions/workflows/R-CMD-check.yaml/badge.svg)](https://github.com/chross22/distsamp/actions/workflows/R-CMD-check.yaml)
[![check-citations](https://github.com/chross22/distsamp/actions/workflows/check-citations.yaml/badge.svg)](https://github.com/chross22/distsamp/actions/workflows/check-citations.yaml)
<!-- badges: end -->

Segment aerial line-transect marine mammal survey data for distance sampling and
density surface modeling.

Takes survey data in the format of the North Atlantic Right Whale Consortium
(NARWC) sightings database and produces effort segments — each with a location,
an amount of effort, and counts of what was seen along it — ready for `Distance`
and `dsm`.

> **The input format is specified by the NARWC users' guide:**
> Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database: A
> Guide for Users and Contributors, Version 8.* NARWC Reference Document 2023-01.
> **[Read the handbook (PDF)](https://www.narwc.org/uploads/1/1/6/6/116623219/narwc_users_guide__v8_.pdf)**
> · [database landing page](https://www.narwc.org/sightings-database.html)
>
> Every code book, column definition, and effort rule in this package cites a
> section of it. Chapter 8 sections are numbered alphabetically by variable, so
> **they shift between versions** — `distsamp` cites Version 8 throughout. See
> [docs/06-references.md](docs/06-references.md) for what each section is relied
> on for.

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
segs$detections                  # one row per sighting, with perpendicular distance
```

Two vignettes:

```r
vignette("segmenting-narwc-data", package = "distsamp")   # the full walkthrough
vignette("from-segments-to-density", package = "distsamp") # handing off to Distance and dsm
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

Where the survey recorded `ANGLEL`/`ANGLER` declination angles, perpendicular
distances are computed too, and `segs$detections` comes out in the shape a
detection function wants.

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
Kenney (2023), *The North Atlantic Right Whale Consortium Database: A Guide for
Users and Contributors*, Version 8 — `LEGTYPE` (8.A.21), `LEGSTAGE` (8.A.20),
`IDREL` (8.A.16), `VISIBLTY` (8.A.38), and the rest. `narwc_codes()` prints them.

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
- **Declination angles give perpendicular distance.** `ANGLEL`/`ANGLER` are
  angles below the horizon, taken when the sighting is abeam (8.A.2), so
  distance is `ALT / tan(angle)`. They replaced `STRIP` in 2022 because survey
  altitudes had to rise for offshore wind, and `STRIP`'s fixed intervals shift
  with altitude while an angle does not.
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

This package was rewritten from a set of internal research scripts. Those are
not distributed — they contain collaborators' working notes and local paths.
`docs/` records what was carried over, what was fixed, and why.

## Citing distsamp

```r
citation("distsamp")
```

That returns three entries — the package, the segmentation method it implements,
and the data format — because a methods section usually needs all three:

```
Ross, C. distsamp: Segment Aerial Line-Transect Survey Data for Distance
Sampling. R package. https://github.com/chross22/distsamp

Becker, E.A., Forney, K.A., Ferguson, M.C., Foley, D.G., Smith, R.C., Barlow, J.
and Redfern, J.V. (2010) Comparing California Current cetacean-habitat models
developed using in situ and remotely sensed sea surface temperature data. Marine
Ecology Progress Series 413:163-183. doi:10.3354/meps08696

Kenney, R.D. (2023) The North Atlantic Right Whale Consortium Database: A Guide
for Users and Contributors, Version 8. NARWC Reference Document 2023-01.
```

The package version comes from `DESCRIPTION` at install time, so it is always the
version you actually have.

Record the `seed` you used — without it the segmentation is not reproducible.

Suggested methods-section wording is in
[docs/06-references.md](docs/06-references.md#6-how-to-cite-the-package), along
with a note on which parts of the algorithm are attributable to the published
methods and which are properties of Becker's implementation.

---

## References

Alphabetical. What each source is relied on for is set out in
[docs/06-references.md](docs/06-references.md). These are checked monthly by
CI — DOIs still resolve and still describe the paper we cite, hosted PDFs are
still there, and the NARWC handbook is still at the version we cite. Run it
yourself with `Rscript tools/check-citations.R`.

Becker, E.A., Forney, K.A., Ferguson, M.C., Foley, D.G., Smith, R.C., Barlow, J.
and Redfern, J.V. (2010) Comparing California Current cetacean–habitat models
developed using in situ and remotely sensed sea surface temperature data. *Marine
Ecology Progress Series* 413:163–183. <https://doi.org/10.3354/meps08696>
— *the segmentation method.*

Becker, E.A., Forney, K.A., Redfern, J.V., Barlow, J., Jacox, M.G., Roberts, J.J.
and Palacios, D.M. (2019) Predicting cetacean abundance and distribution in a
changing climate. *Diversity and Distributions* 25:626–643.
<https://doi.org/10.1111/ddi.12867>

Becker, E.A., Forney, K.A., Thayre, B.J., Debich, A.J., Campbell, G.S., Whitaker,
K., Douglas, A.B., Gilles, A., Hoopes, R. and Hildebrand, J.A. (2017)
Habitat-based density models for three cetacean species off southern California
illustrate pronounced seasonal differences. *Frontiers in Marine Science* 4:121.
<https://doi.org/10.3389/fmars.2017.00121>

Buckland, S.T., Anderson, D.R., Burnham, K.P., Laake, J.L., Borchers, D.L. and
Thomas, L. (2001) *Introduction to Distance Sampling: Estimating Abundance of
Biological Populations.* Oxford University Press, New York, NY.

CETAP (1982) *A Characterization of Marine Mammals and Turtles in the Mid- and
North-Atlantic Areas of the U.S. Outer Continental Shelf, Final Report.* Cetacean
and Turtle Assessment Program, University of Rhode Island. Bureau of Land
Management, Washington, DC. — *the survey protocol behind the effort defaults.*

Hedley, S.L. and Buckland, S.T. (2004) Spatial models for line transect sampling.
*Journal of Agricultural, Biological, and Environmental Statistics* 9:181–199.
<https://doi.org/10.1198/1085711043578>

Kenney, R.D. (2002) *Quality-control Issues for Data Submissions to the North
Atlantic Right Whale Consortium Database.* NARWC Reference Document 2002-02.
University of Rhode Island, Graduate School of Oceanography, Narragansett, RI.

Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database: A Guide
for Users and Contributors, Version 8.* NARWC Reference Document 2023-01.
University of Rhode Island, Graduate School of Oceanography, Narragansett, RI.
<https://www.narwc.org/sightings-database.html> — *the input format.*

Kenney, R.D. and Scott, G.P. (1981) Calibration of the Beechcraft AT-11 forward
observation bubble for population estimation purposes. Pp. III.1–III.11 *in*
CETAP, *A Characterization of Marine Mammals and Turtles in the Mid- and
North-Atlantic Areas of the U.S. Outer Continental Shelf, Annual Report for
1979.* Bureau of Land Management, Washington, DC.

Kenney, R.D. and Shoop, C.R. (2012) Aerial surveys for marine turtles. Pp.
264–271 *in* R.W. McDiarmid, M.S. Foster, C. Guyer, J.W. Gibbons and N. Chernoff,
eds. *Reptile Biodiversity: Standard Methods for Inventory and Monitoring.*
University of California Press, Berkeley, CA.

Kenney, R.D. and Winn, H.E. (1986) Cetacean high-use habitats of the northeast
United States continental shelf. *Fishery Bulletin* 84(2):345–357. — *the
`"kenney"` distance formula, p. 347, and the CETAP on-effort criteria.*

Miller, D.L., Burt, M.L., Rexstad, E.A. and Thomas, L. (2013) Spatial models for
distance sampling data: recent developments and future directions. *Methods in
Ecology and Evolution* 4:1001–1010.
<https://doi.org/10.1111/2041-210X.12105>

Miller, D.L., Rexstad, E., Thomas, L., Marshall, L. and Laake, J.L. (2019)
Distance sampling in R. *Journal of Statistical Software* 89(1):1–28.
<https://doi.org/10.18637/jss.v089.i01>

Pebesma, E. (2018) Simple features for R: standardized support for spatial vector
data. *The R Journal* 10(1):439–446. <https://doi.org/10.32614/RJ-2018-009>

R Core Team (2026) *R: A Language and Environment for Statistical Computing.* R
Foundation for Statistical Computing, Vienna, Austria.
<https://www.R-project.org/>

Shoemake, K. (1985) Animating rotation with quaternion curves. *ACM SIGGRAPH
Computer Graphics* 19(3):245–254. <https://doi.org/10.1145/325165.325242>

Sinnott, R.W. (1984) Virtues of the haversine. *Sky and Telescope* 68(2):159.
