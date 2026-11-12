# Next steps

*C. H. Ross. 2026-11-12. Distributed with the package source.*

## 1. Scope

This chapter lists what v1 does not do, roughly in the order it is worth doing
(Section 2), and the design of the detection-function support (Section 3).
Section 4 records what is deliberately out of scope. Completed items are kept
and marked done, with where the work now lives.

Other chapters cite items by number (for example "item 2"); the numbers are
stable.

## 2. Planned items

| Item | Topic | Status |
|---|---|---|
| 1 | Validate against a real NARWC extract | open; real extracts have been read (see item) |
| 2 | Documented profile for the CCS Cape Cod Bay format | open; `anchor` argument not built |
| 2b | Columns from other survey programmes | done |
| 3 | Detection functions | mostly done; multi-year fitting open |
| 4 | Covariates and density surface models | open; separate package |
| 5 | Mapping | partly done; tile basemaps out of scope |
| 6 | Smaller items | done |

### Item 1. Validate against a real NARWC extract

The highest-value next step, and the cheapest.

Everything in v1 is verified against a synthetic fixture built from the
handbook's worked example. That checks the logic. It cannot surface what real
archives contain: codes outside the handbook, `LEGSTAGE` sequences that do not
close, duplicated events, time zones that shifted mid-season, and `LEGNO`
values that repeat across blocks.

With one real file:

```r
dat <- read_narwc("path/to/extract.csv")
issues <- validate_narwc(dat)
issues[, c("check", "severity", "column", "n")]
```

Then compare `segment_survey()` output against segments from a previous run of
the original scripts. Any difference should be attributable to a numbered
defect in [03-bug-fixes.md](03-bug-fixes.md); any that is not is a finding.

**Status (2026-11-12):** partly done. Real extracts have since been read, and
the reader changes that followed are recorded in `NEWS.md`, "Reading real
extracts". The comparison against output from the original scripts has not
been made.

### Item 2. A documented profile for the CCS Cape Cod Bay format

The processed "ready for model" CSV the original scripts consumed is not raw
NARWC. It carries columns that are not handbook Table 1 variables and that are
computed nowhere in `original/`: every occurrence of each is a `filter()` or a
`select()`, with no assignment. They arrive already set.

**Source (Camille, 2026-08-10):** `Tr_SIGHTING` and the `IS_*` columns are
**specific to the Center for Coastal Studies (CCS) aerial survey programme of
Cape Cod Bay**. They are an artifact of the CCS survey design, not of NARWC and
not of any general pipeline.

| Column | Meaning | Source | Used for |
|---|---|---|---|
| `Tr_SIGHTING` | Whether the sighting was made from the track-line | **CCS** | **load-bearing**; see below |
| `IS_LAT`, `IS_LONG`, `IS_SPECCODE` | **Initial sighting**: the *aircraft's* position on the track-line at first detection, and the species. Distinct from the circle position in `LATITUDE`/`LONGITUDE` | **CCS** | the distance calculation |
| `LEGTYPE_BK` | Kenney's `LEGTYPE`, alongside a different `LEGTYPE` | unconfirmed | aliased to `LEGTYPE` |
| `Effort_Type` | An upstream effort classification | unconfirmed | carried only |
| `OBSSIGHT` | An observer sighting flag | unconfirmed | carried only, never acted on |
| `Date_UTC`, `Time_UTC` | Date and time, already in UTC | unconfirmed | carried only |

#### `IS_*` is not `S_LAT`/`S_LONG`

An earlier version of this chapter guessed that `IS_LAT`/`IS_LONG` were the
handbook's `S_LAT`/`S_LONG`. That was wrong twice: they are neither that column
nor a position of the animal. Their actual meaning, and why it is useful, is
below.

#### `Tr_SIGHTING`

`compute_distance.R:15` and `:18` gate **the entire distance calculation** on
`Tr_SIGHTING == 1`. With the column identified, the consequence is clear: the
original pipeline **silently required CCS-format input.** On a NARWC extract
from any other programme the column is absent and the filter errors. Worse, if
another pipeline supplies a column of that name with a different meaning, it
runs and returns the wrong subset. With the `"RIWH" %in% ...` day filter at
line 13, the set of sightings that ever received a distance was fixed by two
conditions, one of them a survey-programme artifact. See defect 15 in
[03-bug-fixes.md](03-bug-fixes.md).

`distsamp` does not use it. Eligibility comes from handbook columns only, so
the distance code runs on data from any programme. `Tr_SIGHTING` encodes the
same intent, so it remains useful as a *cross-check* on eligibility where it
exists, but it cannot be the mechanism.

