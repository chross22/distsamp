# Defects found in the original scripts

*C. H. Ross. 2026-11-12. Distributed with the package source.*

## 1. Scope

This chapter lists the 16 defects found in the original research scripts
(`original/`), and what was done about each. Each entry gives where the defect
is, its consequence, the fix, and the regression test that now guards it.

The method being ported is Becker et al. (2010), *Marine Ecology Progress
Series* 413:163–183, `doi:10.3354/meps08696`. The data format is Kenney (2023),
NARWC Reference Document 2023-01. Full citations, and what each is relied on
for, are in [06-references.md](06-references.md).

The original scripts are **not distributed** with this package. They contain
collaborators' working notes and local paths. The `original/…:NN` references
are provenance, not links: they record where each defect came from, so the
rewrite can be audited by anyone holding the original code.

Terms:

| Term | Meaning |
|---|---|
| severity | Impact of the defect: low, medium, high, or critical. |
| `case5` | The cutter's end-of-track case: the final segment absorbs everything remaining. |
| `segtol` | The tolerance that keeps a realised segment length inside `[0.5s, 1.5s]`, where `s` is the target length. |
| CETAP | Cetacean and Turtle Assessment Program. The source of the 2-nmi visibility standard and of the circling rule in defect 10. |
| CCS | Center for Coastal Studies, which runs the Cape Cod Bay aerial survey programme. |

## 2. Summary

| # | Defect | Severity | Guarding test |
|---|---|---|---|
| 1 | Legacy visibility codes discarded all pre-2004 effort | high | `test-effort.R` (in `narwcr`) |
| 2 | Last trackline of every dataset dropped | high | `test-segments.R` |
| 3 | Segmentation not reproducible | high | `test-segments.R` |
| 4 | Leftover never on the final segment | medium | `test-segments.R` |
| 5 | Chopping loop quadratic | medium | none named |
| 6 | `1:length(x)` on empty input | medium | `test-segments.R` |
| 7 | One spurious track per off-effort record | low | `test-tracks-midpoints.R` |
| 8 | Cutting error accumulated into the final segment | medium | `test-segments.R` |
| 9 | Pilot sightings counted | medium | `test-sightings.R` |
| 10 | Circling sightings hard-coded to right whales | medium | `test-sightings.R` |
| 11 | Study parameters hard-coded | medium | none named |
| 12 | Files written by evaluating strings | low | none named |
| 13 | Duplicate and colliding definitions | low | none named |
| 14 | Functions called but never defined | critical | none named |
| 15 | Exact distances radial, not perpendicular | high | `test-exact.R` |
| 16 | Blank columns filled across days and files | high | `test-fill.R` (in `narwcr`) |

## 3. Defects

### 1. Legacy visibility codes silently discarded all pre-2004 effort

**Where:** `ds_data_prep_dmr.R:82`. **Severity:** high, silently drops data.

```r
I2 <- which(dat$VISIBLTY >= 2 & dat$ALT < 366 & dat$BEAUFORT <= 3)
```

`VISIBLTY` holds two encodings in one column (handbook 8.A.38). It was first a
one-digit code. The code recorded only whether visibility reached the
2-nautical-mile CETAP standard and, if not, the weather responsible. In 2004 it
was redefined as the actual visibility in nautical miles. In the 2021 archive
update the old codes were folded back into `VISIBLTY` **as negative numbers**:

| Code | Meaning |
|---|---|
| `-1` | clear visibility for at least 2 nautical miles |
| `-2` | less than 2 miles, fog |
| `-3` | less than 2 miles, haze |
| `-4` | less than 2 miles, rain |
| `-5` | less than 2 miles, snow |

**Consequence:** `VISIBLTY >= 2` marks every legacy record unacceptable,
including `-1`, which records *good* visibility. On a multi-year dataset that
spans the 2004 change, every pre-2004 survey line is classified as off effort.
Its distance is never accumulated and its sightings are never counted. Nothing
errors; the analysis runs on a fraction of the data.

