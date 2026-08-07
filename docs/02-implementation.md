# Implementation notes

How each stage of the pipeline was built, what it replaces in `original/`, and
why it works the way it does. Read alongside [03-bug-fixes.md](03-bug-fixes.md),
which covers the defects corrected on the way.

The pipeline in order:

```
read_narwc  ->  validate_narwc         (report only, not a gate)
     |
make_leg_id  ->  flag_circling  ->  flag_effort  ->  point_to_point_effort
     |
split_tracks  ->  track_effort  ->  plan_segments  ->  cut_segments
     |
attach_circling_sightings  ->  segment_midpoints  ->  segment_sightings
     |
                        distsamp_segments
```

---

## Step 1 — `read_narwc()`

**File:** `R/read-narwc.R`
**Replaces:** the column selection and renaming scattered through
`ds_data_prep_dmr.R` and `DataExploration.R`.

Does four things and nothing else:

1. **Alias renaming.** The handbook's canonical event position is
   `LAT_DD`/`LONG_DD` (8.A.17, 8.A.21), but the extracts the database manager
   distributes — and all of `original/` — use `LATITUDE`/`LONGITUDE`. The
   package standardises internally on `LATITUDE`/`LONGITUDE` and accepts either
   on input, along with `LEGTYPE_BK`, `EVENT`, and a handful of other spellings
   seen in the upstream Maine DMR files. An alias never overwrites a column that
   is already correctly named.
2. **Column selection.** Recognised columns plus anything named in
   `extra_columns`. Passing `extra_columns = NULL` keeps everything, which is
   the escape hatch for upstream pipelines that carry derived columns like
   `Effort_Type`, `Tr_SIGHTING`, or `IS_LAT`.
3. **Missing-value normalisation.** NARWC writes `"."` for missing. Everything is
   read as character first, `"."` and `""` are blanked, and only then are the
   numeric columns coerced — otherwise a single `"."` turns a whole column into
   `NA` with a warning.
4. **`DATE` derivation** from `YEAR`/`MONTH`/`DAY`.

It deliberately does **not** filter, repair, or reject anything. The original
began by dropping rows with `LEGNO == "."`; here that is a validation finding,
and the decision about what to do with it is yours.

## Step 2 — `validate_narwc()`

**File:** `R/validate.R`
**Replaces:** nothing. There was no validation.

Returns a tibble of findings — `check`, `severity`, `column`, `n`, `rows`,
`message` — and never stops. A zero-row result means everything passed. Ten
checks, each traceable to a handbook statement:

| Check | Severity | Basis |
|---|---|---|
| `missing_required` | error | Segmentation is impossible without it |
| `missing_values` | error | `NA` in a required column |
| `unknown_code` | warning | Value outside the code book for `LEGTYPE`, `LEGSTAGE`, `IDREL`, `TAXCODE`, `STRATUM` |
| `legstage_off_census` | note | 8.A.19: `LEGSTAGE` is recorded only during `LEGTYPE == 2`, except code 7 |
| `sighting_at_boundary` | warning | 8.A.19, 4.2: sightings should not occur at `LEGSTAGE` 1, 3, 4, or 5 |
| `eventno_not_increasing` | warning | Repeats are legal (4.2 assigns one event several sightings); decreases mean mis-sorted records |
| `bad_time_format` | warning/note | 8.A.36: six-digit `hhmmss` |
| `coordinates_out_of_range` | error | Latitude and longitude bounds |
| `positive_west_longitude` | warning | 8.A.21: west longitudes must be negative |
| `sighting_without_number` | warning | 8.A.23: `NUMBER` required for all sightings |

`positive_west_longitude` is worth singling out. It fires only when *every*
longitude in the file is positive, which in a western North Atlantic dataset can
only mean the sign convention was lost somewhere upstream. It is the kind of
error that produces a plausible-looking analysis of the wrong ocean.

## Step 3 — `make_leg_id()`

**File:** `R/effort.R`
**Ports:** `ds_data_dmr.R:28-35`.

A `LEGNO` can be started, abandoned for fog, and picked up hours later. Treated
as one line, the point-to-point distance would leap from the end of the first
stretch to the start of the second and count that as effort. `LEGNO3` pastes
`LEGNO` to a run-length index so the two stretches stay separate.

