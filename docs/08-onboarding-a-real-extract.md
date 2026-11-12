# Onboarding a real extract

*C. H. Ross. 2026-11-12. Distributed with the package source.*

## 1. Scope

This chapter sets out the order in which a new dataset is brought into the
pipeline, what to check at each step, and the traps that have been hit.

Everything in this package was built against a synthetic fixture generated from
handbook Figure 2. A real NARWC extract fails in ways a fixture cannot, and it
fails *quietly*: the pipeline runs and returns numbers that are wrong by a
factor.

The numbers quoted are from a 1.4-million-record aerial extract worked through
in August 2026 (the "worked extract"). They are given because a real magnitude
is more useful than a caution.

## 2. The rule this document exists for

**The failure mode is a wrong number that looks reasonable, not a crash.**
Effort is the denominator of density, so anything that inflates effort deflates
density proportionally, with no warning and no `NA`. Every check below exists
because something produced a plausible wrong answer.

The traps, and what they caused:

| Trap | Magnitude | Section |
|---|---|---|
| A column judged present or absent for the whole file | `LATITUDE` emptied on 3,754,148 records, leaving one era | 4 |
| Vessel position read instead of the plane's GPS | the vessel track was segmented | 5 |
| Altitude in feet read as metres | every right-angle distance overstated by 3.28 | 5 |
| Clock-format times coerced to numbers | `TIME` emptied on all 1,394,556 records | 5 |
| `LEGNO` blank between change points | `NA` on 1,111,289 of 1,394,556 records | 7 |
| `fill_narwc()` defaults | 1,072,415 values back-filled, including 114,281 `ALT` | 7.1 |
| `LEGSTAGE` recorded only on change | 1,928 of 2,280 on-effort census sightings (85%) excluded | 7.2 |
| A constant `FILEID` | 337.8 km of effort where 8.9 km is correct (38x) | 8 |
| A single angle column with a side flag | 2,503 angles recovered, against zero in `ANGLEL`/`ANGLER` | 9 |

## 3. Run the pre-flight first

```r
res <- diagnose_pipeline("extract.csv", days = 1)
```

`days = 1` diagnoses the first survey day only, so a large extract is checked in
seconds. Whole days are taken, never a sample of records. Effort and
segmentation are computed from consecutive positions along a line, so a random
subset would report distances across gaps created by the sampling.

Read the report top to bottom before running anything else. The rest of this
chapter explains its lines.

## 4. An archive may be several archives

A NARWC extract can be several surveys concatenated, each era recording the same
variable in a *different column*. One real archive, 5,148,704 records spanning
1844-2026, splits like this:

| variable | recent era | older era |
|---|---|---|
| position | `TrkLatitude`/`TrkLongitude` | `LATITUDE`/`LONGITUDE` |
| date | `Date_UTC` | `YEAR`/`MONTH`/`DAY` |
| clock | `TrkTime_UTC` | `TIME(UTC)` |
| event | `Event` | `EVENTNO` |

The counts were complementary, not overlapping: 1,394,560 and 3,754,144.

`narwcr` fills each canonical column from whichever source covers each record.
Judging a column present or absent for the *whole file* is the mistake. It
caused four separate failures on that archive. The worst emptied `LATITUDE` on
3,754,148 records, which `drop_missing_position` then deleted, leaving only the
GPS-logger era. The result looked like a clean two-year dataset and matched a
different file record for record.

**Check the row count and the date span first.** A 5-million-row file that
reads as 1.4 million has lost an era, not a few bad records.

## 5. Reading: check which columns the pipeline is using

```r
narwcr::narwc_column_mapping(dat)
```

Four things have gone wrong here on real data.

| Problem | What happened | Current handling |
|---|---|---|
| **The plane's GPS versus the vessel's position** | A file covering both a vessel and an aircraft may carry `TrkLatitude`/`TrkLongitude` *and* a plain `LATITUDE`/`LONGITUDE`. These are not two spellings of one thing: the `Trk*` family is the receiver's track log, and the plain columns are the position recorded for the platform. narwcr's rule was "a correctly named column always wins", so the plain column won and **the package segmented the vessel track**. | `Trk*` takes precedence, the displaced column is kept as `LATITUDE_ORIGINAL`, and the swap warns. `prefer_source = FALSE` turns it off. |
| **`LEGTYPE_BK`** | A MEMDR-era quirk. Where a file carries both, `LEGTYPE_BK` is the leg type to believe. | The plain column is kept as `LEGTYPE_ORIGINAL`. |
| **Altitude in feet** | `ALT` is metres throughout (handbook 8.A.1) and feeds `perp_distance()`. A column named `TrkAltitude_ft` or `ALTFT` read as metres overstates every right-angle distance by 3.28. | Feet-named columns are converted by 0.3048, and the multiplier is recorded in `narwc_column_mapping()$factor`. Check that column on any new file. |
| **Clock-format times** | `as.numeric("12:00:00")` is `NA`, silently. On the worked extract this emptied `TIME` on all 1,394,556 records. | `parse_narwc_time()` reads clocks and full timestamps. Any numeric coercion that empties a column which had values now warns. That warning means a column arrived in a format the schema did not expect. |