**Fix:** `visibility_ok()` (now in `narwcr`, `R/effort.R`; re-exported here) branches on sign. A `-1` record
asserts only that visibility reached 2 nmi, so it returns `NA`, not a false
`TRUE`, when asked to satisfy a stricter threshold.

**Tests:** `narwcr`'s `test-effort.R`: "legacy visibility codes are read as codes, not
distances", "a legacy clear code cannot satisfy a stricter threshold", and
"legacy-format effort is not silently discarded".

### 2. The last trackline of every dataset was dropped

**Where:** `chop_to_size.R:12`. **Severity:** high, loses data.

```r
for(i in 1:(dim(totdist_expand)[1]-1)){
```

**Consequence:** the loop stops one row short, because its body reads row
`i+1` to detect the end of a track. The final planned segment is never cut.
That segment is the final row, so the last track of the whole dataset produces
no segments.

**Fix:** `cut_one_track()` in `R/08-segments.R` iterates every planned segment and
treats `i == n_seg` as end-of-track, the existing `case5`.

**Test:** `test-segments.R`: "the last track is not dropped". Three tracks go
in and three come out, with total segment effort equal to total track effort.

### 3. Segmentation was not reproducible

**Where:** `compute_num_segs.R:99`, `chop_to_size.R:74`. **Severity:** high,
results cannot be reproduced.

```r
randnum <- runif(1, 1, numsegs)          # which segment absorbs the leftover
coinflip <- round(runif(n = 1, ...))     # over- or under-shoot the target
```

**Consequence:** both draws are unseeded. No two runs produce the same
segments, and no published result can be regenerated.

**Fix:** `segment_survey(seed = )` threads a seed through both draws, which run
inside one `withr::with_seed()` block. Without a seed,
`withr::with_preserve_seed()` is used instead. The caller's RNG stream is not
disturbed in either case.

**Tests:** `test-segments.R`: "segmentation is reproducible under a seed" and
"segmenting does not disturb the caller's RNG stream".

### 4. The leftover could never land on the final segment

**Where:** `compute_num_segs.R:99-105`. **Severity:** medium, systematic bias.

```r
randnum <- runif(1, 1, numsegs)
randpick <- floor(randnum)
expand$tgtdist[randpick] <- extrabit
```

**Consequence:** `runif(1, 1, n)` draws from `[1, n)`, so `floor()` returns `1`
to `n-1`, never `n`. The segment that absorbs a track's leftover distance is
never the last one. That segment is systematically shorter or longer than the
rest, so every track carries a small, consistent spatial bias: the odd segment
is never at the far end.

**Fix:** `sample.int(n_seg, 1L)` in `plan_one_track()`.

**Test:** `test-segments.R`: "the leftover can land on any segment, including
the last". It runs 200 seeds and asserts that all five positions occur.

### 5. The chopping loop was quadratic

**Where:** `chop_to_size.R:128-137`. **Severity:** medium, performance.

```r
dat_chopped <- dat_chopped |> rbind(dat_onedate_onelegno)
dat_chopped_4join <- dat_chopped |> dplyr::select(-seg_eff, -seg_no) |> ...
dat_nest_expand <- dat_nest_expand |> anti_join(dat_chopped_4join)
```

**Consequence:** every iteration `rbind`s onto an accumulating frame. It then
`anti_join`s that whole growing frame against the whole remaining dataset to
find the unconsumed rows. On a season of computer-logged survey data (hundreds
of thousands of records, thousands of segments) this dominates the runtime. The
`anti_join` is also unkeyed, so it matches on every shared column: two distinct
records with identical values remove each other.

**Fix:** `cut_one_track()` keeps a per-track row cursor. Each track's records
are visited once. Results are combined with one `bind_rows()` at the end.

**Test:** none named.

### 6. `1:length(x)` iterates backwards on empty input

