# Defects found in `original/`, and what was done about them

The method being ported is Becker et al. (2010), *Marine Ecology Progress Series*
413:163–183, `doi:10.3354/meps08696`; the data format is Kenney (2021), NARWC
Reference Document 2021-01. Full citations and what each is relied on for are in
[06-references.md](06-references.md).

Each item names the file and line in `original/`, explains the consequence, and
points at the regression test that now guards it. All line references are to the
code as it stands in `original/`, which is left untouched.

---

## 1. Legacy visibility codes silently discarded all pre-2004 effort

**Where:** `ds_data_prep_dmr.R:82`
**Severity:** high — silently drops data

```r
I2 <- which(dat$VISIBLTY >= 2 & dat$ALT < 366 & dat$BEAUFORT <= 3)
```

`VISIBLTY` carries two different encodings in the same column. Handbook 8.A.37:
the field was originally a one-digit code recording only whether visibility
reached the 2-nautical-mile CETAP standard and, if not, the weather responsible.
In 2004 it was redefined to hold the actual visibility in nautical miles. During
the 2021 archive update the old codes were folded back into `VISIBLTY` **as
negative numbers**:

| Code | Meaning |
|---|---|
| `-1` | clear visibility for at least 2 nautical miles |
| `-2` | less than 2 miles, fog |
| `-3` | less than 2 miles, haze |
| `-4` | less than 2 miles, rain |
| `-5` | less than 2 miles, snow |

So `VISIBLTY >= 2` marks every legacy record as unacceptable — including `-1`,
which records *good* visibility. On a multi-year dataset spanning the 2004
change, every pre-2004 survey line is silently classified as off effort, its
distance never accumulated, and its sightings never counted. Nothing errors; the
analysis simply runs on a fraction of the data.

**Fix:** `visibility_ok()` in `R/effort.R` branches on sign. A `-1` record
asserts only that visibility reached 2 nmi, so it returns `NA` rather than a
false `TRUE` when asked to satisfy a stricter threshold.

**Tests:** `test-effort.R`, "legacy visibility codes are read as codes, not
distances", "a legacy clear code cannot satisfy a stricter threshold", and
"legacy-format effort is not silently discarded".

---

## 2. The last trackline of every dataset was dropped

**Where:** `chop_to_size.R:12`
**Severity:** high — loses data

```r
for(i in 1:(dim(totdist_expand)[1]-1)){
```

The loop stops one row short because its body peeks at `i+1` to detect the end of
a track. The final planned segment is therefore never cut, and since the last
planned segment of the last track is the final row, the last track of the whole
dataset produces no segments at all.

**Fix:** `cut_one_track()` in `R/segments.R` iterates every planned segment and
treats `i == n_seg` as end-of-track — the existing `case5`.

**Test:** `test-segments.R`, "the last track is not dropped" — three tracks in,
three tracks out, with total segment effort equal to total track effort.

---

## 3. Segmentation was not reproducible

**Where:** `compute_num_segs.R:99`, `chop_to_size.R:74`
**Severity:** high — results cannot be reproduced

```r
randnum <- runif(1, 1, numsegs)          # which segment absorbs the leftover
coinflip <- round(runif(n = 1, ...))     # over- or under-shoot the target
```

Both draws are unseeded, so no two runs produce the same segments and no
published result can be regenerated.

**Fix:** `segment_survey(seed = )` threads a seed through both. Both draws happen
inside one `withr::with_seed()` block. When no seed is given,
`withr::with_preserve_seed()` is used instead, so the caller's RNG stream is
never disturbed either way.

**Tests:** `test-segments.R`, "segmentation is reproducible under a seed" and
"segmenting does not disturb the caller's RNG stream".

---

## 4. The leftover could never land on the final segment

**Where:** `compute_num_segs.R:99-105`
**Severity:** medium — systematic bias

