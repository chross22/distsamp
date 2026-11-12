# References

*C. H. Ross. 2026-11-12. Distributed with the package source.*

## 1. Scope

This chapter lists every source the package relies on and states what each is
relied on *for*. It also states what the published methods do not cover, how
to cite the package, and how the citations are kept current.

All DOIs and bibliographic details were verified against CrossRef or against
the source document. The grey literature is transcribed from the reference
list of the NARWC handbook (Kenney 2023, chapter 10). The consolidated list is
at the [bottom of the README](../README.md#references).

---

## 2. Segmentation and the statistical framework

### The segmentation method

> **Becker, E.A., Forney, K.A., Ferguson, M.C., Foley, D.G., Smith, R.C.,
> Barlow, J. and Redfern, J.V. (2010)** Comparing California Current
> cetacean–habitat models developed using in situ and remotely sensed sea surface
> temperature data. *Marine Ecology Progress Series* **413**: 163–183.
> <https://doi.org/10.3354/meps08696>

The citation for the segment-chopping approach implemented by `plan_segments()`
and `cut_segments()`. It is also the paper behind the `segchopr` code from which
`original/compute_num_segs.R` was adapted.

Later papers in the same programme cite it rather than restate the method.
Becker et al. (2019):

> "Continuous portions of survey effort were divided into approximate 5-km
> segments to create samples for modelling using the approach described by Becker
> et al. (2010). Species-specific sighting data were assigned to each segment
> (total number of sightings and average group size), and habitat covariates were
> derived based on the segment's geographical mid-point."

Three elements of `distsamp` come from that sentence:

| Element | Function |
|---|---|
| Segments are cut from **continuous** effort | `split_tracks()` |
| Sightings are assigned to the segment they fall in | `segment_sightings()` |
| Covariates are taken at the segment **mid-point** | `segment_midpoints()` |

### What the published methods do not cover

This affects how the package is cited.

The published descriptions state the target segment length and that segments
come from continuous effort. They do **not** describe the handling of the
leftover distance at the end of a track: the tolerance test that decides
whether a remainder becomes its own segment or is absorbed, and the choice of a
*random* segment to absorb it rather than the last one. These are properties of
the `segchopr` implementation. No printed description of them was found.

Cite Becker et al. (2010) for the method. For the remainder handling, the
tolerance parameter, and the over/under cut rule, the documentation of record is
[02-implementation.md](02-implementation.md#step-8--plan_segments) and
`?plan_segments`. In a methods section, these details are reproducible from
here but are not attributable to the 2010 paper.

### Restatements of the method, cited for specific details

> **Becker, E.A., Forney, K.A., Redfern, J.V., Barlow, J., Jacox, M.G., Roberts,
> J.J. and Palacios, D.M. (2019)** Predicting cetacean abundance and distribution
> in a changing climate. *Diversity and Distributions* **25**: 626–643.
> <https://doi.org/10.1111/ddi.12867>

Quoted above. Also the source for covariates sampled at the segment mid-point
over a 3 × 3-pixel box; cited in `?segment_midpoints`.

> **Becker, E.A., Forney, K.A., Thayre, B.J., Debich, A.J., Campbell, G.S.,
> Whitaker, K., Douglas, A.B., Gilles, A., Hoopes, R. and Hildebrand, J.A.
> (2017)** Habitat-based density models for three cetacean species off southern
> California illustrate pronounced seasonal differences. *Frontiers in Marine
> Science* **4**: 121. <https://doi.org/10.3389/fmars.2017.00121>

Source of the guidance for choosing `seg_length`: segment size is chosen for
the oceanography and bathymetry of the study area, so that habitat is expected
to vary little within a segment.

### The statistical framework

> **Hedley, S.L. and Buckland, S.T. (2004)** Spatial models for line transect
> sampling. *Journal of Agricultural, Biological, and Environmental Statistics*
> **9**: 181–199. <https://doi.org/10.1198/1085711043578>

The framework that segmenting serves: counts per segment are modelled against
spatial covariates, with effort as an offset.

> **Miller, D.L., Burt, M.L., Rexstad, E.A. and Thomas, L. (2013)** Spatial
> models for distance sampling data: recent developments and future directions.
> *Methods in Ecology and Evolution* **4**: 1001–1010.
> <https://doi.org/10.1111/2041-210X.12105>

The density surface modelling formulation and the `dsm` package. The output of
`segments_wide()` is shaped for it.

> **Buckland, S.T., Anderson, D.R., Burnham, K.P., Laake, J.L., Borchers, D.L.
> and Thomas, L. (2001)** *Introduction to Distance Sampling: Estimating
> Abundance of Biological Populations.* Oxford University Press, New York, NY.

The standard reference for line-transect distance sampling. The NARWC handbook
names it in section 3.1 as the place to begin.

> **Kenney, R.D. and Shoop, C.R. (2012)** Aerial surveys for marine turtles. Pp.
> 264–271 *in* R.W. McDiarmid, M.S. Foster, C. Guyer, J.W. Gibbons and N.
> Chernoff, eds. *Reptile Biodiversity: Standard Methods for Inventory and
> Monitoring.* University of California Press, Berkeley, CA.

Named by the handbook (3.1) as an accessible summary of aerial line-transect
methodology.

---

## 3. Distance calculation

> **Kenney, R.D. and Winn, H.E. (1986)** Cetacean high-use habitats of the
> northeast United States continental shelf. *Fishery Bulletin* **84**(2):
> 345–357.

**The verified primary source for the `"kenney"` method.** The formula is given
on p. 347:

> "For any pair of successive positions, the length of track line between the
> points (D, in km) can be calculated by:
>
>     D = 111.12 arccos [sin (X₁) sin (X₂) + cos (X₁) cos (X₂) cos (Y₂ − Y₁)],
>
> where X₁ and X₂ are the latitudes of the two positions, and Y₁ and Y₂ are the
> corresponding longitudes. This calculates great circle distance."

This is `dist.rdk` in `original/ds_data_dmr.R:62-66`, except that the original
passes decimal degrees to `sin()` and `cos()` without converting to radians, so
it never computed this formula. `gc_distance(method = "kenney")` computes what
the paper published.

Two Kenney & Winn 1986 works exist, and the handbook cites both. This entry is
the *Fishery Bulletin* paper. The other, *Marine Mammal Data Transfer and
Documentation* (NMFS final report, contract no. 40-EANF-501629), concerns the
CETAP database transfer and is not the source of the distance formula.

The same page justifies great-circle distance for a platform that flies rhumb
lines:

> "Flight or cruise tracks would actually be rhumb lines rather than great
> circles, but the algorithm required to calculate rhumb line distance is much
> more complex. Furthermore, for two points around 10 km apart, typical of track
> line segments in the data, great circle and rhumb line distance differ by <1 m,
> an error of <0.01%."

> **Sinnott, R.W. (1984)** Virtues of the haversine. *Sky and Telescope*
> **68**(2): 159.

The haversine formulation, and the standard reference for preferring it over the
law of cosines at short range. `"haversine"` is the package default.

> **Veness, C. (2019)** *Calculating distance, bearing and more between
> latitude/longitude points.* Movable Type Scripts.
> <https://www.movable-type.co.uk/scripts/latlong.html>

The cross-track and along-track great-circle formulae used by
`cross_track_distance()`, and the initial-bearing and destination-point
formulae behind `gc_bearing()`. These are standard spherical trigonometry, not a
research result. The source is cited because it states them in the form
implemented, so the implementation can be checked against it.

Becker's `fn.grcirclkm` (the `"becker"` method) has no separate published
description that could be found. It appears in the `segchopr` code, reproduced
at `original/ds_data_dmr.R:70-98`. It is algebraically identical to Kenney and
Winn's formula, as shown in
[03-bug-fixes.md](03-bug-fixes.md#the-becker-and-kenney-methods-are-the-same-formula).

> **Shoemake, K. (1985)** Animating rotation with quaternion curves. *ACM
> SIGGRAPH Computer Graphics* **19**(3): 245–254.
> <https://doi.org/10.1145/325165.325242>

Spherical linear interpolation. Used by `gc_interpolate()` to place a segment
midpoint between two bracketing survey positions.

---

## 4. The data format and survey protocol

> **Kenney, R.D. (2023)** *The North Atlantic Right Whale Consortium Database: A
> Guide for Users and Contributors, Version 8.* North Atlantic Right Whale
> Consortium Reference Document 2023-01. University of Rhode Island, Graduate
> School of Oceanography, Narragansett, Rhode Island.
> <https://www.narwc.org/sightings-database.html>

The input-format specification. Sections used, and where:

| Section | Used for | Where |
|---|---|---|
| 3.1 | Line-transect vs POP vs opportunistic data types | `?narwc_schema` |
| 4.2, Figure 2 | The worked example the test fixture is built from; pilot sightings cannot enter a density estimate; the CETAP rule for circling sightings | `data-raw/make-fixture.R`, `?segment_sightings`, `?attach_circling_sightings` |
| Table 1 | Master variable list and types | `?narwc_schema` |
| 8.A.16 | `IDREL` | `?narwc_codes`, `?segment_sightings` |
| 8.A.18, 8.A.22 | `LAT_DD`, `LONG_DD`, and the sign convention | `?read_narwc`, `?validate_narwc` |
| 8.A.20 | `LEGSTAGE` | `?narwc_codes`, `?flag_circling`, `?segment_sightings` |
| 8.A.21 | `LEGTYPE` | `?narwc_codes`, `?flag_effort`, `?flag_circling` |
| 8.A.24 | `NUMBER` required for sightings | `?validate_narwc` |
| 8.A.30 | `STRATUM` | `?narwc_codes` |
| 8.A.31 | `STRIP`, both interval code books, and the Skymaster blind spot | `?narwc_strip_bins`, `?strip_distance`, `?sighting_distances` |
| 8.A.33, 8.A.34 | `S_LAT`, `S_LONG`, the exact sighting position | `?exact_distance`, `?validate_narwc` |
| 8.A.36 | `TAXCODE` | `?narwc_codes` |
| 8.A.37 | `TIME` | `?validate_narwc` |
| 8.A.38 | `VISIBLTY`, including the two encodings | `?visibility_ok` |

> **CETAP (1982)** *A Characterization of Marine Mammals and Turtles in the Mid-
> and North-Atlantic Areas of the U.S. Outer Continental Shelf, Final Report.*
> Cetacean and Turtle Assessment Program, University of Rhode Island. Bureau of
> Land Management, Washington, DC.

The programme whose protocol the effort defaults come from, and the origin of
the data structures the NARWC database inherited.

Kenney and Winn (1986, p. 347) state the on-effort criteria applied to the CETAP
data, which `flag_effort()` uses: "observer(s) formally on watch, clear
visibility of at least 2 miles, and sea states of Beaufort 3 or lower". Surveys
were flown at 750 ft, 229 m (p. 346). The default altitude ceiling of 366 m
(1,200 ft) therefore sits well above normal survey altitude.

> **Kenney, R.D. and Scott, G.P. (1981)** Calibration of the Beechcraft AT-11
> forward observation bubble for population estimation purposes. Pp. III.1–III.11
> *in* CETAP, *A Characterization of Marine Mammals and Turtles in the Mid- and
> North-Atlantic Areas of the U.S. Outer Continental Shelf, Annual Report for
> 1979.* Bureau of Land Management, Washington, DC.

The calibrated strip markings behind the `STRIP` right-angle distance intervals
(handbook 8.A.31). Relevant to the detection-function work in
[05-next-steps.md](05-next-steps.md), not to v1.

> **Kenney, R.D. (2002)** *Quality-control Issues for Data Submissions to the
> North Atlantic Right Whale Consortium Database.* NARWC Reference Document
> 2002-02. University of Rhode Island, Graduate School of Oceanography.

Background for `validate_narwc()`.

---

## 5. Software

> **R Core Team (2026)** *R: A Language and Environment for Statistical
> Computing.* R Foundation for Statistical Computing, Vienna, Austria.
> <https://www.R-project.org/>

> **Pebesma, E. (2018)** Simple features for R: standardized support for spatial
> vector data. *The R Journal* **10**(1): 439–446.
> <https://doi.org/10.32614/RJ-2018-009>

Used by `segments_as_sf()` and `crop_to_bbox()`. In `Suggests`.

> **Miller, D.L., Rexstad, E., Thomas, L., Marshall, L. and Laake, J.L. (2019)**
> Distance sampling in R. *Journal of Statistical Software* **89**(1): 1–28.
> <https://doi.org/10.18637/jss.v089.i01>

The `Distance` package, a downstream consumer of this package's output. It is
in `Suggests`, used only by a test that fits a detection function to
`detection_data()` output.

For the remaining dependencies (`dplyr`, `tidyr`, `rlang`, `tibble`, `withr`,
`narwcr`, `testthat`), use `citation("dplyr")` and so on.

---

## 6. How to cite the package

```
Ross, C. (2026) distsamp: Segment Line-Transect Survey Data for Distance
Sampling. R package version 0.1.0. https://github.com/chross22/distsamp
```

In a methods section, the method and the software are cited separately. For
example:

> Continuous portions of on-effort survey trackline were divided into segments of
> approximately 5 km following Becker et al. (2010), using the `distsamp` R
> package (Ross 2026). Effort was accumulated as great-circle distance between
> consecutive on-effort positions (Kenney and Winn 1986). Segments were cut at
> record boundaries, with the remainder of each trackline assigned to a randomly
> selected segment when it fell below half the target length; habitat covariates
> were sampled at the along-track mid-point of each segment. On-effort criteria
> followed the CETAP standard (CETAP 1982; Kenney 2023): survey line, Beaufort
> sea state of 3 or lower, altitude below 366 m, and clear visibility of at least
> 2 nautical miles. Sightings by observers other than the dedicated on-duty
> observers, sightings detected in vertical photographs, and identifications
> below "probable" reliability were excluded (Kenney 2023).

Record the `seed` used. Without it the segmentation is not reproducible.

---

## 7. Keeping citations current

Citations go out of date: a DOI is corrected, a hosted PDF moves, or the NARWC
publishes a new handbook version. The last matters most, because the package's
correctness depends on the handbook's code books.

`tools/citations.csv` is the registry: one row per source, with the DOI or URL
and the metadata printed. `tools/check-citations.R` verifies it:

```bash
Rscript tools/check-citations.R
```

| Check | What it verifies | Catches |
|---|---|---|
| 1. Registry coverage | Every DOI in the package is in the registry, and every registry DOI is cited. Offline, so it also runs in the test suite. | A new citation added unchecked |
| 2. CrossRef metadata | First author, year, title, journal and volume still match | A transcription error here, or a correction by the publisher |
| 3. URL liveness | The NARWC page, the NOAA-hosted Kenney and Winn PDF, and the R project page still resolve | Moved or removed pages |
| 4. NARWC handbook version | The Consortium's sightings-database page still offers the cited version | A new handbook version |
| 5. Self-citation | `inst/CITATION` parses and does not hard-code a stale version; the README has a citation section naming the package | A package that cannot be cited, or is cited at the wrong version |
| 6. Reference list | The README's References section agrees with the registry | A README list that drifts from the sources |

`.github/workflows/check-citations.yaml` runs the check on the first of each
month and on any pull request touching `tools/`, `R/`, `docs/`, `README.md`,
`DESCRIPTION` or `inst/CITATION`. A scheduled failure opens one issue labelled
`citations`. A second issue is not opened while one is open.

### When the handbook version check fires

Do not simply bump the citation. First diff the new version against the code
books, which live in `narwcr` (`narwc_codes()`). The `LEGTYPE`, `LEGSTAGE`, `IDREL`, `VISIBLTY`, `TAXCODE`
and `STRATUM` values are load-bearing, and section numbers shift whenever a
variable is added.

This happened on the check's first run. It found Version 8 (October 2023,
Reference Document 2023-01) while the package cited Version 7. The review found:

| Change in Version 8 | Consequence |
|---|---|
| **No code-book values changed.** `LEGTYPE`, `LEGSTAGE`, `IDREL`, `TAXCODE`, `STRATUM`, `STRIP`, and the negative `VISIBLTY` codes that [03-bug-fixes.md](03-bug-fixes.md#1-legacy-visibility-codes-silently-discarded-all-pre-2004-effort) depends on are identical. | Nothing in the package's behaviour was wrong. |
| **Section numbers shifted by one** from `ANGLEL` onward, because Version 8 inserts a new section for `ANGLEL`/`ANGLER`. | All 84 cross-references in the code and docs were remapped. |
| **`ANGLEL` and `ANGLER` are new**: declination angles to a sighting. The New England Aquarium survey team stopped recording `STRIP` in 2022 and switched to these. They give a more precise right-angle distance and are less sensitive to survey altitude (8.A.31). | Carried through as optional columns. Converting them to perpendicular distance belongs with the detection-function work ([05-next-steps.md](05-next-steps.md)). |
| **`WX`** is now in the code book. | Available as `narwc_codes("WX")`. |
| Version 8 dates the archive update that folded `OLDVIZ` into `VISIBLTY` to 2020; Version 7 said 2021. | The package no longer names a year for it. |