## 6. Validation: which findings matter

```r
f <- narwcr::validate_narwc(dat)   # handbook rules only
f <- distsamp::validate_narwc(dat) # plus the distance-sampling checks
```

`severity` is the triage:

| Severity | Meaning |
|---|---|
| `error` | A required column is missing or empty. |
| `warning` | Something that changes results. |
| `note` | Something to know. |

Two notes are usually benign:

- `legstage_line_not_closed`: normal for a line abandoned for weather or
  re-flown later.
- `columns_outside_handbook` naming `*_ORIGINAL` columns: these are the
  displaced positions narwcr deliberately keeps.

`missing_values` on `LEGTYPE` needs attention. Those records cannot be
identified as census track, so they contribute no effort and no detections. The
exclusion is silent rather than a decision.

## 7. Line identity: the step most likely to be missing

`LEGNO` identifies a survey line. `make_leg_id()` builds `LEGNO3` from it.
`LEGNO3` is what effort is grouped by and what `segment_survey()` cuts into
segments. If `LEGNO` is absent, a whole day collapses into one occupation and
**segments run straight across the transits between lines**.

Real extracts record leg state at change points and leave it blank in between.
On the worked extract, `LEGNO` was `NA` on 1,111,289 of 1,394,556 records,
including 405,134 of the 610,420 census records.

```r
c(rows = nrow(dat),
  legno_na = sum(is.na(dat$LEGNO)),
  legno_distinct = length(unique(dat$LEGNO[!is.na(dat$LEGNO)])))

with(dat[!is.na(dat$LEGSTAGE) & dat$LEGSTAGE == 1, ],
     c(begin_rows = length(LEGNO), legno_present = sum(!is.na(LEGNO))))
```

If `LEGNO` is present on the begin-line records, the gap is a fill, not a
repair.

### 7.1 The fill trap

**Do not run `fill_narwc()` with its defaults for this.** Two of its defaults
are wrong for repairing line identity, and both were hit:

```r
# WRONG for this purpose
filled <- narwcr::fill_narwc(dat)

# Right
filled <- narwcr::fill_narwc(dat, columns = "LEGNO", direction = "down")
```

`direction` defaults to `"downup"`, which infers state for records *before* the
first recorded value in a group. On the worked extract that back-filled
1,072,415 values, including **114,281 `ALT` values**. A fabricated altitude
produces a fabricated perpendicular distance. It also back-filled `GLAREL`,
`GLARER`, `WX`, `BEAUFORT` and `VISIBLTY`, attributing observing conditions to
records taken before anyone recorded them.

The default column set also includes `LEGSTAGE`, which filled 1,242,722 values.
`LEGSTAGE 1` is "begin line": an event, not a state. Carrying it forward stamps
`1` across continuation rows, in effect claiming the line began a thousand
times. Since `1 → 1` is not an allowed transition, this manufactures the
sequence warnings it appears to fix.

### 7.2 State recorded once is not state missing everywhere

`LEGSTAGE` is written when it *changes*, so a record taken mid-line often has
none. `on_effort_census_rows()` requires `LEGSTAGE == 2`, because handbook
8.A.31 restricts a right-angle distance measurement to records continuing a
census line. On the worked archive **1,928 of 2,280 on-effort census sightings
had no code at all**. As a result, 85% of the detections that could have
informed a detection function were excluded for something nobody wrote down.

```r
legs <- narwcr::make_leg_id(dat)
legs <- narwcr::fill_legstage(legs)
```

`fill_legstage()` walks the state machine of handbook 8.A.20. After a begin, a
continue or a resume, the line is continuing, so those records take `2`. After a
break-off the aircraft is circling; after an end-line the line is over; before
the first event nothing is known. All three keep their `NA` and stay
ineligible. This is correct, not merely conservative: a detection made while not
searching the line breaks the distance-sampling assumptions, not just the
bookkeeping.

This is not `fill_narwc(columns = "LEGSTAGE")`, which carries the *value*
forward (Section 7.1).

### 7.3 Reading `legstage_sequence` warnings

These warnings usually indicate missing `LEGNO`, not bad `LEGSTAGE`. The check
groups records into occupations by `LEGNO3`. With `LEGNO` absent, two stages
hours apart on different lines are read as consecutive, so a line beginning at
`1` looks like an illegal transition from the previous line's `4`. **Fix line
identity before touching `LEGSTAGE`.**

### 7.4 After filling

```r
d2 <- narwcr::make_leg_id(filled)
c(begins = sum(!is.na(d2$LEGSTAGE) & d2$LEGSTAGE == 1),
  occupations = length(unique(d2$LEGNO3)))
```

These two counts should agree, unless a line was genuinely flown more than once.

**Filling introduces one hazard.** If a line is flown, left, and re-flown the
same day, filling `LEGNO` down bridges the gap. `LEGNO3`'s run-length counter
then merges both occupations, because the value no longer has a break to
detect. Compare the two counts above to rule this out. If more records stay `NA`
than the gaps explain, whole days carry no `LEGNO` at all. Filling cannot fix
those days, because there is nothing to carry forward.

