# Onboarding a real extract

Everything in this package was built against a synthetic fixture generated from
handbook Figure 2. A real NARWC extract fails in ways a fixture cannot, and it
fails *quietly* — the pipeline runs, returns numbers, and the numbers are wrong
by a factor.

This is the order to bring a new dataset in, what to look at, and the traps
that have actually been hit. The numbers quoted are from a 1.4-million-record
aerial extract worked through in August 2026; they are here because a real
magnitude is more use than a caution.

## The rule this document exists for

**A wrong number that looks reasonable is the failure mode, not a crash.**
Effort is the denominator of density, so anything that inflates effort deflates
density proportionally, with no warning and no `NA`. Every check below exists
because something produced a plausible wrong answer.

## 0. Run the pre-flight first

```r
res <- diagnose_pipeline("extract.csv", days = 1)
```

`days = 1` diagnoses the first survey day only, so a large extract is checked in
seconds. It takes whole days, never a sample of records — effort and
segmentation are computed from consecutive positions along a line, so a random
subset would report distances across gaps that are an artefact of the sampling.

Read the report top to bottom before running anything else. The rest of this
document is what its lines mean.

## 1. Reading: is the pipeline even looking at the right columns?

```r
narwcr::narwc_column_mapping(dat)
```

Four things have gone wrong here on real data.

**The plane's GPS versus the vessel's position.** A file covering both a vessel
and an aircraft may carry `TrkLatitude`/`TrkLongitude` *and* a plain
`LATITUDE`/`LONGITUDE`. They are not two spellings of one thing: the `Trk*`
family is the receiver's track log, and the plain columns are the position
recorded for the platform. narwcr's rule was "a correctly named column always
wins", so the plain column won and **the package segmented the vessel track**.
`Trk*` now takes precedence, the displaced column is kept as
`LATITUDE_ORIGINAL`, and the swap warns. `prefer_source = FALSE` turns it off.

**`LEGTYPE_BK`.** A MEMDR-era quirk. Where a file carries both, `LEGTYPE_BK` is
the leg type to believe; the plain one is kept as `LEGTYPE_ORIGINAL`.

**Altitude in feet.** `ALT` is metres throughout (handbook 8.A.1) and feeds
`perp_distance()`. A column named `TrkAltitude_ft` or `ALTFT` read as metres
overstates every right-angle distance by 3.28. Feet-named columns are now
converted by 0.3048 and the multiplier is recorded in
`narwc_column_mapping()$factor`. Check that column on any new file.

**Clock-format times.** `as.numeric("12:00:00")` is `NA`, silently. On the real
extract this emptied `TIME` on all 1,394,556 records. `parse_narwc_time()` now
reads clocks and full timestamps. More generally, any numeric coercion that
empties a column which had values now warns — if you see that warning, a column
arrived in a format the schema did not expect.

## 2. Validation: which findings matter

```r
f <- narwcr::validate_narwc(dat)   # handbook rules only
f <- distsamp::validate_narwc(dat) # plus the distance-sampling checks
```

`severity` is the triage. `error` means a required column is missing or empty.
`warning` means something that changes results. `note` means something to know.

Two notes are routinely benign:

- `legstage_line_not_closed` — normal for a line abandoned for weather or
  re-flown later.
- `columns_outside_handbook` naming `*_ORIGINAL` columns — those are the
  displaced positions narwcr deliberately preserved.

`missing_values` on `LEGTYPE` is worth stopping for. Those records cannot be
identified as census track, so they contribute no effort and no detections —
a silent exclusion rather than a decision.

## 3. Line identity: the step most likely to be missing

`LEGNO` identifies a survey line. `make_leg_id()` builds `LEGNO3` from it, and
`LEGNO3` is what effort is grouped by and what `segment_survey()` chops into
segments. If `LEGNO` is absent, a whole day collapses into one occupation and
**segments run straight across the transits between lines**.

Real extracts record leg state at change points and leave it blank in between.
On the worked extract, `LEGNO` was `NA` on 1,111,289 of 1,394,556 records —
including 405,134 of the 610,420 census records.

```r
c(rows = nrow(dat),
  legno_na = sum(is.na(dat$LEGNO)),
  legno_distinct = length(unique(dat$LEGNO[!is.na(dat$LEGNO)])))

with(dat[!is.na(dat$LEGSTAGE) & dat$LEGSTAGE == 1, ],
     c(begin_rows = length(LEGNO), legno_present = sum(!is.na(LEGNO))))
```

If `LEGNO` is present on the begin-line records, it is a fill, not a repair.

### The fill trap