The original built this with `rle()` inside a `group_by()`, which is fragile
because `rle()` does not handle `NA` as a value. `rle_id()` in `R/utils.R` maps
`NA` to a sentinel string first.

## Step 4 — `flag_circling()`

**File:** `R/circling.R`
**Replaces:** `DataExploration.R:54`, `CIRCLE = if_else(LEGTYPE == 4, 1, 0)`.

Two signals, either sufficient:

- `LEGTYPE == 4` — the "other (circling)" code (8.A.20); and
- any record between a `LEGSTAGE == 3` (break off line to circle) and the
  following `LEGSTAGE == 4` (resume line), within the same line occupation
  (8.A.19).

The second matters because a survey may log positions during circling without
changing `LEGTYPE`. The break-off and resume records themselves stay at
`LEGTYPE == 2` and are correctly *not* marked as circling — the aircraft is
still on the line at those instants.

## Step 5 — `flag_effort()` and `visibility_ok()`

**File:** `R/effort.R`
**Ports:** `ds_data_prep_dmr.R:79-91`.

A record is on effort when `LEGTYPE` is in `legtype_on_effort` (default `2`),
`BEAUFORT <= max_beaufort` (default 3), `ALT < max_alt_m` (default 366 m =
1,200 ft), and visibility clears `min_visibility_nmi` (default 2 nmi, the CETAP
standard). Every threshold is an argument; the original hard-coded all four. A
criterion whose column is absent is skipped with a message rather than silently.

Records are **not** removed. Off-effort records are needed for correct distance
accounting and for attaching circling sightings back to their segments. The
original carried a shouted comment to this effect at
`ds_data_prep_dmr.R:93-94`; here it is a property of the design.

