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
   `LAT_DD`/`LONG_DD` (8.A.18, 8.A.22), but the extracts the database manager
   distributes — and all of `original/` — use `LATITUDE`/`LONGITUDE`. The
   package standardises internally on `LATITUDE`/`LONGITUDE` and accepts either
   on input, along with `LEGTYPE_BK`, `EVENT`, and a handful of other spellings
   seen in upstream processed files. An alias never overwrites a column that
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

## Step 1c — `fill_narwc()`

**File:** `R/fill.R`
**Ports:** `DataExploration.R:52`, `:71`; `detectionFunctionMultipleYears.R:55`,
`:67`, `:76`.

NARWC data records a value once and leaves it blank until it changes. `LEGTYPE`
is entered as `2` at the start of a census line and the rows beneath are empty
until the leg type changes; `BEAUFORT` stays as recorded until the sea state is
re-assessed. Downstream code needs the state each record was actually flown
under, so the blanks have to be filled.

The original did this:

```r
tidyr::fill(c("LEGTYPE", "LEGSTAGE", "LEGNO", "VISIBLTY", "BEAUFORT",
              "CLOUD", "GLAREL", "GLARER", "WX"), .direction = "downup")
```

**Ungrouped.** There is no `group_by()` anywhere near it, so the fill runs the
length of the file: the sea state from the last record of one survey day carries
into the first records of the next, and a leg number carries across a `FILEID`
boundary into a different survey. Neither is recoverable afterwards, because a
filled value is indistinguishable from a recorded one. `by` therefore defaults to
`FILEID` and `DATE`, and a frame with neither warns rather than filling across
everything.

The same scripts also disagree with themselves:
`detectionFunctionMultipleYears.R:55` fills the same nine columns with **no**
`.direction`, which is `"down"`, while `DataExploration.R:52` uses `"downup"`.
Two different treatments of the same data in one codebase.

Four judgement calls:

- **State may be filled; measurements may not.** `LEGTYPE` and `BEAUFORT`
  persist until something changes them, so a blank means "as above" and filling
  recovers information deliberately not repeated. A position, a time, a species,
  a group size describes one moment, and a blank means it was not taken. Filling
  one fabricates a measurement.
- **Sighting columns are refused outright, not merely omitted from the default.**
  `narwc_never_fill()` covers `SPECCODE`, `NUMBER`, `SIGHTNO`, `STRIP`, the
  angles, `S_LAT`/`S_LONG`, and the per-record identifiers, and asking for one is
  an error. Carrying `SPECCODE` and `NUMBER` forward would replicate a single
  group of three right whales onto every row until the next sighting, and every
  count downstream would be wrong by orders of magnitude. This is the failure
  mode that would be hardest to notice, because the result still looks like data.
- **Backward fills are counted separately.** `"downup"` fills down and then up,
  so the only values it fills backwards are those before the first recorded value
  in a group — a smaller claim than it first appears, but still a guess about
  state that was never logged. Where a day begins on transit before the first
  `LEGTYPE` is entered, back-filling a `2` marks that transit as census effort.
  The report separates *carried forward* from *carried backward*, because only
  the first is recovery.
- **`LEGSTAGE` is flagged as the least safe default.** If a file records `1`
  (begin line) and leaves the continuation rows blank, filling down marks the
  whole line "begin line" rather than `2` (continue) — and since on-effort
  eligibility is `LEGSTAGE == 2`, that line drops out of every distance
  calculation. Whether it happens depends on the recording convention of the file
  in hand, which cannot be settled without one. The behaviour is documented and
  the per-column counts are reported so it is visible.

A regression test gaps the fixture — blanking every value that repeats the row
above, within file and day — and asserts that filling restores it exactly and
that `segment_survey()` gives identical segments and sightings either way.

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
| `legstage_off_census` | note | 8.A.20: `LEGSTAGE` is recorded only during `LEGTYPE == 2`, except code 7 |
| `sighting_at_boundary` | warning | 8.A.20, 4.2: sightings should not occur at `LEGSTAGE` 1, 3, 4, or 5 |
| `eventno_not_increasing` | warning | Repeats are legal (4.2 assigns one event several sightings); decreases mean mis-sorted records |
| `bad_time_format` | warning/note | 8.A.37: six-digit `hhmmss` |
| `coordinates_out_of_range` | error | Latitude and longitude bounds |
| `positive_west_longitude` | warning | 8.A.22: west longitudes must be negative |
| `sighting_without_number` | warning | 8.A.24: `NUMBER` required for all sightings |

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

