# References

Every citation the package relies on, and what it is relied on *for*. All DOIs
verified against CrossRef.

---

## The segmentation method

> **Becker, E.A., Forney, K.A., Ferguson, M.C., Foley, D.G., Smith, R.C.,
> Barlow, J. and Redfern, J.V. (2010)** Comparing California Current
> cetacean–habitat models developed using in situ and remotely sensed sea surface
> temperature data. *Marine Ecology Progress Series* **413**: 163–183.
> <https://doi.org/10.3354/meps08696>

This is the citation for the segment-chopping approach that `plan_segments()` and
`cut_segments()` implement, and the paper behind Becker's `segchopr` code that
`original/compute_num_segs.R` was adapted from.

It is what the literature points at. Later papers in the same programme describe
their samples by reference to it rather than restating the method — Becker et al.
(2019), for instance:

> "Continuous portions of survey effort were divided into approximate 5-km
> segments to create samples for modelling using the approach described by Becker
> et al. (2010). Species-specific sighting data were assigned to each segment
> (total number of sightings and average group size), and habitat covariates were
> derived based on the segment's geographical mid-point."

Three elements of `distsamp` come straight from that sentence: segments are cut
from **continuous** effort (`split_tracks()`), sightings are assigned to the
segment they fall in (`segment_sightings()`), and covariates are taken at the
segment **mid-point** (`segment_midpoints()`).

### What the published methods do not cover

Worth being precise about, because it affects how you cite this package.

The published descriptions state the target segment length and that segments come
from continuous effort. They do **not** describe the handling of the leftover
distance at the end of a track — the tolerance test that decides whether a
remainder becomes its own segment or is absorbed, or the choice of a *random*
segment to absorb it rather than the last one. Those are properties of the
`segchopr` implementation, and I could not find them described in print.

So: cite Becker et al. (2010) for the method. For the remainder handling, the
tolerance parameter, and the over/under cut rule, the description in
[02-implementation.md](02-implementation.md#step-8--plan_segments) and
`?plan_segments` is the documentation of record. This matters if you are writing
a methods section — those details are reproducible from here but are not
attributable to the 2010 paper.

---

## Supporting method papers

> **Hedley, S.L. and Buckland, S.T. (2004)** Spatial models for line transect
> sampling. *Journal of Agricultural, Biological, and Environmental Statistics*
> **9**: 181–199. <https://doi.org/10.1198/1085711043578>

The statistical framework segmenting exists to serve: modelling counts per
segment against spatial covariates, with effort as an offset.

> **Miller, D.L., Burt, M.L., Rexstad, E.A. and Thomas, L. (2013)** Spatial
> models for distance sampling data: recent developments and future directions.
> *Methods in Ecology and Evolution* **4**: 1001–1010.
> <https://doi.org/10.1111/2041-210X.12105>

The density surface modelling formulation and the `dsm` package, which the output
of `segment_survey()` is shaped for.

> **Buckland, S.T., Anderson, D.R., Burnham, K.P., Laake, J.L., Borchers, D.L.
> and Thomas, L. (2001)** *Introduction to Distance Sampling: Estimating
> Abundance of Biological Populations.* Oxford University Press.

The standard reference for line-transect distance sampling, and the one the NARWC
handbook itself names (section 3.1).

> **Becker, E.A., Forney, K.A., Redfern, J.V., Barlow, J., Jacox, M.G., Roberts,
> J.J. and Palacios, D.M. (2019)** Predicting cetacean abundance and distribution
> in a changing climate. *Diversity and Distributions* **25**: 626–643.
> <https://doi.org/10.1111/ddi.12867>

Cited for its restatement of the segmenting procedure, quoted above, and for
covariate sampling at the segment mid-point.

> **Becker, E.A., Forney, K.A., Thayre, B.J., Debich, A.J., Campbell, G.S.,
> Whitaker, K., Douglas, A.B., Gilles, A., Hoopes, R. and Hildebrand, J.A.
> (2017)** Habitat-based density models for three cetacean species off southern
> California illustrate pronounced seasonal differences. *Frontiers in Marine
> Science* **4**: 121. <https://doi.org/10.3389/fmars.2017.00121>

Another restatement, and the source of the note that segment length is chosen so
that habitat is expected to vary little within a segment — which is the practical
guidance for choosing `seg_length`.

---

## The data format

> **Kenney, R.D. (2021)** *The North Atlantic Right Whale Consortium Database: A
> Guide for Users and Contributors, Version 7.* North Atlantic Right Whale
> Consortium Reference Document 2021-01. University of Rhode Island, Graduate
> School of Oceanography, Narragansett, Rhode Island.
> <https://www.narwc.org/sightings-database.html>

The input-format specification. Sections used:

| Section | Used for |
|---|---|
| 3.1 | Line-transect vs POP vs opportunistic data types |
| 4.2, Figure 2 | The worked example the test fixture is built from; the rule that pilot sightings cannot enter a density estimate; the CETAP rule for circling sightings |
| Table 1 | Master variable list and types |
| 8.A.15 | `IDREL` |
| 8.A.19 | `LEGSTAGE` |
| 8.A.20 | `LEGTYPE` |
| 8.A.29 | `STRATUM` |
| 8.A.30 | `STRIP` |
| 8.A.35 | `TAXCODE` |
| 8.A.36 | `TIME` |
| 8.A.37 | `VISIBLTY`, including the two encodings |

---

## Distance calculation

> **Kenney, R.D. and Winn, H.E. (1986)** Cetacean high-use habitats of the
> northeast United States continental shelf. *Fishery Bulletin* **84**: 345–357.

The `"kenney"` method in `gc_distance()`: the spherical law of cosines scaled by
111.12 km per degree.

Becker's `fn.grcirclkm` — the `"becker"` method — has no separate published
description that I could find; it appears in the `segchopr` code, reproduced in
`original/ds_data_dmr.R:70-98`. As documented in
[03-bug-fixes.md](03-bug-fixes.md#the-becker-and-kenney-methods-are-the-same-formula),
it is the same formula as Kenney and Winn's.

> **Kenney, R.D. and Scott, G.P. (1981)** Cited in handbook 8.A.30 for the
> calibrated strip markings used to classify right-angle sighting distances on the
> AT-11 and Skymaster.

Relevant to `STRIP`, which v1 carries through but does not interpret.

---

## How to cite the package

```
Ross, C. (2026) distsamp: Segment Aerial Line-Transect Survey Data for Distance
Sampling. R package version 0.1.0. https://github.com/chross22/distsamp
```

In a methods section, cite the method and the software separately — for example:

> Continuous portions of on-effort survey trackline were divided into segments of
> approximately 5 km following Becker et al. (2010), using the `distsamp` R
> package (Ross 2026). Effort was accumulated as great-circle distance between
> consecutive on-effort positions; segments were cut at record boundaries, with
> the remainder of each trackline assigned to a randomly selected segment when it
> fell below half the target length. Habitat covariates were sampled at the
> along-track mid-point of each segment. On-effort criteria followed the CETAP
> standard (Kenney 2021): survey line, Beaufort sea state at most 3, altitude
> below 366 m, and visibility of at least 2 nautical miles.

Record the `seed` you used — without it the segmentation is not reproducible.
