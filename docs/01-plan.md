# Plan: turning `original/` into the `distsamp` package

*C. H. Ross. 2026-11-12. Distributed with the package source.*

## 1. Scope

This chapter records why the package was built, the decisions taken before
building, the target layout and API, and what was left out of v1. The plan is
**implemented**. What each step became is in
[02-implementation.md](02-implementation.md). The defects found and corrected
along the way are in [03-bug-fixes.md](03-bug-fixes.md).

## 2. Motivation

`original/` holds about 3,000 lines of research code. It turns NARWC-format
aerial line-transect survey data into distance-sampling segments. It produced
results, but it is a set of loose scripts that `source()` each other by
relative path. **As shipped it cannot run end to end**: `chop_segments()` calls
`calculate_midpoint()` and `crop_data()`, and neither function is defined
anywhere in the folder.

Further problems:

- No `DESCRIPTION`, no namespace, no tests, no installable form.
- `library()` calls inside function bodies.
- Scripts write `.RData` and `.csv` into the working directory as a side effect
  of computing.
- Study parameters (survey area, species of interest, region label) are
  hard-coded inside functions.
- Segmentation is randomised but unseeded, so no run is reproducible.
- Several correctness bugs. The most serious silently discards all pre-2004
  survey effort.

The goal is an installable R package. Its input contract is the NARWC
sightings database format (Kenney 2023, NARWC Reference Document 2023-01,
Version 7). Its output is a segment table ready for `Distance` and `dsm`.

## 3. Decisions taken before starting

Three questions were settled first, because each changes the shape of the work.

| Question | Decision |
|---|---|
| Scope of v1 | **Segmentation core only.** Detection-function fitting, Copernicus covariate access, mapping, and GAM/DSM fitting stay out. Those files remain in `original/` and can be promoted later. |
| Test data | **Synthetic fixtures.** No real NARWC extract was available, so the test fixture is hand-built from the handbook's own worked example. |
| Fidelity to the original algorithm | **Keep the method, fix the defects.** Segment boundaries are still produced by the Becker et al. (2010) logic: segments per track, `leftover`/`segtol`, one randomly chosen absorbing segment, and a coin flip over or under the target. The bugs are fixed and chopping is reproducible from a seed. |

A fourth decision was added mid-build at the user's request: **the great-circle
distance method must be selectable between Becker and Kenney.** It is
implemented. The two methods turned out to be the same formula; see
[03-bug-fixes.md](03-bug-fixes.md#the-becker-and-kenney-methods-are-the-same-formula).

## 4. Target layout

The original scripts are kept unchanged as the reference implementation, but
outside the repository. They hold collaborators' working notes and local paths
and are not published.

```
DESCRIPTION, NAMESPACE, LICENSE, README.md, NEWS.md, .Rbuildignore
R/
  narwc-codes.R      code books: LEGTYPE, LEGSTAGE, IDREL, TAXCODE, STRATUM, VISIBLTY
  read-narwc.R       read_narwc()          ingest, column mapping, type coercion
  validate.R         validate_narwc()      schema, code, and sequence checks
  effort.R           flag_effort(), visibility_ok(), make_leg_id()
  circling.R         flag_circling(), attach_circling_sightings()
  geodist.R          gc_distance(), point_to_point_effort(), dist_methods()
  tracks.R           split_tracks(), track_effort()
  segments.R         plan_segments(), cut_segments()
  segment-survey.R   segment_survey(), segments_wide(), print method
  midpoints.R        segment_midpoints(), gc_interpolate()   [written fresh]
  sightings.R        segment_sightings()
  spatial.R          segments_as_sf(), crop_to_bbox(), write_segments()
  utils.R
tests/testthat/      180 tests planned (809 assertions on 2026-11-12)
inst/extdata/        narwc-example.csv, the synthetic fixture
data-raw/            make-fixture.R, the reproducible generator for it
vignettes/           segmenting-narwc-data.Rmd, from-segments-to-density.Rmd
docs/                this documentation set
man/                 roxygen-generated
```

This is the layout as planned. The reading and effort files later moved to
`narwcr`. On 2026-11-12 the pipeline files were renamed with step numbers
(`R/01-prepare.R` to `R/13-detection-data.R`); the current list is in
`docs/10-code-guide.md`, Section 2.

## 5. Target API

```r
dat  <- read_narwc("survey.csv")
iss  <- validate_narwc(dat)                  # a report, never an error
segs <- segment_survey(dat, seg_length = 5, seed = 1)

segs$segments    # one row per segment
segs$sightings   # one row per segment per species
segs$tracks      # one row per continuous track
segs$points      # point-level data with segment assignments
```

Every function returns objects. Nothing is written to disk implicitly; output
is handled by a separate `write_segments()`.

## 6. Grounding in the handbook

The handbook's code books are encoded as data in `R/narwc-codes.R`. Validation,
effort determination, and sighting filtering read permitted values from this one
place, not from numeric literals spread through the pipeline.

| Variable | Handbook section | Used for |
|---|---|---|
| `LEGTYPE` | 8.A.21 | On-effort determination; only `2` is a census track |
| `LEGSTAGE` | 8.A.20 | Circling detection; excluding non-observer and photographic sightings |
| `IDREL` | 8.A.16 | Sighting reliability filter |
| `VISIBLTY` | 8.A.38 | Effort determination, with two encodings in one column |
| `LAT_DD` / `LONG_DD` | 8.A.18, 8.A.22 | Event position, with alias handling |
| `STRIP`, `S_LAT`, `S_LONG` | 8.A.31, 8.A.33, 8.A.34 | Carried through, not interpreted in v1 |
| `TAXCODE`, `STRATUM` | 8.A.36, 8.A.30 | Validation only |

## 7. Verification plan

| # | Criterion |
|---|---|
| 1 | `R CMD check --as-cran` with no errors and no warnings. |
| 2 | A `testthat` suite covering at least: effort conservation, segment lengths within the tolerance band, seed reproducibility, legacy visibility handling, retention of the last track, track splitting at effort breaks, midpoint placement, sighting filters, and empty input. |
| 3 | A vignette that knits end to end from the bundled fixture. |

All three are met. Results are in [04-verification.md](04-verification.md).

## 8. Out of scope for v1

- Detection-function fitting (`Distance::ds` wrappers, multi-year fitting).
- `STRIP` to right-angle-distance conversion. The handbook defines two interval
  code books, CETAP and NLPSC/MassCEC, and which applies depends on the platform
  and the year. This belongs with the detection-function work.
- Copernicus and other covariate access.
- Mapping and plotting.
- GAM/DSM fitting.

See [05-next-steps.md](05-next-steps.md).

## 9. References

The method, the statistical framework it serves, and the data-format
specification are set out in [06-references.md](06-references.md). That chapter
also states which parts of the algorithm come from the published methods and
which are properties of Becker's implementation. Full citations are there.