#### What is still unknown

`LEGTYPE_BK`, `Effort_Type`, `OBSSIGHT`, `Date_UTC`, and `Time_UTC` have not
been attributed. `OBSSIGHT` is the least recoverable. It appears five times,
all in `select()`, and is never filtered on or assigned, so its meaning cannot
be inferred from its use.

v1 treats all of these as optional pass-through columns. `LEGTYPE_BK` is
aliased to `LEGTYPE`; the rest survive if named in `extra_columns`. This works
by arrangement, not by design. `read_narwc(profile = "ccs")` could map them
properly given a data dictionary.

#### `IS_*` is a better anchor, not a better animal position

**Settled: `IS_LAT`/`IS_LONG` is the *aircraft's* position on the track-line at
initial sighting**, not the animal's. A CCS row therefore carries both ends of
the measurement: the track-line point at detection in `IS_*`, and the circle
position in `LATITUDE`/`LONGITUDE`. `compute_distance.R:23` takes the distance
between them.

This maps directly onto `circling_distance()` and improves it. The package
currently anchors a circling sighting on the `LEGSTAGE == 3` break-off record.
`IS_*` gives **the point of detection instead of the point of turning**. That
is strictly better, because the aircraft flies some distance past a group
before it begins the turn. The animal's position still comes from the circle
record, so the orbit-radius caveat in step 11e of
[02-implementation.md](02-implementation.md) is unaffected.

The CCS distance is still *radial* (track-line point straight to the animal),
so defect 15 stands, and the projection `circling_distance()` performs is still
the improvement. The two changes compose: a better anchor, and a perpendicular
instead of a radial distance.

**To build:** an `anchor` argument on `circling_distance()` that accepts an
explicit pair of position columns. A CCS file would supply `IS_LAT`/`IS_LONG`;
anything else falls back to the break-off record. Blocked on a real CCS file to
verify the column semantics end to end. The reading above is confirmed, but no
file has been seen.

### Item 2b. Handling columns from other survey programmes: done

`narwc_profiles()`, `read_narwc(profile = )`, and the
`columns_outside_handbook` check cover the general case. Unrecognised columns
are reported by name, not silently dropped, and are attributed to a survey
programme where one is recognised. Step 1b of
[02-implementation.md](02-implementation.md) gives the reasoning, including why
a profile is never applied automatically.

CCS is the only registered profile, and is **an exception, not a
representative case**. Adding a programme needs its column list and a data
dictionary, which is usually the missing part: a column's meaning cannot be
inferred from its name. Entries whose meaning was guessed are marked
`confidence = "unconfirmed"` and should stay so until someone who ran the
survey confirms them.

`DataExploration.R:52` and `:71` `tidyr::fill()` `LEGTYPE`, `LEGSTAGE`,
`LEGNO`, `VISIBLTY`, `BEAUFORT` and others in both directions
(`.direction = "downup"`) before use. That propagates a sea state or leg number
backwards in time across arbitrary gaps. Whether this is appropriate depends on
how the upstream file records those variables, and should be settled before
that profile is written.

### Item 3. Detection functions

Perpendicular distances are computed from the `ANGLEL`/`ANGLER` declination
angles (handbook 8.A.2) and returned in `segs$detections`. Fitting a detection
function means handing that table to `Distance::ds()`. Status of the parts:

- ~~**`STRIP` to right-angle distance.**~~ Done: `narwc_strip_bins()` and
  `strip_distance()`.
- ~~**Exact sighting positions.**~~ Done: `exact_distance()`, which projects
  onto the trackline instead of measuring radially as
  `original/compute_distance.R` did.