`visibility_ok()` is the interesting part, and is documented at length in
[03-bug-fixes.md](03-bug-fixes.md#1-legacy-visibility-codes-silently-discarded-all-pre-2004-effort).
`VISIBLTY` carries two encodings in one column and a plain `>= 2` comparison
gets every legacy record wrong.

## Step 6 — `gc_distance()` and `point_to_point_effort()`

**File:** `R/geodist.R`
**Ports:** `ds_data_dmr.R:62-98` (`dist.rdk`, `fn.grcirclkm`) and the triple
nested loop at `ds_data_dmr.R:112-207`.

Three selectable methods:

| Method | Aliases | What it is |
|---|---|---|
| `haversine` | — | Haversine on a 111.12 km/degree sphere. **Default.** |
| `becker` | `eab` | Becker's `segchopr` `fn.grcirclkm`: law of cosines, 60 nmi/degree x 1.852 km/nmi |
| `kenney` | `rdk` | Kenney and Winn (1986): law of cosines, 111.12 km/degree |

`dist_methods()` prints the table at runtime. Becker and Kenney return bit-identical
values, for the reason given in
[03-bug-fixes.md](03-bug-fixes.md#the-becker-and-kenney-methods-are-the-same-formula);
haversine is the default because it is numerically stable at the short ranges
between consecutive survey records, which is where the law of cosines loses
precision.

All three are vectorised. The original called its distance function once per row
inside three nested loops over survey, line, and record; on a season of
computer-logged data that is the dominant cost of the whole pipeline.

`point_to_point_effort()` computes, within each line occupation, the distance
from each record to the next *when both are on effort*, and `0` otherwise —
never `NA`, so segment sums are well defined without `na.rm`. Effort is
attributed to the first record of each pair, so the last record of a line
carries `0`.

## Step 7 — `split_tracks()` and `track_effort()`

**File:** `R/tracks.R`
**Ports:** `create_new_track_nos.R`.

A new track begins when the line occupation changes, or when effort breaks. A
break means **two or more consecutive off-effort records** — a single off-effort
record between two on-effort ones is smoothed over, so a momentary excursion
logged as one point does not fragment the track.

The original walked rows with a six-branch `if`/`else` chain; the replacement is
the same rule expressed as three vector operations
(`R/tracks.R:track_index()`). One behavioural improvement is described in
[03-bug-fixes.md](03-bug-fixes.md#7-a-break-in-effort-produced-one-spurious-track-per-record).

`track_effort()` totals effort per track and drops tracks under `min_track_km`
(default 1 km).

## Step 8 — `plan_segments()`

**File:** `R/segments.R`
**Ports:** `compute_num_segs.R`.
**Method:** Becker et al. (2010), *MEPS* 413:163–183, `doi:10.3354/meps08696`.
See [06-references.md](06-references.md#the-segmentation-method), including what
the published methods do and do not cover.

For a track of length `L` and target `s`, with tolerance `t = seg_tol_frac * s`
(default `0.5 * s`):

- `L < s` gives one segment of length `L`.
- Otherwise `floor(L / s)` whole segments fit, leaving `rem`.
- `rem >= t`: it is big enough to stand alone and becomes an extra segment.
- `rem < t`: it is absorbed instead, stretching one segment to `s + rem`.

Either way the leftover lands on a **randomly chosen** segment, so the odd
segment is not systematically at the end of every track. Target lengths always
sum to `L` exactly — asserted for eight track lengths in
`test-segments.R`.

## Step 9 — `cut_segments()`

**File:** `R/segments.R`
**Ports:** `chop_to_size.R`.

Walks each track's records, accumulating effort until the cut point is reached.
Because a survey record is never split, a segment rarely lands exactly on its
target: the function finds the first record at which cumulative effort reaches
the target, then flips a coin — heads, include it and run slightly long; tails,
exclude it and run slightly short. Over many segments the errors cancel rather
than biasing every segment long.

Two things changed from the original beyond bug fixes:

- **Cut points are measured from the start of the track**, not from wherever the
  previous segment happened to end, so per-segment rounding does not accumulate.
  See [03-bug-fixes.md](03-bug-fixes.md#8-cutting-error-accumulated-into-the-final-segment).
- The `add_row()` spacer rows the original inserted between segments, and the
  `fill()` block that compensated for them, are gone. That block
  (`chop_to_size.R:144-152`) computed `dat_chopped_temp` and then never used it;
  the function returned the unfilled `dat_chopped`. It was dead code.

The `case` column is kept, with the original's diagnostic labels: `case2` (first
record alone met the target), `case3` (several records, coin flip decided),
`case4` (not enough effort left), `case5` (last segment, absorbed the remainder).
`case1` is gone — it marked an empty group, which the cursor-based walk cannot
produce.

## Step 10 — `attach_circling_sightings()`

**File:** `R/circling.R`
**Ports:** `process_obs_data.R:44-106`.

A group sighted from the census track is often circled for photographs, and the
position recorded for it is the one taken during circling, off effort. Dropping
those loses detections that genuinely arose from on-effort search.

Three modes:

- `"none"` — drop them.
- `"same_species"` (**default**) — attach a circling sighting to the preceding
  segment only if that segment already holds an on-effort sighting of the same
  species.
- `"all"` — attach every circling sighting to the preceding segment.

The default implements the CETAP rule stated in handbook 4.2 (event 11): counted
with the original on-effort group are further individuals *of the same species*
seen while circling; groups of *other* species not originally seen from the
track-line are new off-effort sightings and do not belong to the segment. The
original instead hard-coded right whales, attaching every circling right whale
and discarding circling sightings of everything else
(`process_obs_data.R:49-50`).

Attached records get `pt2pt.effort = 0`, so attaching a sighting can never change
how long a segment is. That invariant is asserted in the test suite.

## Step 11 — `segment_midpoints()`

**File:** `R/midpoints.R`
**Status:** written from scratch. `calculate_midpoint()` was `source()`d at
`chop_segments.R:16` and called at `chop_segments.R:109`, but exists nowhere.

The midpoint is the position **half of the segment's effort along the track**:
walk the cumulative point-to-point distance to half the segment length, then
interpolate along the great circle between the two records that bracket it, via
`gc_interpolate()` (spherical linear interpolation).

The alternative — averaging the coordinates of the segment's records — is worse
in a way that matters. It is pulled towards wherever records happen to be dense,
which on computer-logged data means towards wherever the aircraft slowed down;
and on a curved or dog-legged track it can fall off the line entirely. The
along-track midpoint is on the track by construction and is weighted by distance
rather than by record count. `test-tracks-midpoints.R` builds a segment with its
records deliberately bunched at one end and asserts the two disagree.

The mid-point is the conventional place to sample habitat covariates in this
family of models. Becker et al. (2019) describe covariates "derived based on the
segment's geographical mid-point", with SST and depth standard deviations taken
over a 3 x 3-pixel box around it — so the accuracy of this coordinate propagates
directly into the covariates a density surface model is fitted on.

## Step 12 — `segment_sightings()`

**File:** `R/sightings.R`
**Ports:** `process_obs_data.R:57-160`.

Counts sightings and animals per segment per species, and summarises conditions.

Default exclusions, each with a handbook basis:

- `LEGSTAGE == 6` — sighting by anyone other than an on-duty observer. Handbook
  4.2 is explicit that a pilot sighting "cannot be included in a density
  estimate". **The original kept these** (`ds_data_dmr.R:259` excluded only
  `LEGSTAGE != 7`).
- `LEGSTAGE == 7` — sighting found afterwards in a vertical photograph (8.A.19).
- `IDREL` of 1 (possible) or 9 (unknown) — 8.A.15 records Kenney's own practice
  of using only definite and probable identifications.

All three are arguments.

Two Beaufort summaries are produced: `mean_beaufort`, the plain mean over
records, and `wt_beaufort`, weighted by the distance each record covers. Prefer
the weighted one as a detection covariate — a sea state recorded over 3 km should
not count the same as one recorded over 200 m. `weighted_mean_safe()` falls back
to the plain mean when every weight is zero, which happens on a segment whose
records share a position.

## Step 13 — `segment_survey()` and output

**Files:** `R/segment-survey.R`, `R/spatial.R`

`segment_survey()` runs steps 3 to 12 and returns a `distsamp_segments` object:
`segments`, `sightings`, `tracks`, `points`, plus the `call` and `settings`.
Steps 3 to 5 are skipped when the input already carries `LEGNO3`, `CIRCLE`, or
`OnOff.Effort`, so you can substitute your own definitions.

Both random choices run inside a single `withr::with_seed()` block, so one seed
fixes the whole segmentation. `with_optional_seed()` uses
`withr::with_preserve_seed()` when no seed is given, so the calling session's RNG
stream is never disturbed either way — asserted in the test suite.

Supporting output:

- `segments_wide()` — one count column per species, the shape `dsm` expects.
  Missing combinations become `0`, not `NA`.
- `segments_as_sf()` — midpoints or per-segment `LINESTRING` geometry. `sf` is in
  `Suggests` and its absence is reported with an actionable message.
- `crop_to_bbox()` — replaces the undefined `crop_data()`. Handles data frames,
  `sf` objects, and whole `distsamp_segments` results, keeping the tables
  consistent with each other. Tolerates a box given with its corners reversed.
- `write_segments()` — the only function that writes to disk.

## Dependencies

`Imports`: dplyr, rlang, tibble, tidyr, utils, withr.
`Suggests`: knitr, rmarkdown, sf, testthat.

Dropped relative to `original/`: `geosphere` (replaced by `gc_distance()`),
`sp` (retired upstream), `stringr` (base string handling suffices), and the
mapping and covariate stack — `marmap`, `terra`, `copernicus`, `rosm`,
`ggspatial`, `rnaturalearth`, `doParallel` — none of which the segmentation core
needs.

All `library()` calls inside function bodies are gone; every external call is
namespaced.

## The test fixture

**Files:** `data-raw/make-fixture.R` (generator), `inst/extdata/narwc-example.csv`
(output, 113 records).

Built from the hypothetical survey in handbook Figure 2 (section 4.2), because
that is a case whose correct handling the handbook states explicitly. It contains
a transit with an off-effort sighting; survey lines with begin/continue/end
stages; two sightings sharing one `EVENTNO`; a pilot sighting at `LEGSTAGE 6`; a
cross-leg with a sighting; a break-off, five-record circling excursion, and
resume; a sighting at `LEGSTAGE 7`; a line abandoned when the sea state rises and
re-flown later; and a sighting at `IDREL 1`.

Geometry is deliberately simple: every line runs due north along a constant
meridian in 0.01-degree steps, so one step is exactly 1.1112 km and every
expected distance can be checked by hand. Total on-effort distance is 92.2296 km
across seven tracks.