**Where:** `ds_data_dmr.R:112`, `ds_data_dmr.R:124`, `ds_data_dmr.R:255`,
`create_new_track_nos.R:30`, `create_new_track_nos.R:41`,
`compute_num_segs.R:33`. **Severity:** medium, wrong results or an error on an
empty subset.

**Consequence:** `1:length(x)` yields `c(1, 0)` when `x` is empty. The loop
body runs twice with meaningless indices instead of not at all. This happens
when a species is absent from a season, a date has no qualifying tracklines, or
a filter empties a group.

**Fix:** `seq_len()` and `seq_along()` throughout.

**Test:** `test-segments.R`: "empty and single-record inputs do not error".

### 7. A break in effort produced one spurious track per record

**Where:** `create_new_track_nos.R:76-82`. **Severity:** low; cosmetic, but
makes `new_trackno` hard to interpret.

**Consequence:** the original incremented `new_trackno` on *every* record where
the current and next records were both off effort. A five-record circling
excursion produced four new track numbers, not one. The increment also stopped
one record before the excursion ended, so the last two off-effort records were
attached to the track that resumed *afterwards*.

**Fix:** `track_index()` in `R/07-tracks.R` first smooths isolated single
off-effort records, then starts a new track at each change of effort state. A
sustained break yields three tracks: effort before, the break, effort after.
The middle track carries no effort and is dropped by `track_effort()`. Each
surviving track contains only on-effort records.

**Tests:** `test-tracks-midpoints.R`: "a break in effort starts a new track"
and "multi-record circling splits the track, and the fixture shows it".

### 8. Cutting error accumulated into the final segment

**Where:** `chop_to_size.R:52-125`. **Severity:** medium, segments outside the
stated tolerance band.

**Consequence:** each segment's target was measured from wherever the previous
segment ended. A cut can fall only on a record boundary, so every segment lands
a little over or under its target, and the errors compound down the track. On a
long track of many small records the arrears all land on the final segment,
which `case5` makes absorb everything remaining. That segment then falls well
outside the `[0.5s, 1.5s]` band the `segtol` logic is meant to guarantee.

The defect was found by the test suite, not by reading: the tolerance-band test
failed on a 111 km track of 0.56 km records.

**Fix:** `cut_one_track()` measures cut points as cumulative distance from the
**start of the track** (`cut_at <- cumsum(plan_i$tgtdist)`). Each segment's
effective target absorbs the previous segment's error instead of passing it
on. The planning logic, the coin flip, and `case5` are unchanged.

**Tests:** `test-segments.R`: "segment lengths stay inside the tolerance band"
(15 seeds) and "cutting error does not accumulate down a track" (10 seeds on a
401-record track).

### 9. Pilot sightings were counted in density estimates

**Where:** `ds_data_dmr.R:257-260`. **Severity:** medium, inflates counts.

```r
I <- which(dat$SPECCODE == spp[i] & dat$LEGSTAGE != 7 & (dat$IDREL == 2 | dat$IDREL == 3))
```

**Consequence:** `LEGSTAGE == 7` (a sighting found in a vertical photograph) is
excluded, but `LEGSTAGE == 6` (a pilot sighting) is not. Handbook 4.2, on event
6 of the worked example, says a pilot sighting "cannot be included in a density
estimate, therefore it is assigned a different LEGSTAGE". It did not arise from
the standard search effort the detection function describes. Including it
inflates the count with no matching increase in effort.

**Fix:** `segment_sightings(legstage_exclude = c(6, 7))`, overridable.

**Tests:** `test-sightings.R`: "pilot and photograph sightings
are excluded by default" and "excluded LEGSTAGEs can be overridden".

### 10. Circling sightings were hard-coded to right whales

**Where:** `process_obs_data.R:49-50`, `process_obs_data.R:153`.
**Severity:** medium, wrong for any other species.