```r
randnum <- runif(1, 1, numsegs)
randpick <- floor(randnum)
expand$tgtdist[randpick] <- extrabit
```

`runif(1, 1, n)` draws from `[1, n)`, so `floor()` returns `1` to `n-1` and never
`n`. The segment that absorbs a track's leftover distance is therefore never the
last one. Since the leftover segment is systematically shorter (or longer) than
the rest, this puts a small but consistent spatial bias into every track: the odd
segment is never at the far end.

**Fix:** `sample.int(n_seg, 1L)` in `plan_one_track()`.

**Test:** `test-segments.R`, "the leftover can land on any segment, including the
last" — 200 seeds, asserting all five positions occur.

---

## 5. The chopping loop was quadratic

**Where:** `chop_to_size.R:128-137`
**Severity:** medium — performance

```r
dat_chopped <- dat_chopped |> rbind(dat_onedate_onelegno)
dat_chopped_4join <- dat_chopped |> dplyr::select(-seg_eff, -seg_no) |> ...
dat_nest_expand <- dat_nest_expand |> anti_join(dat_chopped_4join)
```

Every iteration `rbind`s onto an accumulating frame and then `anti_join`s that
entire growing frame against the entire remaining dataset, to work out which rows
are still unconsumed. On a season of computer-logged survey data — hundreds of
thousands of records, thousands of segments — this dominates the runtime.

The `anti_join` is also unkeyed, so it matches on every shared column. Two
genuinely distinct records with identical values would remove each other.

**Fix:** `cut_one_track()` keeps a per-track row cursor. Each track's records are
visited once; results are combined with a single `bind_rows()` at the end.

---

## 6. `1:length(x)` iterates backwards on empty input

**Where:** `ds_data_dmr.R:112`, `ds_data_dmr.R:124`, `ds_data_dmr.R:255`,
`create_new_track_nos.R:30`, `create_new_track_nos.R:41`, `compute_num_segs.R:33`
**Severity:** medium — wrong results or an error on an empty subset

`1:length(x)` yields `c(1, 0)` when `x` is empty, so the loop body runs twice
with nonsensical indices instead of not running at all. This surfaces whenever a
species is absent from a season, a date has no qualifying tracklines, or a filter
empties a group.

**Fix:** `seq_len()` and `seq_along()` throughout.

**Test:** `test-segments.R`, "empty and single-record inputs do not error".

---

## 7. A break in effort produced one spurious track per record

**Where:** `create_new_track_nos.R:76-82`
**Severity:** low — cosmetic, but makes `new_trackno` hard to interpret

The original incremented `new_trackno` on *every* record where the current and
next records were both off effort. A five-record circling excursion therefore
produced four new track numbers rather than one, and — because the increment
stopped one record before the excursion ended — left the last two off-effort
records attached to the track that resumed *afterwards*.

**Fix:** `track_index()` in `R/tracks.R` smooths isolated single off-effort
records, then starts a new track at each change of effort state. A sustained
break yields three tracks: effort before, the break, effort after. The middle one
carries no effort and is dropped by `track_effort()`. Each surviving track
contains only on-effort records.

**Test:** `test-tracks-midpoints.R`, "a break in effort starts a new track" and
"multi-record circling splits the track, and the fixture shows it".

---

## 8. Cutting error accumulated into the final segment

**Where:** `chop_to_size.R:52-125`
**Severity:** medium — segments outside the stated tolerance band

Each segment's target was measured from wherever the previous segment happened to
end. Because a cut can only fall on a record boundary, every segment lands a
little over or under its target, and the errors compound down the track. On a
long track made of many small records the arrears all land on the final segment,
which `case5` makes absorb everything remaining. The result is a final segment
well outside the `[0.5s, 1.5s]` band the `segtol` logic is supposed to guarantee.

This was found by the test suite, not by reading: the tolerance-band test failed
on a 111 km track of 0.56 km records.

