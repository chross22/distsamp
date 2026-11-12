# Implementation notes

*C. H. Ross. 2026-11-12. Distributed with the package source.*

## 1. Scope

This chapter describes how each pipeline stage was built, what it replaces in
`original/`, and why it works the way it does. The defects corrected on the way
are in [03-bug-fixes.md](03-bug-fixes.md).

Each stage is a numbered step. Step numbers are stable identifiers cited by
other chapters (for example "step 11d"); lettered steps were added after v1.
For each step, **File** gives the package source, and **Ports** or **Replaces**
gives the code in `original/` it supersedes. A *line occupation* is one
continuous flight along a `LEGNO`, identified by `LEGNO3` (Step 3).

## 2. Pipeline

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

## 3. Reading and checking the input

### Step 1 — `read_narwc()`

**File:** `R/read-narwc.R` at the time. Moved to `narwcr` on 2026-08-10 and re-exported (`R/00-reexports.R`).
**Replaces:** the column selection and renaming scattered through
`ds_data_prep_dmr.R` and `DataExploration.R`.

The function does four things:

1. **Alias renaming.** The handbook's canonical event position is
   `LAT_DD`/`LONG_DD` (8.A.18, 8.A.22). The extracts the database manager
   distributes, and all of `original/`, use `LATITUDE`/`LONGITUDE`. The package
   standardises internally on `LATITUDE`/`LONGITUDE` and accepts either on
   input, along with `LEGTYPE_BK`, `EVENT`, and other spellings seen in upstream
   processed files. An alias never overwrites a column that is already
   correctly named.
2. **Column selection.** Recognised columns are kept, plus anything named in
   `extra_columns`. `extra_columns = NULL` keeps everything. This is the escape
   hatch for upstream pipelines that carry derived columns such as
   `Effort_Type`, `Tr_SIGHTING`, or `IS_LAT`.
3. **Missing-value normalisation.** NARWC writes `"."` for missing. Everything
   is read as character first, `"."` and `""` are blanked, and only then are
   the numeric columns coerced. Otherwise a single `"."` turns a whole column
   into `NA` with a warning.
4. **`DATE` derivation** from `YEAR`/`MONTH`/`DAY`.

It does **not** filter, repair, or reject anything. The original began by
dropping rows with `LEGNO == "."`. Here that is a validation finding, and the
decision about what to do with it is the user's.

### Step 1b — `narwc_profiles()` and unrecognised columns

**File:** `R/profiles.R` at the time, plus changes to `read_narwc()` and `validate_narwc()`. Moved to `narwcr` on 2026-08-10 and re-exported (`R/00-reexports.R`).
**Replaces:** nothing. The original scripts assumed one survey programme's file
layout without saying so.

A NARWC extract is not the only form this data arrives in. Survey programmes
add their own derived columns, and a processed "ready for model" file may carry
a dozen that are not in handbook Table 1.

**The defect fixed here is in v1 of this package, not in `original/`.**
`read_narwc()` kept the handbook columns and discarded everything else without
a message:

```r
keep <- c(schema$required, schema$optional, extra_columns)
dat <- dat[, intersect(keep, names(dat)), drop = FALSE]
```

A CCS file lost `IS_LAT`, `IS_LONG`, and `Tr_SIGHTING` silently.
`extra_columns` was the escape hatch, but it required knowing in advance what to
name, and the columns most in need of attention are the ones not seen before.

**Current behaviour.** Dropped columns are reported by name, with the profile
they match, if any:

```
`read_narwc()` dropped 5 columns not in the NARWC handbook schema:
  Effort_Type, IS_LAT, IS_LONG, IS_SPECCODE, Tr_SIGHTING
4 of these are declared by the "ccs" profile (Center for Coastal Studies, Cape Cod Bay).
Keep them with `profile = "ccs"`; see `narwc_profiles()`.
```

`narwc_profiles()` is the registry: programme, column, meaning, the role
`distsamp` gives it, and how confident the meaning is. `validate_narwc()`
reports the same information as a `columns_outside_handbook` note, for data
frames that never went through `read_narwc()`.

| Decision | Reason |
|---|---|
| **Detection suggests, declaration acts.** A profile is never applied because a column name matched; `profile = "ccs"` is the caller's decision. | `Tr_SIGHTING` means "sighting made from the track-line" in a CCS file, and nothing stops another programme using the name for something else. A column name is not a contract between programmes. The same reasoning keeps `Tr_SIGHTING` out of the eligibility rule; see defect 15. |
| **Keeping is not interpreting.** `profile = "ccs"` carries the columns through and does nothing else. Every registry entry is currently `role = "passthrough"`. | The registry does not imply a capability that does not exist. |
| **Confidence is recorded per column.** `IS_LAT`, `IS_LONG`, and `Tr_SIGHTING` are `confirmed`; `OBSSIGHT` and the rest are `unconfirmed`, their meaning inferred from the name alone. | A guess is marked as a guess. The previous version of this documentation recorded `IS_LAT` as "presumably the handbook's `S_LAT`". That was wrong, and the error would have propagated into the distance code. |
| **A redundant alias is not reported as a loss.** A file with both `LAT_DD` and `LATITUDE` keeps the latter and discards the former; aliases whose canonical column survived are excluded from the message. | Reporting them would send the caller looking for information still present under another name. |