**Do not run `fill_narwc()` with its defaults for this.** Two of them are wrong
for repairing line identity, and both were hit:

```r
# WRONG for this purpose
filled <- narwcr::fill_narwc(dat)

# Right
filled <- narwcr::fill_narwc(dat, columns = "LEGNO", direction = "down")
```

`direction` defaults to `"downup"`, which infers state for records *before* the
first recorded value in a group. On the worked extract that back-filled
1,072,415 values, including **114,281 `ALT` values** — and a fabricated
altitude produces a fabricated perpendicular distance. It also back-filled
`GLAREL`, `GLARER`, `WX`, `BEAUFORT` and `VISIBLTY`, attributing observing
conditions to records taken before anyone recorded them.

The default column set also includes `LEGSTAGE`, which filled 1,242,722 values.
`LEGSTAGE 1` is "begin line" — an event, not a state. Carrying it forward
stamps `1` across continuation rows, and since `1 → 1` is not an allowed
transition it manufactures sequence warnings rather than clearing them.

### Reading `legstage_sequence` warnings

These are usually a symptom of missing `LEGNO`, not of bad `LEGSTAGE`. The
check groups records into occupations via `LEGNO3`; with `LEGNO` absent, two
stages hours apart on different lines are read as consecutive, so a line
beginning at `1` looks like an illegal transition from the previous line's `4`.
**Fix line identity before touching `LEGSTAGE`.**

### After filling

```r
d2 <- narwcr::make_leg_id(filled)
c(begins = sum(!is.na(d2$LEGSTAGE) & d2$LEGSTAGE == 1),
  occupations = length(unique(d2$LEGNO3)))
```

These should agree, unless a line was genuinely flown more than once.

**One hazard filling introduces:** if a line is flown, transited away from, and
re-flown the same day, filling `LEGNO` down bridges the gap and `LEGNO3`'s
run-length counter merges both occupations, because there is no longer a break
in the value to detect. Compare the two counts above to rule it out. If more
records stay `NA` than the gaps explain, whole days carry no `LEGNO` at all and
there is nothing to carry forward — filling cannot fix those days.

## 4. Effort: the two ways it inflates

**A constant `FILEID`.** `LEGNO3` increments only when `LEGNO` changes, so when
the last line of one day and the first of the next share a `LEGNO`, only
`FILEID` separates them — and some extracts carry one value on every row. The
ferry between the days is then counted as on-effort track. Measured on a
two-day frame: 337.8 km where 8.9 km is correct, a 38x overstatement.
`point_to_point_effort()` now includes `DATE` in its default grouping, and
`diagnose_pipeline()` reports the totals with and without it so the size of the
difference on *your* file is visible rather than assumed.

**Records silently off effort.** `flag_effort()` cannot distinguish "criterion
failed" from "criterion does not apply", so a vessel record — which cannot meet
an altitude criterion — is dropped rather than handled. `diagnose_pipeline()`
prints the per-criterion breakdown, which is the only way to see which
criterion excluded what.

## 5. Measured versus reconstructed effort

Where the file carries `TrkDist_m`, narwcr keeps it as `TRKDIST` in metres and

```r
point_to_point_effort(dat, source = "recorded")
```

uses the distance the receiver measured since the previous fix, instead of the
great circle between consecutive positions. The handbook makes the argument
itself (8.A.10): the farther apart the fixes, the less a straight line between
them reconstructs the track that was flown. A computed distance is a chord; the
recorded one followed the aircraft.

The default is still `"computed"`, because switching it would change every
effort number already produced. `diagnose_pipeline()` prints both totals and
their ratio. Close to 1 means the fixes are dense enough that the
reconstruction is fine; well above 1 means it is cutting corners.

## 6. Only then, the pipeline

Re-run the pre-flight on the repaired frame, then the full pipeline. Every
number produced before line identity was fixed was computed with each day as a
single track, and none of them carry over.

## Order of operations

1. `read_narwc()` — check the column mapping, the conversion factors, and any
   `*_ORIGINAL` column.
2. `validate_narwc()` — triage by severity.
3. `fill_narwc(columns = "LEGNO", direction = "down")` — only if `LEGNO` is
   blank between change points.
4. `make_leg_id()` — confirm occupations against begin-line records.
5. `flag_effort()` — read the per-criterion breakdown.
6. `point_to_point_effort()` — compare with and without `DATE`, and against
   `TRKDIST` if present.
7. `segment_survey()`.

`diagnose_pipeline()` runs 1, 2, 4, 5, 6 and 7 and reports on all of them. It
does not run 3, because filling changes the data and every check in this
package reports rather than repairs.