**Fix:** `cut_one_track()` measures cut points as a cumulative distance from the
**start of the track** (`cut_at <- cumsum(plan_i$tgtdist)`), so each segment's
effective target absorbs the previous segment's error instead of passing it on.
The planning logic, the coin flip, and `case5` are unchanged.

**Tests:** `test-segments.R`, "segment lengths stay inside the tolerance band"
(15 seeds) and "cutting error does not accumulate down a track" (10 seeds on a
401-record track).

---

## 9. Pilot sightings were counted in density estimates

**Where:** `ds_data_dmr.R:257-260`
**Severity:** medium — inflates counts

```r
I <- which(dat$SPECCODE == spp[i] & dat$LEGSTAGE != 7 & (dat$IDREL == 2 | dat$IDREL == 3))
```

`LEGSTAGE == 7` (a sighting found in a vertical photograph) is excluded, but
`LEGSTAGE == 6` is not. Handbook 4.2, discussing event 6 of the worked example,
is explicit: a sighting made by the pilot "cannot be included in a density
estimate, therefore it is assigned a different LEGSTAGE". It did not arise from
the standard search effort that the detection function describes, so including it
inflates the count without a matching increase in effort.

**Fix:** `segment_sightings(legstage_exclude = c(6, 7))`, overridable.

**Tests:** `test-read-validate-sightings.R`, "pilot and photograph sightings are
excluded by default" and "excluded LEGSTAGEs can be overridden".

---

## 10. Circling sightings were hard-coded to right whales

**Where:** `process_obs_data.R:49-50`, `process_obs_data.R:153`
**Severity:** medium — wrong for any other species

```r
riwh_circle <- dat_nest_expand |> filter(SPECCODE =='RIWH') |> ...
num_anms <- ... filter(SPECCODE == "RIWH")   # "needs to be modified if looking at other whales"
```

Every circling right whale was attached back to its segment; circling sightings
of every other species were discarded. That is neither the handbook rule nor
correct for a multi-species analysis — and the code carries a comment saying so.

Handbook 4.2 (event 11) states the actual CETAP rule: counted with the original
on-effort group are further individuals *of the same species* seen while
circling; groups of *other* species not originally seen from the track-line are
new off-effort sightings.

**Fix:** `attach_circling_sightings(mode = )` with `"same_species"` (default,
implementing the handbook rule), `"all"`, and `"none"`.

**Test:** `test-read-validate-sightings.R`, "circling sightings are attached, and
only for the same species".

---

## 11. Study parameters hard-coded mid-function

**Where:** `ds_data_dmr.R:243-249`
**Severity:** medium — silently wrong for any other study

```r
dat$Region.Label <- "MyStratum"
dat$Area <- 5811   # sq km, this could be put in the function call.
```

The survey area is a magic number in the middle of a function, with a comment
acknowledging it should be an argument. Any analysis of a different area or year
inherits 5,811 km² unless the user notices.

**Fix:** these are gone from the segmentation core entirely. Area and region are
properties of a study design, not of a segmentation, and belong to the abundance
estimation step. Species selection, which was equally hard-coded, is the
`species` argument.

---

## 12. Files written by building and evaluating strings

**Where:** `ds_data_dmr.R:341-387`
**Severity:** low — fragile

```r
cmd = paste("write.csv(effort_summary, file = '", target.dir, "effort_summary_", fn, ".csv'", ...)
eval(parse(text = cmd))
```

Four `write.csv` calls built as strings and evaluated. A quote or apostrophe in a
path breaks it, and the concatenation assumes `target.dir` ends in a separator.

**Fix:** nothing in the package writes to disk as a side effect of computing.
`write_segments()` uses `file.path()` and is the only function that writes.

---

## 13. Duplicate and colliding definitions

**Severity:** low

- `add_effort_buffer()` is defined twice, in `add_effort_buffer.R:8` and
  `add_effort_offset.R:8`, with different bodies. Whichever file was `source()`d
  last won.