**Not yet done.** No profile column is interpreted. The case for doing so is
`IS_LAT`/`IS_LONG`, which give a better anchor for circling distances than the
break-off record; see [05-next-steps.md](05-next-steps.md) item 2.

### Step 1c — `fill_narwc()`

**File:** `R/fill.R` at the time. Moved to `narwcr` on 2026-08-10 and re-exported (`R/00-reexports.R`).
**Ports:** `DataExploration.R:52`, `:71`; `detectionFunctionMultipleYears.R:55`,
`:67`, `:76`.

NARWC data records a value once and leaves it blank until it changes. `LEGTYPE`
is entered as `2` at the start of a census line, and the rows beneath are empty
until the leg type changes. `BEAUFORT` stays as recorded until the sea state is
re-assessed. Downstream code needs the state each record was flown under, so
the blanks are filled.

The original did this:

```r
tidyr::fill(c("LEGTYPE", "LEGSTAGE", "LEGNO", "VISIBLTY", "BEAUFORT",
              "CLOUD", "GLAREL", "GLARER", "WX"), .direction = "downup")
```

The fill was **ungrouped**. No `group_by()` is near it, so it runs the length of
the file. The sea state from the last record of one survey day carries into the
first records of the next, and a leg number carries across a `FILEID` boundary
into a different survey. Neither is recoverable afterwards, because a filled
value is indistinguishable from a recorded one. `by` therefore defaults to
`FILEID` and `DATE`. A frame with neither column warns rather than filling
across everything.

The scripts also disagree with each other.
`detectionFunctionMultipleYears.R:55` fills the same nine columns with no
`.direction`, which means `"down"`. `DataExploration.R:52` uses `"downup"`.

| Decision | Reason |
|---|---|
| **State may be filled; measurements may not.** | `LEGTYPE` and `BEAUFORT` persist until something changes them, so a blank means "as above" and filling recovers information deliberately not repeated. A position, a time, a species, or a group size describes one moment; a blank means it was not taken, and filling it fabricates a measurement. |
| **Sighting columns are refused, not merely left out of the default.** `narwc_never_fill()` covers `SPECCODE`, `NUMBER`, `SIGHTNO`, `STRIP`, the angles, `S_LAT`/`S_LONG`, and the per-record identifiers. Asking to fill one is an error. | Carrying `SPECCODE` and `NUMBER` forward would copy a single group of three right whales onto every row until the next sighting, and every downstream count would be wrong by orders of magnitude. This failure would be the hardest to notice, because the result still looks like data. |
| **Backward fills are counted separately.** The report separates *carried forward* from *carried backward*. | `"downup"` fills down and then up, so it fills backwards only the values before the first recorded value in a group. That is still a guess about state that was never logged. Where a day begins on transit before the first `LEGTYPE` is entered, back-filling a `2` marks the transit as census effort. Only forward filling is recovery. |
| **`LEGSTAGE` is flagged as the least safe default.** The behaviour is documented and per-column counts are reported. | If a file records `1` (begin line) and leaves the continuation rows blank, filling down marks the whole line "begin line" instead of `2` (continue). On-effort eligibility is `LEGSTAGE == 2`, so that line drops out of every distance calculation. Whether this happens depends on the recording convention of the file, which cannot be settled without one. |

A regression test gaps the fixture: every value that repeats the row above,
within file and day, is blanked. The test asserts that filling restores the
fixture exactly, and that `segment_survey()` gives identical segments and
sightings either way.

### Step 2 — `validate_narwc()`

**File:** `R/validate.R`.
**Replaces:** nothing. There was no validation.

The function returns a tibble of findings (`check`, `severity`, `column`, `n`,
`rows`, `message`) and never stops. A zero-row result means every check passed.
Ten checks were defined in v1, each traceable to a handbook statement:

| Check | Severity | Basis |
|---|---|---|
| `missing_required` | error | Segmentation is impossible without it |
| `missing_values` | error | `NA` in a required column |
| `unknown_code` | warning | Value outside the code book for `LEGTYPE`, `LEGSTAGE`, `IDREL`, `TAXCODE`, `STRATUM` |
| `legstage_off_census` | note | 8.A.20: `LEGSTAGE` is recorded only during `LEGTYPE == 2`, except code 7 |
| `sighting_at_boundary` | warning | 8.A.20, 4.2: sightings should not occur at `LEGSTAGE` 1, 3, 4, or 5 |
| `eventno_not_increasing` | warning | Repeats are legal (4.2 assigns one event several sightings); decreases mean mis-sorted records |
| `bad_time_format` | warning/note | 8.A.37: six-digit `hhmmss` |
| `coordinates_out_of_range` | error | Latitude and longitude bounds |
| `positive_west_longitude` | warning | 8.A.22: west longitudes must be negative |
| `sighting_without_number` | warning | 8.A.24: `NUMBER` required for all sightings |