```r
riwh_circle <- dat_nest_expand |> filter(SPECCODE =='RIWH') |> ...
num_anms <- ... filter(SPECCODE == "RIWH")   # "needs to be modified if looking at other whales"
```

**Consequence:** every circling right whale was attached back to its segment.
Circling sightings of every other species were discarded. That is not the
handbook rule, nor correct for a multi-species analysis, and the code carries a
comment saying so. Handbook 4.2 (event 11) states the CETAP rule: further
individuals *of the same species* seen while circling are counted with the
original on-effort group; groups of *other* species not first seen from the
track-line are new off-effort sightings.

**Fix:** `attach_circling_sightings(mode = )` with `"same_species"` (default;
the handbook rule), `"all"`, and `"none"`.

**Test:** `test-sightings.R`: "circling sightings are attached,
and only for the same species".

### 11. Study parameters hard-coded mid-function

**Where:** `ds_data_dmr.R:243-249`. **Severity:** medium, silently wrong for
any other study.

```r
dat$Region.Label <- "MyStratum"
dat$Area <- 5811   # sq km, this could be put in the function call.
```

**Consequence:** the survey area is a constant in the middle of a function,
with a comment admitting it should be an argument. Any analysis of another area
or year inherits 5,811 km² unless the user notices.

**Fix:** both are removed from the segmentation core. Area and region are
properties of a study design, not of a segmentation, and belong to the
abundance-estimation step. Species selection, equally hard-coded, is the
`species` argument.

**Test:** none named.

### 12. Files written by building and evaluating strings

**Where:** `ds_data_dmr.R:341-387`. **Severity:** low, fragile.

```r
cmd = paste("write.csv(effort_summary, file = '", target.dir, "effort_summary_", fn, ".csv'", ...)
eval(parse(text = cmd))
```

**Consequence:** four `write.csv` calls are built as strings and evaluated. A
quote or apostrophe in a path breaks them, and the concatenation assumes
`target.dir` ends in a separator.

**Fix:** no package function writes to disk as a side effect of computing.
`write_segments()` uses `file.path()` and is the only function that writes.

**Test:** none named.

### 13. Duplicate and colliding definitions

**Where:** listed below. **Severity:** low.

- `add_effort_buffer()` is defined twice, in `add_effort_buffer.R:8` and
  `add_effort_offset.R:8`, with different bodies. Whichever file was
  `source()`d last won.
- `ds_data_dmr.R:275,281` binds `newdat$distance` twice, and `names()` at
  `ds_data_dmr.R:286-299` assigns `"distance"` to two positions of the same
  data frame.
- `create_new_track_nos.R:47` writes `dat_nest$new_trackno <- j`, assigning the
  whole column, not `[j]`. It works only because `j == 1` there.

**Fix:** none of these constructs exist in the package. The effort-buffer
functions were not ported (Section 4).

**Test:** none named.

### 14. Functions that were called but never existed

**Where:** listed below. **Severity:** critical; the pipeline could not run.

- `calculate_midpoint()`: `source()`d at `chop_segments.R:16`, called at
  `chop_segments.R:109`. Defined nowhere.
- `crop_data()`: called at `chop_segments.R:113` and `chop_segments.R:124`.
  Defined nowhere.
- `configs.R`, `ds_data_ccb.R`, `ds_data_prep_ccb.R`: `source()`d at
  `detectionFunctionMultipleYears.R:5-8`. Not present.

**Fix:** `segment_midpoints()` and `crop_to_bbox()` were written from scratch;
see [02-implementation.md](02-implementation.md). The missing `*_ccb.R` files
belong to the detection-function work, which is out of scope for v1.

**Test:** none named.

### 15. Exact sighting distances were radial, not perpendicular

**Where:** `compute_distance.R:23`. **Severity:** high, biases every density
estimate in the same direction.

```r
mutate(distance = distHaversine(c(IS_LONG, IS_LAT), c(LONGITUDE, LATITUDE)))
```