## 8. Effort: the two ways it inflates

**A constant `FILEID`.** `LEGNO3` increments only when `LEGNO` changes. When the
last line of one day and the first line of the next share a `LEGNO`, only
`FILEID` separates them, and some extracts carry one value on every row. The
ferry between the days is then counted as on-effort track. Measured on a
two-day frame: 337.8 km where 8.9 km is correct, a 38x overstatement.
`point_to_point_effort()` now includes `DATE` in its default grouping.
`diagnose_pipeline()` reports the totals with and without `DATE`, so the size of
the difference on a given file is measured rather than assumed.

**Records silently off effort.** `flag_effort()` cannot distinguish "criterion
failed" from "criterion does not apply". A vessel record, which cannot meet an
altitude criterion, is therefore dropped rather than handled.
`diagnose_pipeline()` prints the per-criterion breakdown, which is the only way
to see which criterion excluded what.

Where the shipboard records are the survey rather than a contaminant,
`prepare_survey(platform = "vessel")` handles them instead of dropping them. It
passes `max_alt_m = NULL`, meaning the criterion does not apply, rather than a
ceiling that no record with a missing altitude can clear. See
[09-shipboard-surveys.md](09-shipboard-surveys.md).

## 9. Distances the schema does not name

The handbook records a declination angle in `ANGLEL` or `ANGLER`, by side. Some
programmes keep one angle column and a separate left/right flag. `narwcr` does
not infer this from a column name: a column called `Decl_Angle` might hold a
declination, an inclination or a bearing.

```r
dat <- narwcr::read_narwc(path,
                          extra_columns = c("Decl_Angle", "Left_or_Right"))
dat <- narwcr::angles_from_declination(dat, "Decl_Angle", "Left_or_Right")
```

On the worked archive this recovered 2,503 angles, against zero in
`ANGLEL`/`ANGLER`. In that file only about 4,000 of 51,363 sightings carried any
distance at all.

### 9.1 Two sources check each other

Where a sighting has both a declination angle and an exact position, the two
distances are computed by independent routes (`ALT / tan(angle)` versus a
projection onto the trackline) and should agree:

```r
d <- distsamp::sighting_distances(air, sources = "angle")$distance
e <- distsamp::sighting_distances(air, sources = "exact")$distance
both <- !is.na(d) & !is.na(e)
c(n = sum(both), median_diff_m = median(abs(d[both] - e[both])))
```

They agreed to **0.34 m across 2,310 pairs** on the worked archive. A constant
offset indicates the altitude is in the wrong unit. Scatter indicates one source
is unreliable. This is the strongest single check available. Repeat it whenever
the reading changes.

## 10. Measured versus reconstructed effort

Where the file carries `TrkDist_m`, narwcr keeps it as `TRKDIST` in metres, and

```r
point_to_point_effort(dat, source = "recorded")
```

uses the distance the receiver measured since the previous fix instead of the
great circle between consecutive positions. The handbook gives the reason
(8.A.10): the farther apart the fixes, the less a straight line between them
reconstructs the track flown. A computed distance is a chord; the recorded one
followed the aircraft.

The default is still `"computed"`, because changing it would change every effort
number already produced. `diagnose_pipeline()` prints both totals and their
ratio. A ratio close to 1 means the fixes are dense enough for the
reconstruction. A ratio well above 1 means the reconstruction is cutting
corners.

## 11. Only then, the pipeline

Re-run the pre-flight on the repaired frame, then the full pipeline. Every
number produced before line identity was fixed treated each day as a single
track. None of those numbers carry over.

## 12. Order of operations

| Step | Function | Check or reason |
|---|---|---|
| 1 | `read_narwc(extra_columns = )` | Check the row count against the file, the column mapping, the conversion factors, and any `*_ORIGINAL` column. |
| 2 | `angles_from_declination()` | Only if the file keeps one angle column and a side. |
| 3 | `validate_narwc()` | Triage by severity. |
| 4 | `make_leg_id()` | Confirm occupations against begin-line records. |
| 5 | `fill_legstage()` | After 4, because it needs `LEGNO3`. Before 7, because it is what makes records eligible. |
| 6 | `classify_platform()` | Split aerial from vessel, and filter *after* `make_leg_id()`, never before. Decide which of the two is being analysed: `platform` carries that decision through the effort criteria and the distance sources together. |
| 7 | Correct the altitude units if needed | After the platform split, since only the aerial records are in feet, and exactly once. |
| 8 | `flag_effort()` | Read the per-criterion breakdown. |
| 9 | `point_to_point_effort()` | Compare with and without `DATE`, and against `TRKDIST` if present. |
| 10 | `segment_survey()`, then `detection_data()` | |

`diagnose_pipeline()` runs steps 1, 3, 4, 6, 8, 9 and 10 and reports on each;
step 5 runs inside `segment_survey()`. It does not apply 2 or 7: both are
corrections specific to one file, and every check in this package reports
rather than repairs.