`positive_west_longitude` fires only when *every* longitude in the file is
positive. In a western North Atlantic dataset that can only mean the sign
convention was lost upstream. Uncaught, it produces a plausible analysis of the
wrong ocean.

Later checks (`exact_position_out_of_range`, `exact_position_far_from_event`,
`columns_outside_handbook`) are described with the steps that added them:
Step 11d and Step 1b.

## 4. Line occupations, effort, and tracks

### Step 3 — `make_leg_id()`

**File:** `R/effort.R` at the time. Moved to `narwcr` on 2026-08-10 and re-exported (`R/00-reexports.R`).
**Ports:** `ds_data_dmr.R:28-35`.

A `LEGNO` can be started, abandoned for fog, and resumed hours later. Treated
as one line, the point-to-point distance would jump from the end of the first
stretch to the start of the second and count the gap as effort. `LEGNO3` pastes
`LEGNO` to a run-length index so the two stretches stay separate.

The original built this with `rle()` inside a `group_by()`. That is fragile,
because `rle()` does not handle `NA` as a value. `rle_id()` in `R/utils.R` maps
`NA` to a sentinel string first.

### Step 4 — `flag_circling()`

**File:** `R/09-circling.R`.
**Replaces:** `DataExploration.R:54`, `CIRCLE = if_else(LEGTYPE == 4, 1, 0)`.

A record is circling if either signal holds:

- `LEGTYPE == 4`, the "other (circling)" code (8.A.21); or
- it lies between a `LEGSTAGE == 3` (break off line to circle) and the
  following `LEGSTAGE == 4` (resume line), within the same line occupation
  (8.A.20).

The second signal is needed because a survey may log positions during circling
without changing `LEGTYPE`. The break-off and resume records themselves stay at
`LEGTYPE == 2` and are *not* marked as circling: the aircraft is on the line at
those instants.

### Step 5 — `flag_effort()` and `visibility_ok()`

**File:** `R/effort.R` at the time. Moved to `narwcr` on 2026-08-10 and re-exported (`R/00-reexports.R`).
**Ports:** `ds_data_prep_dmr.R:79-91`.

A record is on effort when all of the following hold:

| Criterion | Argument | Default |
|---|---|---|
| `LEGTYPE` in the census set | `legtype_on_effort` | `2` |
| `BEAUFORT <= max_beaufort` | `max_beaufort` | 3 |
| `ALT < max_alt_m` | `max_alt_m` | 366 m (1,200 ft) |
| Visibility clears the minimum | `min_visibility_nmi` | 2 nmi (CETAP standard) |

The defaults are the CETAP criteria as stated by Kenney and Winn (1986, p. 347),
"observer(s) formally on watch, clear visibility of at least 2 miles, and sea
states of Beaufort 3 or lower". The altitude ceiling is set above the 750 ft
(229 m) at which CETAP surveys were flown (p. 346).

Every threshold is an argument; the original hard-coded all four. A criterion
whose column is absent is skipped with a message.

Records are **not** removed. Off-effort records are needed for correct distance
accounting and for attaching circling sightings back to their segments. The
original stated this in a capitalised comment at `ds_data_prep_dmr.R:93-94`;
here it is a property of the design.