**Consequence:** this is the great-circle (radial) distance from the event
position to the animal. Line-transect estimators are defined on the
**perpendicular** distance from the trackline. The two are equal only if the
sighting was logged at the instant it came abeam. Otherwise

```
radial = sqrt(perpendicular^2 + along_track_offset^2)
```

so the recorded distance is always too large, never too small. The bias is
large at survey scales. The fixture carries a whale 132 m off the track, logged
300 m before the aircraft drew level; its radial distance is 327.8 m, two and a
half times the correct value. Inflated distances widen the fitted effective
strip half-width. Density is abundance divided by that width, so the error
becomes an underestimate.

The same file holds an abandoned, commented-out attempt at the circling case
(`compute_distance.R:34-51`). It projects to UTM zone 19 with `sf`, then takes
`matrixStats::rowMins` of the distance from each circling right whale to every
on-effort position on the line. That gives the distance to the *nearest logged
position*: a lower bound on the radial distance, still not a perpendicular one,
and quadratic in the length of the line. `circling_distance()` instead anchors
on the `LEGSTAGE == 3` break-off record and projects onto the line; see step
11e of [02-implementation.md](02-implementation.md).

Two lesser points about the same function:

- It computes nothing unless the day contains a right whale
  (`compute_distance.R:13`), so distances to every other species are missing.
  That is defensible if right whales are the only target, but it is a filter
  buried in a distance calculation, not an argument.
- It writes results back by rebuilding a six-condition logical index over the
  whole data frame inside a triple loop (`compute_distance.R:26-31`), one
  trackline at a time. This is why it is slow on a full season.

**A more serious point: the calculation ran on one programme's data only.** It
is gated on `Tr_SIGHTING == 1` (`compute_distance.R:15`, `:18`) and driven by
`IS_LAT`/`IS_LONG` (`:23`). None of the three is a handbook Table 1 variable,
and none is assigned anywhere in `original/`; every occurrence is a `filter()`
or a `select()`. They are **specific to the CCS aerial survey programme of Cape
Cod Bay**, an artifact of that survey's design.

The original distance calculation therefore silently required CCS-format
input. On a NARWC extract from any other programme the columns are absent and
it fails. On a pipeline that supplies a column of the same name with another
meaning, it runs and returns the wrong subset. With the right-whale day filter,
the set of sightings that ever received a distance was fixed by two conditions,
one of them a survey-programme artifact, not a property of the data.

`distsamp` uses neither. Eligibility for a right-angle distance comes from
handbook-defined columns only (on effort, `LEGTYPE == 2`, `LEGSTAGE == 2`), in
one shared helper. The rule is inspectable, identical across all distance
sources, and runs on data from any programme. `Tr_SIGHTING` encodes the same
intent, so it is a useful *cross-check* on eligibility where it exists, but it
cannot be the mechanism.

`IS_LAT`/`IS_LONG` are not a defect. They record the *aircraft's* position on
the track-line at **initial sighting**, before any circling (settled in
[05-next-steps.md](05-next-steps.md) item 2), which is a better anchor than
anything `distsamp` currently has for a circled animal. That is a feature to
adopt, not a bug to fix; see [05-next-steps.md](05-next-steps.md) item 2.

**Fix:** `exact_distance()` projects the sighting onto the trackline using the
local track bearing. It returns the perpendicular distance, the side, and the
along-track offset, so the size of the correction is visible, not assumed away.

**Tests:** `test-exact.R`: "an along-track offset does not inflate the
distance" and "the sighting logged before it came abeam keeps its true
distance". Both assert the `sqrt` relationship against the radial distance the
original computed.

### 16. Blank columns were filled across survey days and files

**Where:** `DataExploration.R:52`, `:71`. **Severity:** high, corrupts effort
and conditions undetectably.