- `ds_data_dmr.R:275,281` binds `newdat$distance` twice, and `names()` at
  `ds_data_dmr.R:286-299` assigns `"distance"` to two positions of the same data
  frame.
- `create_new_track_nos.R:47` writes `dat_nest$new_trackno <- j`, assigning the
  whole column rather than `[j]`. It survives only because `j == 1` there.

**Fix:** none of these constructs exist in the package. The effort-buffer
functions were not ported at all — see below.

---

## 14. Functions that were called but never existed

**Severity:** critical — the pipeline could not run

- `calculate_midpoint()` — `source()`d at `chop_segments.R:16`, called at
  `chop_segments.R:109`. Defined nowhere.
- `crop_data()` — called at `chop_segments.R:113` and `chop_segments.R:124`.
  Defined nowhere.
- `configs.R`, `ds_data_ccb.R`, `ds_data_prep_ccb.R` — `source()`d at
  `detectionFunctionMultipleYears.R:5-8`. Not present.

**Fix:** `segment_midpoints()` and `crop_to_bbox()` were written from scratch;
see [02-implementation.md](02-implementation.md). The missing `*_ccb.R` files
belong to the detection-function work, which is out of scope for v1.

---

## Not fixed, by decision

**`add_effort_buffer()`** (`add_effort_buffer.R`, `add_effort_offset.R`) adds
`0.00001` km — one centimetre — to `pt2pt.effort` where consecutive records share
a position, to stop segments touching exactly. It was already commented out at
the only call site (`chop_segments.R:51`). The cursor-based cutter has no
zero-length-interval problem to work around, so it was not ported. If a
downstream tool turns out to need strictly positive intervals, that is better
handled there than by perturbing the effort data.

**`dist.rdk()`'s missing radian conversion** is not a fix so much as a finding —
see the next section.

---

## The Becker and Kenney methods are the same formula

This came up because you asked for the choice to be selectable. It is, and here
is what the choice amounts to.

Becker's `fn.grcirclkm` (`ds_data_dmr.R:70-98`) and Kenney and Winn (1986)
(`ds_data_dmr.R:62-66`) are both the spherical law of cosines. Becker converts
the central angle to degrees and scales by 60 nautical miles per degree times
1.852 km per nautical mile; Kenney scales by 111.12 km per degree. Since
60 x 1.852 = 111.12 exactly, **the two are algebraically identical and return
bit-identical values.** Choosing between them cannot change a result.

Both names are kept anyway, so existing scripts and configuration files keep
reading sensibly and so an analysis can record which lineage it meant to follow.
`dist_methods()` prints the table, and the identity is asserted in
`test-geodist.R`, "Becker and Kenney are the same formula".

Two things are worth knowing on top of that:

**The original `dist.rdk` never computed the Kenney distance.**
`ds_data_dmr.R:62-66` passes decimal degrees straight into `sin()` and `cos()`
with no conversion to radians, and then treats the arc cosine — in radians — as
though it were degrees. The result is not a distance in any unit. The package's
`"kenney"` will therefore not reproduce that function's output; it computes what
Kenney and Winn actually published. In practice this mattered less than it might
have, because `dist.method = "eab"` was what the driver scripts passed.

**A third method was added, and is now the default.** The law of cosines is
ill-conditioned at short range: the arc cosine of a number very close to 1 loses
roughly half the available precision. Consecutive positions in a computer-logged
aerial survey are often only tens of metres apart, which is squarely in that
regime, and those tiny intervals are exactly what segment effort is built from.
`"haversine"` is stable there, uses the same sphere and the same 111.12 km per
degree, and agrees with the other two to well under a millimetre at all survey
scales — asserted over 200 random short displacements in `test-geodist.R`. It is
the default for that reason; `"becker"` and `"kenney"` remain available and
produce results indistinguishable at any scale the data can support.


---

Full citations: [06-references.md](06-references.md).