`VISIBLTY` carries two encodings in one column, and a plain `>= 2` comparison
gets every legacy record wrong. `visibility_ok()` handles both; it is
documented in
[03-bug-fixes.md](03-bug-fixes.md#1-legacy-visibility-codes-silently-discarded-all-pre-2004-effort).

### Step 6 — `gc_distance()` and `point_to_point_effort()`

**File:** `R/03-geodist.R`.
**Ports:** `ds_data_dmr.R:62-98` (`dist.rdk`, `fn.grcirclkm`) and the triple
nested loop at `ds_data_dmr.R:112-207`.

| Method | Aliases | Definition |
|---|---|---|
| `haversine` | — | Haversine on a 111.12 km/degree sphere. **Default.** |
| `becker` | `eab` | Becker's `segchopr` `fn.grcirclkm`: law of cosines, 60 nmi/degree x 1.852 km/nmi |
| `kenney` | `rdk` | Kenney and Winn (1986): law of cosines, 111.12 km/degree |

`dist_methods()` prints the table at runtime. Becker and Kenney return
bit-identical values, for the reason given in
[03-bug-fixes.md](03-bug-fixes.md#the-becker-and-kenney-methods-are-the-same-formula).
Haversine is the default because it is numerically stable at the short ranges
between consecutive survey records, where the law of cosines loses precision.

All three methods are vectorised. The original called its distance function
once per row inside three nested loops over survey, line, and record. On a
season of computer-logged data that is the dominant cost of the whole pipeline.

`point_to_point_effort()` computes, within each line occupation, the distance
from each record to the next *when both are on effort*, and `0` otherwise. It is
never `NA`, so segment sums are defined without `na.rm`. Effort is attributed to
the first record of each pair, so the last record of a line carries `0`.

### Step 7 — `split_tracks()` and `track_effort()`

**File:** `R/07-tracks.R`.
**Ports:** `create_new_track_nos.R`.

A new track begins when the line occupation changes or when effort breaks. A
break is **two or more consecutive off-effort records**. A single off-effort
record between two on-effort ones is smoothed over, so a momentary excursion
logged as one point does not fragment the track.

The original walked the rows with a six-branch `if`/`else` chain. The
replacement expresses the same rule as three vector operations
(`R/07-tracks.R:track_index()`). One behavioural improvement is described in
[03-bug-fixes.md](03-bug-fixes.md#7-a-break-in-effort-produced-one-spurious-track-per-record).

`track_effort()` totals effort per track and drops tracks shorter than
`min_track_km` (default 1 km).

## 5. Segmentation

### Step 8 — `plan_segments()`

**File:** `R/08-segments.R`.
**Ports:** `compute_num_segs.R`.
**Method:** Becker et al. (2010), *MEPS* 413:163–183, `doi:10.3354/meps08696`.
See [06-references.md](06-references.md#the-segmentation-method), including what
the published methods do and do not cover.

For a track of length `L` and target `s`, the tolerance is
`t = seg_tol_frac * s` (default `0.5 * s`):

| Condition | Result |
|---|---|
| `L < s` | One segment of length `L`. |
| `L >= s` | `floor(L / s)` whole segments fit, leaving a remainder `rem`. |
| `rem >= t` | The remainder stands alone as an extra segment. |
| `rem < t` | The remainder is absorbed, stretching one segment to `s + rem`. |

In both remainder cases the leftover lands on a **randomly chosen** segment, so
the odd segment is not systematically at the end of every track. Target lengths
always sum to `L` exactly; this is asserted for eight track lengths in
`test-segments.R`.

### Step 9 — `cut_segments()`

**File:** `R/08-segments.R`.
**Ports:** `chop_to_size.R`.

The function walks each track's records, accumulating effort until the cut
point is reached. A survey record is never split, so a segment rarely lands
exactly on its target. The first record at which cumulative effort reaches the
target is found, and a coin is flipped: heads includes it and the segment runs
slightly long; tails excludes it and the segment runs slightly short. Over many
segments the errors cancel instead of biasing every segment long.

Two changes from the original, beyond bug fixes:

- **Cut points are measured from the start of the track**, not from wherever the
  previous segment ended, so per-segment rounding does not accumulate. See
  [03-bug-fixes.md](03-bug-fixes.md#8-cutting-error-accumulated-into-the-final-segment).
- The `add_row()` spacer rows the original inserted between segments, and the
  `fill()` block that compensated for them, are removed. That block
  (`chop_to_size.R:144-152`) computed `dat_chopped_temp` and never used it; the
  function returned the unfilled `dat_chopped`. It was dead code.

The `case` column keeps the original's diagnostic labels:

| Label | Meaning |
|---|---|
| `case2` | The first record alone met the target. |
| `case3` | Several records; the coin flip decided. |
| `case4` | Not enough effort left. |
| `case5` | Last segment; absorbed the remainder. |

`case1` is removed. It marked an empty group, which the cursor-based walk
cannot produce.

### Step 10 — `attach_circling_sightings()`

**File:** `R/09-circling.R`.
**Ports:** `process_obs_data.R:44-106`.

A group sighted from the census track is often circled for photographs, and the
position recorded for it is taken during circling, off effort. Dropping those
records loses detections that arose from on-effort search.

| Mode | Behaviour |
|---|---|
| `"none"` | Drop circling sightings. |
| `"same_species"` (**default**) | Attach a circling sighting to the preceding segment only if that segment already holds an on-effort sighting of the same species. |
| `"all"` | Attach every circling sighting to the preceding segment. |

The default implements the CETAP rule in handbook 4.2 (event 11). Further
individuals *of the same species* seen while circling are counted with the
original on-effort group. Groups of *other* species not first seen from the
track-line are new off-effort sightings and do not belong to the segment. The
original instead hard-coded right whales: it attached every circling right whale
and discarded circling sightings of all other species
(`process_obs_data.R:49-50`).

Attached records get `pt2pt.effort = 0`, so attaching a sighting never changes a
segment's length. The test suite asserts this invariant.

### Step 11 — `segment_midpoints()`

**File:** `R/10-midpoints.R`.
**Status:** written from scratch. `calculate_midpoint()` was `source()`d at
`chop_segments.R:16` and called at `chop_segments.R:109`, but is defined
nowhere.

The midpoint is the position **half of the segment's effort along the track**.
The cumulative point-to-point distance is walked to half the segment length,
and the position is interpolated along the great circle between the two
bracketing records by `gc_interpolate()` (spherical linear interpolation).

Averaging the coordinates of the segment's records is the rejected alternative.
That average is pulled towards wherever records are dense, which on
computer-logged data is wherever the aircraft slowed down. On a curved or
dog-legged track it can fall off the line. The along-track midpoint is on the
track by construction and is weighted by distance, not record count.
`test-tracks-midpoints.R` builds a segment with its records bunched at one end
and asserts that the two methods disagree.

The midpoint is the conventional place to sample habitat covariates in this
family of models. Becker et al. (2019) describe covariates "derived based on the
segment's geographical mid-point", with SST and depth standard deviations taken
over a 3 x 3-pixel box around it. The accuracy of this coordinate therefore
propagates directly into the covariates a density surface model is fitted on.

## 6. Right-angle distances

Steps 11b to 11f compute the right-angle (perpendicular) distance from the
track-line to each sighting, which a detection function is fitted on. Four
sources exist: declination angle, `STRIP` interval, exact position, and
circling position.

### Step 11b — `perp_distance()` and `sighting_distances()`

**File:** `R/04-distances.R`.
**Replaces:** nothing. `original/compute_distance.R` computed distance from
exact sighting positions (`IS_LAT`/`IS_LONG`) via `geosphere::distHaversine`;
declination angles did not exist in the handbook version it was written
against.

Handbook 8.A.2 defines `ANGLEL` and `ANGLER` as "the declination angles, in
degrees, below the horizon of a sighting (to the left or right, respectively)
**when it is perpendicular to the track-line**". The angle is taken with the
sighting abeam, so the aircraft, the sea-surface point below it, and the animal
form a right triangle in the plane perpendicular to the track:

```
x = ALT / tan(angle)
```

90 degrees is straight down and gives zero; towards the horizon the distance
grows without bound. `ALT` is in metres (8.A.1), so distances are in metres by
default. **`seg_eff` is in kilometres**, which matters when both are passed to
`Distance::ds()`.

| Decision | Reason |
|---|---|
| **`on_effort_only = TRUE` by default.** Distances are `NA` outside `LEGTYPE == 2`, `LEGSTAGE == 2`, on effort. | Handbook 8.A.31 restricts right-angle distance measurement to on-effort sightings during census lines, and notes that some teams record them during transits and circling "to maintain both consistency and proficiency". Those must not enter a detection function. |
| **Both angles populated is an error, not a coin flip.** Such records get `side = "both"` and no distance, and `validate_narwc()` reports them. | A sighting is on one side of the track. |
| **Angles outside `(0, 90]` give `NA`.** | Such an angle is at or above the horizon, or behind the aircraft; neither describes a perpendicular distance. |

The handbook switched to angles because survey altitudes had to rise once
offshore wind turbines were in place. `STRIP`'s fixed distance intervals shift
with altitude, whereas "the calculations of distances from angles would always
need to factor in altitude" (8.A.2).

### Step 11c — `narwc_strip_bins()` and `strip_distance()`

**File:** `R/06-strip.R`.
**Replaces:** nothing. The original scripts never decoded `STRIP`.

`STRIP` records right-angle distance as an *interval*, read from calibrated
markings on the observation bubble and wing struts (Kenney and Scott 1981).
Handbook 8.A.31 gives two code books; which applies depends on the programme,
the date, and the aircraft. `narwc_strip_bins()` returns the requested book, and
`strip_distance()` resolves codes against it.

A plain lookup table is not enough, because the same code means different
things under the two books:

| code | CETAP | NLPSC |
|---|---|---|
| 5 | 1/8 – 1/4 nmi | 1/4 – 1/2 nmi |
| 13 | 1 – 2 nmi (Skymaster) | over 4 nmi |

A code read with the wrong book gives plausible but wrong distances, and nothing
downstream detects it. `scheme = "auto"` picks the book from the date (NLPSC
from October 2011) and errors rather than guessing when no date is given.

Two handbook details are encoded and tested:

- Codes `1,2` are the *original unsplit* 0–1/4 nmi interval, later split at
  1/8 nmi into `3,4` and `5,6`. Both forms are in the archive, so `1,2` is kept
  as the wider bin, not merged into the split ones.
- The Skymaster could not see beneath itself. CETAP-era distances from it "are
  actually measured from about 1/8 mile to either side of the survey line".
  This is a left truncation. It is offered as `left_truncation = TRUE`, and is
  better handled as `ds(left = )`.

Every scheme's top bin is open (`>1`, `>2`, `>4` nmi), so `distend` is `Inf`. A
detection function cannot be fitted to an unbounded bin; truncation is required.

### Step 11d — exact sighting positions

**File:** `R/05-exact.R`, plus `gc_bearing()` and `gc_destination()` in
`R/03-geodist.R`.
**Replaces:** `original/compute_distance.R`.

Where `S_LAT`/`S_LONG` exist (8.A.33, 8.A.34), the sighting's position is
known, and the perpendicular distance is measured, not inferred from an angle or
read from a code book. It is the most direct of the three sources. Where it
coexists with a declination angle, the two are independent measurements of the
same quantity, and comparing them checks both.

**Defect corrected.** `compute_distance.R:23` computed
`distHaversine(c(IS_LONG, IS_LAT), c(LONGITUDE, LATITUDE))`, the distance from
the event position straight to the animal. That is a *radial* distance, not a
perpendicular one. It equals the perpendicular distance only if the sighting was
logged at the instant it came abeam, and exceeds it otherwise:

```
radial = sqrt(perpendicular^2 + along_track_offset^2)
```

The error is always in the same direction. The fixture has a whale 132 m off
the track, logged 300 m before the aircraft drew level. Its radial distance is
327.8 m, two and a half times the perpendicular distance the detection function
is defined on. Inflated distances widen the fitted effective strip and bias
density downwards.

**Replacement.** The track through the event position on its local bearing
defines a great circle, and the sighting is projected onto it:

```
delta_xt = asin(sin(delta_13) * sin(theta_13 - theta_12))
delta_at = acos(cos(delta_13) / cos(delta_xt)) * sign(cos(theta_13 - theta_12))
```

`cross_track_distance()` returns both, in metres by default. The sign of
`delta_xt` gives the side, which cross-checks `ANGLEL`/`ANGLER` and the odd/even
`STRIP` convention. `along` is returned so that the size of the correction is
visible: values near zero mean the original method would have agreed.

| Decision | Reason |
|---|---|
| **Bearings come from a centred difference over *distinct* positions.** `track_bearing()` collapses runs of identical positions, then takes the bearing from the previous distinct position to the next; one-sided at the ends of a line. | A sighting record repeats the position of the routine record it follows (handbook 4.2), so consecutive differencing would ask for the bearing between two identical points. A centred difference is also less sensitive to one jittery fix than a forward difference. |
| **`gc_bearing()` returns `NA` for coincident positions.** | `atan2(0, 0)` is `0`, so the naive implementation reports "due north" for a point that has no bearing. |
| **Only census records define the track.** `track_bearing()` uses `LEGTYPE == 2` records by default, grouped by `FILEID` + `LEGNO3`. | An aircraft circling a whale has a bearing, but not the track-line's. The grouping ensures the end of one line is never joined to the start of the next. |
| **Circling sightings get no distance,** even when `S_LAT`/`S_LONG` are present and the geometry would return a number. The fixture contains this case. | Off the census line there is nothing to be perpendicular to. |

Two checks were added to `validate_narwc()`: `exact_position_out_of_range`, and
`exact_position_far_from_event` for positions more than 20 km from the record
that logged them. The second catches a dropped minus sign on `S_LONG` and
coordinates supplied in degrees and decimal minutes.

### Step 11e — `circling_distance()`

**File:** `R/05-exact.R`.
**Replaces:** the commented-out block at `compute_distance.R:34-51`, which
attempted this with `sf::st_distance` and `matrixStats::rowMins` and was
abandoned.

A group spotted from the census track is often circled for photographs,
identification, and a count, and the sighting is logged during the circle, not
at the moment of detection. These records are off effort and off the
track-line, so none of the three sources above gives them a distance. In the
ordinary case they are nevertheless **genuine on-effort detections**: the
animal was seen from the track-line, which is why the aircraft left it.

Dropping them is not neutral. The lost detections are not a random sample; they
are disproportionately the close, conspicuous, or high-priority groups worth
breaking off for. Removing them thins the near-zero end of the distance
distribution, where a detection function is most sensitive, and biases the
fitted curve towards a flatter shoulder.

**The anchor.** Each circling sighting is tied to the last census record before
the circle began: the `LEGSTAGE == 3` break-off record where one exists
(8.A.20), otherwise the last record still on the line. `anchor_event` reports
which was used.

**Break-off point or the line through it.** The aircraft usually flies past a
group before turning, so the break-off point is beyond the animal, not abeam of
it. Three values are returned:

| Column | Meaning |
|---|---|
| `radial` | Straight-line distance from the break-off point. |
| `distance` | That position projected perpendicularly onto the census line. This is the value a detection function is defined on. |
| `along` | How far back down the line the animal was abeam. `radial` exceeds `distance` by exactly the margin `along` records. |

In the fixture, `distance` and `radial` are 250 m and 472 m.

| Decision | Reason |
|---|---|
| **The bearing is the inbound heading, not a centred difference.** It is taken from the previous distinct census position *to* the anchor: the direction of travel at detection. | The record after a break-off is the resume record, and the handbook requires only that the aircraft resume "as close as possible" to where it broke off. An offset resume point would swing a centred bearing by an amount unrelated to the track flown. |
| **An exact position is required by default.** `position = "logged"` allows the aircraft's position as a fallback, and `position_source` records per row which applied. | Without `S_LAT`/`S_LONG`, the only position on the record is the aircraft's, orbiting the animal at a few hundred metres, the same magnitude as the distances measured. A distance with error as large as itself is worse than no distance. |
| **Circling distances are a distinct source.** They should be excluded from a detection function unless inclusion is a deliberate, stated choice; the `distance_source` column and `detection_data(include_circling = )` exist for this. | The position is fixed minutes after detection and the animal has moved, so the result estimates where it was rather than measuring it. That error is not quantified. |

The *spatial-model* side was already handled. `attach_circling_sightings()` has
attributed circling sightings to their segment since v1, under the CETAP
same-species rule, and `segment_survey(circling = )` selects the mode. Those
counts feed abundance whether or not the sighting carries a distance. The two
questions are kept separate deliberately.

**Done in Step 11f.** `sighting_distances()` now combines all sources and
records which was used in `distance_source`.

### Step 11f — the unified `sighting_distances()` and `detection_data()`

**Files:** `R/04-distances.R`, `R/13-detection-data.R`.
**Replaces:** `ds_data_dmr.R:248`, which hard-coded the study area as 5,811 km².

Steps 11b to 11e built four ways of getting a right-angle distance. This step
assembles them and passes the result to `Distance`.

#### One column, four sources

`sighting_distances()` takes `sources` as a **precedence order, not a set**. The
first source that yields a distance for a record claims it, and
`distance_source` records which one. The default comes from
`platform_defaults()`: `c("angle", "exact", "strip")` for an aerial survey,
`"exact"` for a vessel (`docs/09-shipboard-surveys.md`).

Angle precedes exact where a record has both. The angle is taken when the
sighting is abeam, so it measures the perpendicular distance directly, with no
projection onto a fitted bearing and no position error. Reversing the order is
one argument, and is useful: the two are independent measurements of the same
quantity, so their disagreement checks both. In the fixture, three sightings
carry both and agree exactly, but only because the fixture was built that way.
On real data the comparison is informative.

`"circling"` is **not** in the default order. Those detections are usually real,
and dropping them thins the near-zero end of the distribution. But the position
is fixed minutes after detection, which is a different kind of number, so using
it must be requested explicitly.

| Decision | Reason |
|---|---|
| **The provenance column is required, not cosmetic.** | Point and interval distances cannot share a likelihood, and circling distances are estimated, not measured. Without `distance_source` none of this is visible in the table a model is fitted to. |
| **A source can establish `side` without yielding a distance.** A record with both `ANGLEL` and `ANGLER` gets `side = "both"` and no distance, and stays *unclaimed* so a later source can still supply one. | The ambiguity stays visible. Getting this wrong was a regression caught by an existing test. |
| **Circling records are exempt from the on-effort restriction.** | They are off effort by definition; applying the census filter would make the source unusable. |

#### The flatfile

`detection_data()` produces the single table `Distance` accepts:
`Region.Label` / `Area` / `Sample.Label` / `Effort` / `object` / `distance` /
`size`, plus `distbegin`/`distend` for binned rows and any requested segment
covariates.

| Rule | Reason |
|---|---|
| **`area` is a required argument with no default.** | It scales abundance directly. `ds_data_dmr.R:248` had 5,811 km² written into the middle of a function. |
| **Every segment appears, including those with no detections.** | This records effort that produced nothing. Dropping those rows removes the denominator and inflates density. |
| **Truncation drops detections and keeps their segments.** A segment whose only detection is truncated stays as an empty row; a test covers this case. | Effort searched is effort searched, whether or not anything was seen within the truncation distance. This is the case an implementation most often gets wrong. |
| **Point and interval distances in one table is an error by default.** `mixed = "warn"` allows inspection. | One `ds()` call cannot fit both, so such a table marks a survey-era boundary, not a model set. |
| **Open top bins are dropped.** | Every `STRIP` scheme's last bin is unbounded, so `distend` is infinite and no detection function can be fitted to it. |
| **Circling detections are excluded by default.** This does not touch `segs$sightings`. | Excluding a detection from the detection function while counting the animal towards abundance is a normal, defensible combination, so the two are separate arguments and neither implies the other. |

Everything dropped is reported by name and count. The report ends with
`g(0) = 1 is assumed`.

#### Limitation: `g(0)`

`g(0)` (detection probability on the track-line) is not estimated. This is
stated in the function's help page, where a user about to fit a model will look.
See [07-fitting-architecture.md](07-fitting-architecture.md) section 5 for why
it cannot be estimated from a NARWC extract, and what to do instead.

## 7. Sightings and output

### Step 12 — `segment_sightings()`

**File:** `R/11-sightings.R`.
**Ports:** `process_obs_data.R:57-160`.

The function counts sightings and animals per segment per species, and
summarises conditions. Default exclusions, each an argument with a handbook
basis:

| Excluded | Basis |
|---|---|
| `LEGSTAGE == 6`: sighting by anyone other than an on-duty observer | Handbook 4.2: a pilot sighting "cannot be included in a density estimate". **The original kept these** (`ds_data_dmr.R:259` excluded only `LEGSTAGE != 7`). |
| `LEGSTAGE == 7`: sighting found afterwards in a vertical photograph | 8.A.20 |
| `IDREL` of 1 (possible) or 9 (unknown) | 8.A.16 records Kenney's own practice of using only definite and probable identifications. |

It also returns `detections`: one row per qualifying sighting, with `distance`,
`side`, `size`, and `seg_id`. A detection function consumes this table, and
`seg_id` keys it back to the segments for a density surface model.

A circling sighting appears in `detections` with a missing `distance`. It still
counts towards the segment's abundance, but a position logged off the track is
not a perpendicular distance and must not be fitted.

Two Beaufort summaries are produced: `mean_beaufort`, the plain mean over
records, and `wt_beaufort`, weighted by the distance each record covers. The
weighted one is preferred as a detection covariate: a sea state recorded over
3 km should not count the same as one recorded over 200 m.
`weighted_mean_safe()` falls back to the plain mean when every weight is zero,
which happens on a segment whose records share a position.

### Step 13 — `segment_survey()` and output

**Files:** `R/12-segment-survey.R`, `R/spatial.R`.

`segment_survey()` runs steps 3 to 12 and returns a `distsamp_segments` object:
`segments`, `sightings`, `detections`, `tracks`, `points`, plus the `call` and
`settings`. Steps 3 to 5 are skipped when the input already carries `LEGNO3`,
`CIRCLE`, or `OnOff.Effort`, so a user's own definitions can be substituted.
Since this was written it also fills `LEGSTAGE`, checks the platform by speed,
and computes right-angle distances; `docs/10-code-guide.md`, Section 4, lists
the current steps.

Both random choices run inside a single `withr::with_seed()` block, so one seed
fixes the whole segmentation. With no seed, `with_optional_seed()` uses
`withr::with_preserve_seed()`. Either way the calling session's RNG stream is
not disturbed; the test suite asserts this.

| Function | Role |
|---|---|
| `segments_wide()` | One count column per species, the shape `dsm` expects. Missing combinations become `0`, not `NA`. |
| `segments_as_sf()` | Midpoints or per-segment `LINESTRING` geometry. `sf` is in `Suggests`; its absence is reported with an actionable message. |
| `crop_to_bbox()` | Replaces the undefined `crop_data()`. Handles data frames, `sf` objects, and whole `distsamp_segments` results, keeping the tables consistent with each other. Accepts a box given with its corners reversed. |
| `write_segments()` | The only function that writes to disk. |

## 8. Dependencies

| Field | Packages |
|---|---|
| `Imports` | dplyr, narwcr, rlang, stats, tibble, tidyr, utils, withr |
| `Suggests` | Distance, ggplot2, googledrive, knitr, Microsoft365R, patchwork, rmarkdown, rnaturalearth, rnaturalearthdata, sf, testthat |

As of 2026-11-12. `narwcr` holds reading and effort flags. The plotting,
coastline and cloud-storage packages in `Suggests` are optional.

Dropped relative to `original/`:

| Package | Reason |
|---|---|
| `geosphere` | Replaced by `gc_distance()`. |
| `sp` | Retired upstream. |
| `stringr` | Base string handling suffices. |
| `marmap`, `terra`, `copernicus`, `rosm`, `ggspatial`, `doParallel` | Mapping and covariate stack; not needed by the segmentation core. `rnaturalearth` returned later in `Suggests`, for optional coastlines in plots. |

All `library()` calls inside function bodies are removed; every external call is
namespaced.

## 9. The test fixture

**Files:** `data-raw/make-fixture.R` (generator),
`inst/extdata/narwc-example.csv` (output, 113 records).

The fixture is built from the hypothetical survey in handbook Figure 2
(section 4.2), because the handbook states its correct handling explicitly. It
contains:

- a transit with an off-effort sighting;
- survey lines with begin, continue, and end stages;
- two sightings sharing one `EVENTNO`;
- a pilot sighting at `LEGSTAGE 6`;
- a cross-leg with a sighting;
- a break-off, a five-record circling excursion, and a resume;
- a sighting at `LEGSTAGE 7`;
- a line abandoned when the sea state rises and re-flown later;
- a sighting at `IDREL 1`.

The geometry is simple by design. Every line runs due north along a constant
meridian in 0.01-degree steps, so one step is exactly 1.1112 km and every
expected distance can be checked by hand. Total on-effort distance is
92.2296 km across seven tracks.

Four sightings also carry an exact position in `S_LAT`/`S_LONG`. These are
constructed with a destination-point formula, not typed in. Each departs the
meridian on bearing 90 or 270, which leaves it at a right angle, so the implied
perpendicular distance is exact.

- Three are placed at exactly the distance their own declination angle gives,
  so the two independent sources must agree to the last bit.
- One of those three is also displaced 300 m along the track, so its radial and
  perpendicular distances differ by a factor of two and a half.
- The fourth is on the circling excursion, placed relative to the break-off
  point, not the orbiting aircraft: 400 m back down line 2 and 250 m to its
  right. `circling_distance()` must recover 250 m against a radial distance of
  471.7 m, and `exact_distance()` must return nothing, having no track-line
  there to be perpendicular to.

## 10. References

Full citations are in [06-references.md](06-references.md).