```r
tidyr::fill(c("LEGTYPE", "LEGSTAGE", "LEGNO", "VISIBLTY", "BEAUFORT",
              "CLOUD", "GLAREL", "GLARER", "WX"), .direction = "downup")
```

NARWC records a value once and leaves it blank until it changes, so filling is
necessary.

**Consequence:** this fill is ungrouped; there is no `group_by()` near it. It
runs the length of the file. The sea state from the last record of one survey
day carries into the next day. A `LEGNO` carries across a `FILEID` boundary
into a different survey. The `up` half carries a value backwards into the
trailing blanks of whatever preceded it. A filled value cannot be told apart
from a recorded one. A `BEAUFORT` of 2 propagated into a day actually flown at
5 puts records on effort that should have been excluded, and nothing downstream
can detect it.

The scripts also disagree on direction. `detectionFunctionMultipleYears.R:55`,
`:67`, and `:76` fill the same nine columns with no `.direction` argument,
which means `"down"`.

**Fix:** `fill_narwc()` groups by `FILEID` and `DATE` by default. It warns
instead of filling across an ungroupable frame, refuses to fill sighting
columns, and reports what it filled. The report separates values carried
*forward*, which are recovered, from values carried *backward*, which are
inferred.

**Test:** `narwcr`'s `test-fill.R`: "nothing crosses a survey day or a file". It asserts
both the correct result and the result the ungrouped version would have
produced.

## 4. Not fixed, by decision

**`add_effort_buffer()`** (`add_effort_buffer.R`, `add_effort_offset.R`) adds
`0.00001` km (one centimetre) to `pt2pt.effort` where consecutive records share
a position, so that segments do not touch exactly. It was already commented out
at its only call site (`chop_segments.R:51`). The cursor-based cutter has no
zero-length-interval problem, so the function was not ported. If a downstream
tool needs strictly positive intervals, that is better handled there than by
perturbing the effort data.

**`dist.rdk()`'s missing radian conversion** is a finding, not a fix; see
Section 5.

## 5. Distance methods

### The Becker and Kenney methods are the same formula

The great-circle method was made selectable at the author's request. This
section states what the choice amounts to.

Becker's `fn.grcirclkm` (`ds_data_dmr.R:70-98`) and Kenney and Winn (1986)
(`ds_data_dmr.R:62-66`) both use the spherical law of cosines. Becker converts
the central angle to degrees and scales by 60 nautical miles per degree times
1.852 km per nautical mile. Kenney scales by 111.12 km per degree. Since
60 x 1.852 = 111.12 exactly, **the two are algebraically identical and return
bit-identical values.** The choice between them cannot change a result.

Both names are kept so that existing scripts and configuration files still read
sensibly, and so an analysis can record which lineage it follows.
`dist_methods()` prints the table. The identity is asserted in
`test-geodist.R`, "Becker and Kenney are the same formula".

**The original `dist.rdk` never computed the Kenney distance.**
`ds_data_dmr.R:62-66` passes decimal degrees straight into `sin()` and `cos()`
without converting to radians, then treats the arc cosine (in radians) as
degrees. The result is not a distance in any unit. The package's `"kenney"`
therefore does not reproduce that function's output; it computes what Kenney
and Winn published. In practice this mattered little, because the driver
scripts passed `dist.method = "eab"`.

**A third method, `"haversine"`, was added and is the default.** The law of
cosines is ill-conditioned at short range: the arc cosine of a number very
close to 1 loses roughly half the available precision. Consecutive positions in
a computer-logged aerial survey are often tens of metres apart, which is in
that regime, and segment effort is built from those intervals. `"haversine"` is
stable there, uses the same sphere and the same 111.12 km per degree, and
agrees with the other two to well under a millimetre at all survey scales. This
is asserted over 200 random short displacements in `test-geodist.R`.
`"becker"` and `"kenney"` remain available and give results indistinguishable
at any scale the data can support.

## 6. References

Full citations: [06-references.md](06-references.md).