- ~~**Truncation and binning.**~~ Moved to
  [`dsfit`](https://github.com/chross22/dsfit) and built there. Truncation is
  one value per sweep, not a column. Binned fitting uses `mrds`'s binned
  likelihood, with guards on bins that do not tile or do not reach the
  truncation. This is fitting-side, so it belongs to the middle layer.
- Open: the multi-year fitting from
  `original/detectionFunctionMultipleYears.R`. Not a wrapper around
  `Distance::ds()`; see Section 3.

A caution carried over from the original: `detection_function.R:10` filters
`CIRCLE != 1`, which drops rows where `CIRCLE` is `NA` as well as where it is
1. Use `!(CIRCLE %in% 1)`.

### Item 4. Covariates and density surface models

`original/access_covars.R` and `accessCopernicus.py` fetch Copernicus Marine
products; `load_covars.R` reads them; `integrated_gam_development.CHR.R` fits
the GAMs (generalised additive models). These belong in a separate package.
They share no data structures with segmentation beyond the segment midpoints,
and they carry a heavy dependency stack (`terra`, `marmap`, `copernicus`,
`ncdf4`) that would otherwise be imposed on every user who only wants to cut
segments.

`segments_as_sf(segs, "midpoints")` is the intended handoff point.

### Item 5. Mapping: partly done

`plot()` methods on `distsamp_segments` cover the diagnostic views, behind
`Suggests` on `ggplot2`: the track with segment midpoints and sightings, tracks
coloured by `new_trackno`, segment lengths against the target, and the
distribution of perpendicular distances. They return `ggplot` objects instead
of writing PNGs to a directory.

Coastlines are available: `plot(segs, coastline = TRUE)` draws Natural Earth
land under the track. `coastline` also accepts the user's own `sf` object,
which is the right choice at bay scale. Natural Earth's medium coastline is
1:50m, coarse enough that a survey along the shore appears to run over land.

Still missing, by decision: **tile basemaps**. `original/map_utils.R` contains
a substantial reimplementation of `ggspatial::annotation_map_tile` worth
preserving, but it needs a tile source and network access, which a diagnostic
plot should not. `segments_as_sf()` remains the handoff for anyone building a
publication map.

### Item 6. Smaller items

- ~~**Effort summaries per survey line.**~~ **Done:** `line_effort()` and
  `reflight_summary()`. Two defects came with the port. The original reduced on
  the *occupation* id, not the line id, so it did not combine re-flights at
  all, which was its only purpose. Its re-flight percentage measured the share
  of occupations that were repeats, not the share of lines re-flown. Both rates
  are now reported, each named for what it measures.
- ~~**A `Distance`-shaped export.**~~ **Done:** `detection_data()`.
- ~~**`LEGSTAGE` sequence validation.**~~ **Done:** `legstage_sequence`,
  `legstage_break_off_unresumed`, and `legstage_line_not_closed`. The last is a
  note, not a warning, because a line abandoned for weather legitimately has no
  end-line; the fixture contains one.
- ~~**Performance on a full season.**~~ **Done.** Profiled on synthetic seasons
  up to 242k records: linear throughout, about 12 seconds for a quarter of a
  million records since 2026-11-12 (20 seconds before). One quadratic term in `attach_circling_sightings()` was found
  and removed; it appeared only at high circling rates, which right whale
  surveys have. Numbers and method are in
  [04-verification.md](04-verification.md); the generator is
  `data-raw/make-season.R`.

## 3. Detection function: design decided, partly built

Settled 2026-08-10. Two decisions frame the rest.

**Build it general.** Support all three distance sources, since the data era
is not yet fixed.

**Data preparation only.** `distsamp` does not wrap `Distance::ds()`.
`Distance` is mature and well documented; a wrapper hides its options and
falls out of step with it. What `distsamp` offers instead is NARWC-specific
knowledge: which `STRIP` code book applies, that the Skymaster has a blind
spot, that a circling position is not a perpendicular distance.

### 3.1 Three sources, three eras

| source | era | gives | state |
|---|---|---|---|
| `ANGLEL`/`ANGLER` | 2022+ (NEAQ) | point distance, `ALT / tan(angle)` | **done**, wired into `sighting_distances()` |
| `STRIP` | pre-2022 | interval | **done**, ~~not yet wired in~~ wired in: `sighting_distances(sources = )`, `R/04-distances.R:201`, `:329` (Section 3.3, item 1) |
| `S_LAT`/`S_LONG` | 2011+ (NLPSC/WEA) | point distance from exact position | **done**, ~~not yet wired in~~ wired in: `sighting_distances(sources = )`, `R/04-distances.R:201` (Section 3.3, item 1) |

### 3.2 Done

`narwc_strip_bins()` and `strip_distance()` encode both code books from
handbook 8.A.31. They resolve the scheme from the survey date (CETAP before
October 2011, NLPSC after), branch on aircraft where the CETAP bins differ, and
optionally apply the Skymaster blind-spot offset.

The stakes: `STRIP` code 13 means **1-2 nmi** under CETAP and **over 4 nmi**
under NLPSC. Code 5 differs by a factor of two. Reading a code with the wrong
book silently produces wrong distances, and nothing downstream would detect it.

`exact_distance()` computes the perpendicular distance from `S_LAT`/`S_LONG` to
the trackline, using `gc_bearing()`, `track_bearing()`, and
`cross_track_distance()`. It *projects onto the track* instead of measuring
straight to the animal as `original/compute_distance.R` did. A radial distance
exceeds the perpendicular one by however far the aircraft was from abeam,
always in the same direction, and biases density low. The along-track offset is
returned with the distance so the size of that correction is visible, not
assumed away. Details and the four judgement calls are in
[02-implementation.md](02-implementation.md), step 11d.

A fourth source was added after the first three. `circling_distance()` ties a
sighting logged during a circle back to the `LEGSTAGE == 3` break-off record on
the census line and measures from there. These are real on-effort detections:
the animal was seen from the track-line, which is why the aircraft left it.
Dropping them thins the near-zero end of the distance distribution, where a
detection function is most sensitive. But the position is fixed minutes after
detection, so the animal has moved. They are a *separate and weaker* source,
not more of the same. Step 11e of [02-implementation.md](02-implementation.md)
gives the reasoning.

### 3.3 Remaining

1. ~~**Unify the sources in `sighting_distances()`**~~: **done.** `sources` is
   a precedence order over `"angle"`, `"exact"`, `"strip"`, `"circling"`.
   `distance_source` records which source claimed each row, and
   `distbegin`/`distend` carry the interval for binned rows. Circling is
   available but not on by default. Step 11f of
   [02-implementation.md](02-implementation.md).
2. ~~**`detection_data()`**~~: **done.** It returns the `Distance` flatfile:
   `Region.Label` / `Area` / `Sample.Label` / `Effort` / `object` / `distance` /
   `size`, with `distbegin`/`distend` for binned rows and segment covariates on
   request. `area` is required, with no default. Every segment appears,
   including those with no detections, because that is how the flatfile records
   effort that produced nothing. Truncation drops detections and keeps their
   segments. Point and interval distances in one table is an error by default,
   and open top bins are dropped. `include_circling` defaults to `FALSE` and
   does not change the segment counts; the density-surface side stays on
   `segment_survey(circling = )`.
3. ~~**Left truncation** for the Skymaster blind spot~~ and ~~**a `g(0)`
   correction slot**~~: **moved to
   [`dsfit`](https://github.com/chross22/dsfit).** Both are fitting-side, and
   [07-fitting-architecture.md](07-fitting-architecture.md) puts fitting in the
   middle layer. Left truncation is built there as `sweep_models(left = )`. It
   warns when combined with a gamma key, because the two model the same
   phenomenon and together count the blind spot twice. The `g(0)` slot is the
   top of `dsfit`'s own remaining list. Both are tracked in
   [dsfit's docs/01-plan.md](https://github.com/chross22/dsfit/blob/main/docs/01-plan.md),
   not here, so that one list owns each item.

## 4. Deliberately out of scope

### 4.1 g(0)

`g(0)` is the probability of detecting an animal on the trackline. Aerial
surveys of whales suffer availability bias (animals submerged) and perception
bias (observers missing animals at the surface). A detection function fitted
without correcting for either assumes `g(0) = 1` and biases density low, badly
for a deep-diving species. `distsamp` should not estimate `g(0)`, but it must
not let a user assume it away either. Whatever `detection_data()` returns
should say so in its documentation.

**Done:** `?detection_data` has the section "This assumes g(0) = 1, and it
almost certainly is not" (`R/13-detection-data.R:69`), and the report printed by
`detection_data()` ends with "g(0) = 1 is assumed" (`R/13-detection-data.R:309`;
`NEWS.md`, "One table for `Distance`").

The full treatment is in
[07-fitting-architecture.md](07-fitting-architecture.md) section 5. In short,
three separate effects present as `g(0) < 1`: the geometric blind spot,
availability, and perception. Only the first is recoverable from a NARWC
extract. Availability needs external dive data; perception needs a
double-observer protocol the standard extract does not record. The design is
therefore a correction the analyst *supplies*, with its standard error
propagated and its components named separately, not an estimator. Correcting
for one component while believing another has been corrected is how these
estimates go wrong by a factor rather than a percentage.

### 4.2 Where fitting lives

Settled in [07-fitting-architecture.md](07-fitting-architecture.md): three
layers, with detection-function and DSM (density surface model) fitting in a
separate package and the analysis itself in a `targets` repository. `distsamp`
stops at `detection_data()` and `segments_as_sf()`.

## 5. References

Full citations: [06-references.md](06-references.md).