- `LEGTYPE == 4` — the "other (circling)" code (8.A.21); and
- any record between a `LEGSTAGE == 3` (break off line to circle) and the
  following `LEGSTAGE == 4` (resume line), within the same line occupation
  (8.A.20).

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
standard). Those defaults are the CETAP criteria as stated by Kenney and Winn
(1986, p. 347) — "observer(s) formally on watch, clear visibility of at least 2
miles, and sea states of Beaufort 3 or lower" — with the altitude ceiling set
above the 750 ft (229 m) at which CETAP surveys were flown (p. 346).

Every threshold is an argument; the original hard-coded all four. A criterion
whose column is absent is skipped with a message rather than silently.

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

## Step 11b — `perp_distance()` and `sighting_distances()`

**File:** `R/distances.R`
**Replaces:** nothing. `original/compute_distance.R` computed distance from
exact sighting positions (`IS_LAT`/`IS_LONG`) via `geosphere::distHaversine`;
declination angles did not exist in the handbook version it was written against.

Handbook 8.A.2 defines `ANGLEL` and `ANGLER` as "the declination angles, in
degrees, below the horizon of a sighting (to the left or right, respectively)
**when it is perpendicular to the track-line**". Because the angle is taken with
the sighting abeam, the aircraft, the sea-surface point below it, and the animal
form a right triangle in the plane perpendicular to the track:

```
x = ALT / tan(angle)
```

90 degrees is straight down and gives zero; approaching the horizon the distance
grows without bound. `ALT` is in metres (8.A.1) so distances are metres by
default — **note that `seg_eff` is in kilometres**, which matters when handing
both to `Distance::ds()`.

Three judgement calls:

- **`on_effort_only = TRUE` by default.** Handbook 8.A.31 restricts right-angle
  distance measurement to on-effort sightings during census lines, and notes
  that some teams record them during transits and circling "to maintain both
  consistency and proficiency". Those must not enter a detection function, so
  distances are left `NA` outside `LEGTYPE == 2`, `LEGSTAGE == 2`, on effort.
- **Both angles populated is an error, not a coin flip.** A sighting is on one
  side of the track. Such records get `side = "both"` and no distance, and
  `validate_narwc()` reports them.
- **Angles outside `(0, 90]` give `NA`.** At or above the horizon, or behind the
  aircraft; neither describes a perpendicular distance.

Why the handbook made the switch is worth recording: survey altitudes had to
rise once offshore wind turbines were in place, and `STRIP`'s fixed distance
intervals shift with altitude, whereas "the calculations of distances from
angles would always need to factor in altitude" (8.A.2).

## Step 11c — `narwc_strip_bins()` and `strip_distance()`

**File:** `R/strip.R`
**Replaces:** nothing. The original scripts never decoded `STRIP`.

`STRIP` records right-angle distance as an *interval*, from calibrated markings
on the observation bubble and wing struts (Kenney and Scott 1981). Handbook
8.A.31 gives two code books, and which applies depends on the programme, the
date, and the aircraft. `narwc_strip_bins()` returns whichever is asked for;
`strip_distance()` resolves codes against it.

The reason this needed care rather than a lookup table: the same code means
different things under the two books.

| code | CETAP | NLPSC |
|---|---|---|
| 5 | 1/8 – 1/4 nmi | 1/4 – 1/2 nmi |
| 13 | 1 – 2 nmi (Skymaster) | over 4 nmi |

Reading a code with the wrong book produces plausible distances that are wrong,
and nothing downstream would notice. `scheme = "auto"` picks from the date —
NLPSC from October 2011 — and errors rather than guess when given no date.

Two handbook details that are easy to lose, both encoded and tested:

- Codes `1,2` are the *original unsplit* 0–1/4 nmi interval, later split at
  1/8 nmi into `3,4` and `5,6`. Both forms are in the archive, so `1,2` is kept
  as the wider bin rather than merged into the split ones.
- The Skymaster could not see beneath itself. CETAP-era distances from it "are
  actually measured from about 1/8 mile to either side of the survey line" —
  a genuine left truncation, offered as `left_truncation = TRUE` and better
  handled as `ds(left = )`.

Every scheme's top bin is open (`>1`, `>2`, `>4` nmi), so `distend` is `Inf`. A
detection function cannot be fitted to an unbounded bin; truncation is required.

## Step 11d — exact sighting positions

**File:** `R/exact.R`, plus `gc_bearing()` and `gc_destination()` in
`R/geodist.R`
**Replaces:** `original/compute_distance.R`.

Where `S_LAT`/`S_LONG` exist (8.A.33, 8.A.34) the sighting's position is known
outright, and the perpendicular distance can be measured rather than inferred
from an angle or read off a code book. This is the most direct of the three
sources, and where it coexists with a declination angle the two are independent
measurements of the same quantity — so comparing them checks both.

**The defect this fixes.** `compute_distance.R:23` computed
`distHaversine(c(IS_LONG, IS_LAT), c(LONGITUDE, LATITUDE))` — the distance from
the event position straight to the animal. That is a *radial* distance, not a
perpendicular one. It equals the perpendicular distance only if the sighting was
logged at the instant it came abeam, and exceeds it otherwise:

```
radial = sqrt(perpendicular^2 + along_track_offset^2)
```

The error is always in the same direction. The fixture carries a case where a
whale 132 m off the track was logged 300 m before the aircraft drew level: the
radial distance is 327.8 m, two and a half times the perpendicular distance the
detection function is defined on. Inflated distances widen the fitted effective
strip and bias density downwards.

**What replaces it.** The track through the event position on its local bearing
defines a great circle; the sighting is projected onto it.

```
delta_xt = asin(sin(delta_13) * sin(theta_13 - theta_12))
delta_at = acos(cos(delta_13) / cos(delta_xt)) * sign(cos(theta_13 - theta_12))
```

`cross_track_distance()` returns both, in metres by default. The sign of
`delta_xt` gives the side, which is a free cross-check against `ANGLEL`/`ANGLER`
and the odd/even `STRIP` convention. `along` is returned rather than discarded so
that the size of the correction is visible: values near zero mean the original
method would have agreed.

Four judgement calls:

- **Bearings come from a centred difference over *distinct* positions.** A
  sighting record repeats the position of the routine record it follows
  (handbook 4.2), so consecutive differencing would ask for the bearing between
  two identical points. `track_bearing()` collapses runs of identical positions
  first, then takes the bearing from the previous distinct position to the next,
  which is also less sensitive to a single jittery fix than a forward
  difference. One-sided at the ends of a line.
- **`gc_bearing()` returns `NA` for coincident positions.** `atan2(0, 0)` is
  `0`, so the naive implementation reports a confident "due north" for a point
  that has no bearing at all.
- **Only census records define the track.** An aircraft circling a whale has a
  bearing, but it is not the track-line's. `track_bearing()` uses `LEGTYPE == 2`
  records by default, and the grouping defaults to `FILEID` + `LEGNO3` so that
  the end of one line is never joined to the start of the next.
- **Circling sightings still get no distance,** even though `S_LAT`/`S_LONG` may
  be present and the geometry would return a number. Off the census line there
  is nothing to be perpendicular to. The fixture contains exactly this case.

`validate_narwc()` gained two checks: `exact_position_out_of_range`, and
`exact_position_far_from_event` for positions more than 20 km from the record
that logged them, which catches a dropped minus sign on `S_LONG` and coordinates
supplied in degrees and decimal minutes.

## Step 11e — `circling_distance()`

**File:** `R/exact.R`
**Replaces:** the commented-out block at `compute_distance.R:34-51`, which
attempted this with `sf::st_distance` and `matrixStats::rowMins` and was
abandoned.

A group spotted from the census track is often circled for photographs,
identification, and a proper count, and the sighting is logged during that
circle rather than at the moment of detection. Those records are off effort and
off the track-line, so none of the three sources above will give them a
distance — but they are, in the ordinary case, **genuine on-effort detections**:
the animal was seen from the track-line, which is why the aircraft left it.

Dropping them is therefore not neutral. The detections lost are not a random
sample of detections; they are disproportionately the close, conspicuous, or
high-priority groups worth breaking off for. Removing them thins the near-zero
end of the distance distribution, which is where a detection function is most
sensitive, and biases the fitted curve towards a flatter shoulder.

**The anchor.** Each circling sighting is tied back to the last census record
before the circle began — the `LEGSTAGE == 3` break-off record where there is
one (8.A.20), otherwise the last record still on the line. `anchor_event`
reports which was used.

**Break-off point, or the line through it.** The aircraft usually flies past a
group before turning, so the break-off point is beyond the animal, not abeam of
it. Both readings are returned: `radial` is the straight-line distance from the
break-off point, `distance` is that position projected perpendicularly onto the
census line, and `along` is how far back down the line the animal was abeam.
`distance` is the one a detection function is defined on; `radial` is larger by
exactly the margin `along` records. In the fixture the two are 250 m and 472 m.

Three judgement calls:

- **The bearing is the inbound heading, not a centred difference.** The record
  after a break-off is the resume record, and the handbook only requires the
  aircraft to resume "as close as possible" to where it broke off. A resume
  point offset from the break-off would swing a centred bearing by an amount
  that has nothing to do with the track that was flown, so the bearing is taken
  from the previous distinct census position *to* the anchor — the direction the
  aircraft was going when it made the detection.
- **An exact position is required by default.** With `S_LAT`/`S_LONG` absent, the
  only position on the record is the *aircraft's*, orbiting the animal at a
  radius of a few hundred metres — the same magnitude as the distances being
  measured. `position = "logged"` allows that fallback for anyone who wants it,
  and `position_source` records per row which applied, but it is not the
  default: a distance with error as large as itself is worse than no distance.
- **These are a distinct source, not more of the same.** The position is fixed
  minutes after detection, so the animal has moved, and the result estimates
  where it was rather than measuring it. That error is not quantified. Circling
  distances should be excluded from a detection function unless including them
  is a deliberate and stated choice — which is what the `distance_source`
  column and `detection_data(include_circling = )` are for.

Note that the *spatial-model* side of this was already handled:
`attach_circling_sightings()` has attributed circling sightings back to their
segment since v1, under the CETAP same-species rule, and
`segment_survey(circling = )` selects the mode. Those counts feed abundance
whether or not the sighting carries a distance — the two questions are separate,
and deliberately so.

**Not yet done.** `sighting_distances()` still uses angles only. Unifying the
sources behind one call, with a `distance_source` column recording which was
used, is the next step — see [05-next-steps.md](05-next-steps.md).

## Step 1b — `narwc_profiles()` and unrecognised columns

**File:** `R/profiles.R`, plus changes to `read_narwc()` and `validate_narwc()`
**Replaces:** nothing. The original scripts assumed one survey programme's file
layout without saying so.

A NARWC extract is not the only shape this data arrives in. Survey programmes
add their own derived columns, and a processed "ready for model" file may carry
a dozen that are not in handbook Table 1.

**The defect this fixes is in v1 of this package, not in `original/`.**
`read_narwc()` selected the handbook columns and discarded everything else
without a word:

```r
keep <- c(schema$required, schema$optional, extra_columns)
dat <- dat[, intersect(keep, names(dat)), drop = FALSE]
```

A CCS file lost `IS_LAT`, `IS_LONG`, and `Tr_SIGHTING` silently. `extra_columns`
was the escape hatch, but it required knowing in advance what to name — and the
columns you most need to know about are the ones you have not seen before.

**What it does now.** Dropped columns are reported, by name, with the profile
they match if they match one:

```
`read_narwc()` dropped 5 columns not in the NARWC handbook schema:
  Effort_Type, IS_LAT, IS_LONG, IS_SPECCODE, Tr_SIGHTING
4 of these are declared by the "ccs" profile (Center for Coastal Studies, Cape Cod Bay).
Keep them with `profile = "ccs"`; see `narwc_profiles()`.
```

`narwc_profiles()` is the registry: programme, column, meaning, the role
`distsamp` gives it, and how confident the meaning is. `validate_narwc()` carries
the same information as a `columns_outside_handbook` note, for data frames that
never went through `read_narwc()`.

Four judgement calls:

- **Detection suggests, declaration acts.** A profile is never applied because a
  column name matched. `Tr_SIGHTING` means "sighting made from the track-line" in
  a CCS file and there is nothing stopping another programme using that name for
  something else — a column name is not a contract between programmes. So
  `read_narwc()` will say what a file looks like, and `profile = "ccs"` is the
  caller's decision. This is the same reasoning that keeps `Tr_SIGHTING` out of
  the eligibility rule; see defect 15.
- **Keeping is not interpreting.** `profile = "ccs"` carries those columns
  through and does nothing else with them. Every registry entry is currently
  `role = "passthrough"`, and the registry says so rather than implying a
  capability that does not exist.
- **Confidence is recorded per column.** `IS_LAT`, `IS_LONG`, and `Tr_SIGHTING`
  are `confirmed`; `OBSSIGHT` and the rest are `unconfirmed`, because their
  meaning was inferred from the column name and nothing else. Marking a guess as
  a guess is the whole point — the previous version of this documentation
  recorded `IS_LAT` as "presumably the handbook's `S_LAT`", which was wrong in a
  way that would have propagated into the distance code.
- **A redundant alias is not a loss.** A file carrying both `LAT_DD` and
  `LATITUDE` keeps the latter and discards the former, and reporting that would
  send the caller looking for information that is still present under another
  name. Aliases whose canonical column survived are excluded from the message.

**Not yet done.** No profile column is interpreted. The case for doing so is
`IS_LAT`/`IS_LONG`, which give a better anchor for circling distances than the
break-off record — see [05-next-steps.md](05-next-steps.md) item 2.

## Step 12 — `segment_sightings()`

**File:** `R/sightings.R`
**Ports:** `process_obs_data.R:57-160`.

Counts sightings and animals per segment per species, and summarises conditions.

Default exclusions, each with a handbook basis:

- `LEGSTAGE == 6` — sighting by anyone other than an on-duty observer. Handbook
  4.2 is explicit that a pilot sighting "cannot be included in a density
  estimate". **The original kept these** (`ds_data_dmr.R:259` excluded only
  `LEGSTAGE != 7`).
- `LEGSTAGE == 7` — sighting found afterwards in a vertical photograph (8.A.20).
- `IDREL` of 1 (possible) or 9 (unknown) — 8.A.16 records Kenney's own practice
  of using only definite and probable identifications.

All three are arguments.

It also returns `detections`: one row per qualifying sighting rather than per
segment, with `distance`, `side`, `size`, and `seg_id`. That is the table a
detection function consumes, and `seg_id` keys it back to the segments for a
density surface model.

A circling sighting appears in `detections` with a missing `distance`, and
correctly so — it still counts towards the segment's abundance, but a position
logged off the track is not a perpendicular distance and must not be fitted.

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

Four sightings also carry an exact position in `S_LAT`/`S_LONG`. They are not
typed in but constructed with a destination-point formula, departing the meridian
on bearing 90 or 270 — which leaves it at a right angle, so the perpendicular
distance each one implies is exact rather than approximate. Three are placed at
exactly the distance their own declination angle gives, so the two independent
sources must agree to the last bit; one of those three is also displaced 300 m
along the track, so the radial and perpendicular distances differ by a factor of
two and a half. The fourth is on the circling excursion, placed relative to the
break-off point rather than to the orbiting aircraft — 400 m back down line 2 and
250 m to its right — so that `circling_distance()` must recover 250 m against a
radial distance of 471.7 m, and `exact_distance()` must still return nothing,
having no track-line there to be perpendicular to.


---

Full citations: [06-references.md](06-references.md).
