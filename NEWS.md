# distsamp 0.1.0

## Handbook version

Cites Version 8 of the NARWC user's guide (Kenney 2023, Reference Document
2023-01, October 2023). The package was originally written against Version 7;
the automated citation check found Version 8 on its first run.

No code-book values changed between the two — `LEGTYPE`, `LEGSTAGE`, `IDREL`,
`TAXCODE`, `STRATUM`, `STRIP`, and the negative `VISIBLTY` codes are identical,
so no behaviour was affected. Section numbers shift by one from `ANGLEL`
onward; all cross-references were remapped. New in Version 8:

* `ANGLEL` and `ANGLER`, declination angles to a sighting, which replaced
  `STRIP` for New England Aquarium surveys from 2022. Carried through as
  optional columns; not yet converted to perpendicular distance.
* `WX` is now available from `narwc_codes("WX")`.

## Perpendicular distances from declination angles

`ANGLEL` and `ANGLER` (handbook 8.A.2) are now interpreted rather than merely
carried through.

* `perp_distance()` converts a declination angle and altitude into a
  perpendicular distance, `ALT / tan(angle)`. The angle is taken with the
  sighting abeam, so it gives the right-angle distance directly.
* `sighting_distances()` applies it across a survey data frame, resolving which
  side of the track the sighting was on. Restricted to on-effort census records
  by default, since 8.A.31 notes angles are sometimes recorded during transits
  and circling for practice.
* `segment_survey()` gains a `detections` table: one row per qualifying
  sighting with `distance`, `side`, `size`, and `seg_id` — the shape
  `Distance::ds()` wants, keyed back to the segments for a density surface
  model. `distance_units` controls metres (default) or km.
* Circling detections appear with a missing `distance`. They count towards
  abundance, but a position logged off the track is not a perpendicular
  distance.
* `validate_narwc()` gains `angle_out_of_range`, `angle_both_sides`, and
  `angle_without_altitude`.

Note that `seg_eff` is in kilometres while distances default to metres; see
`?perp_distance` before passing both to `Distance::ds()`.

## The other two right-angle distance sources

Declination angles only exist from 2022. The archive's older data records
right-angle distance two other ways, and both are now interpreted.

* `narwc_strip_bins()` and `strip_distance()` decode `STRIP` (handbook 8.A.31),
  which gives an *interval* rather than a point. Two code books are in use, and
  which applies depends on the programme, the date, and the aircraft — code 13
  is 1–2 nmi under CETAP and over 4 nmi under NLPSC, and code 5 differs by a
  factor of two, so reading a code with the wrong book is silently wrong. The
  book is chosen from the survey date unless named, and no date and no scheme is
  an error rather than a guess. Every scheme's top bin is open, so `distend` is
  `Inf` and truncation is required before fitting.
* `exact_distance()` computes perpendicular distance from `S_LAT`/`S_LONG`
  (8.A.33, 8.A.34), on the new `gc_bearing()`, `track_bearing()`, and
  `cross_track_distance()`. It **projects the sighting onto the trackline**
  rather than measuring straight to it, and returns the along-track offset so
  the difference is visible. `along` near zero means the two would have agreed.
* `validate_narwc()` gains `exact_position_out_of_range` and
  `exact_position_far_from_event`, which catch a dropped minus sign on `S_LONG`
  and coordinates given in degrees and decimal minutes.

## Distances for sightings made while circling

`circling_distance()` ties a sighting logged during a circle back to the
`LEGSTAGE == 3` break-off record on the census line, and measures from there.

These are usually genuine on-effort detections — the animal was seen from the
track-line, which is why the aircraft left it — and giving them no distance drops
them from the detection function altogether. The ones lost are not a random
sample: they are disproportionately the close or conspicuous groups worth
breaking off for, so removing them thins the near-zero end of the distance
distribution, where a detection function is most sensitive.

* The anchor is the break-off record, or the last record still on the line where
  there is none; `anchor_event` reports which.
* The bearing is the *inbound* heading, not a centred difference. A resume point
  offset from the break-off would otherwise swing it for no good reason.
* Both readings are returned. `radial` is the straight-line distance from the
  break-off point; `distance` is that position projected perpendicularly onto the
  census line, which is what a detection function is defined on; `along` is how
  far back down the line the animal was abeam.
* An exact position is required by default. Without `S_LAT`/`S_LONG` the only
  position on the record is the *aircraft's*, orbiting the animal at a radius
  comparable to the distance being measured. `position = "logged"` permits that
  fallback, and `position_source` records where each position came from.
* These are a weaker source than the other three, since the position is fixed
  minutes after detection and the animal has moved. `detection_data()` will
  exclude them by default.

The *spatial-model* side of this needed no change: `attach_circling_sightings()`
has attributed circling sightings back to their segment since v1, under the CETAP
same-species rule, selected by `segment_survey(circling = )`. Those counts feed
abundance whether or not the sighting carries a usable distance. Excluding
circling sightings from a detection function while including them in a density
surface is a normal and defensible combination, so the two stay separate
arguments.

## One table for `Distance`

`sighting_distances()` now resolves all four sources, and `detection_data()`
turns the result into the flatfile `Distance::ds()` accepts.

* **`sources` is a precedence order, not a set.** The first source that yields a
  distance for a record claims it, and `distance_source` records which. Default
  `c("angle", "exact", "strip")` — the angle first, because it is taken with the
  sighting abeam and so measures the perpendicular distance directly. Reverse it
  to prefer exact positions; where a record has both, they are independent
  measurements and their disagreement checks both.
* **`"circling"` is available but off by default.** Those detections are usually
  real, and dropping them thins the near-zero end of the distribution, but the
  position is fixed after the animal has moved. Ask for it deliberately.
* **`detection_data(x, area = )`** emits `Region.Label` / `Area` /
  `Sample.Label` / `Effort` / `object` / `distance` / `size`, plus
  `distbegin`/`distend` for binned rows and segment covariates on request.
  `area` is required and has no default — it scales abundance directly, and
  `ds_data_dmr.R:248` had 5,811 km² written into the middle of a function.
* **Every segment appears, including those with no detections.** That is how a
  flatfile records effort that produced nothing; dropping those rows would
  remove the denominator.
* **Truncation drops detections and keeps their segments**, effort intact. A
  segment whose only detection is truncated survives as an empty row.
* **Point and interval distances in one table is an error** by default —
  `STRIP` rows are binned and one `ds()` call cannot fit both. Open top bins are
  dropped, since an unbounded bin cannot be fitted at all.
* Everything dropped is reported by name and count, and the report ends with
  `g(0) = 1 is assumed`.

`segment_survey()` gains `distance_sources`, and `detections` carries
`distbegin`, `distend`, and `distance_source`.

**On `g(0)`.** Nothing here corrects for animals submerged when the aircraft
passed, or surfaced and missed. It cannot be estimated from a standard NARWC
extract, which records neither dive data nor the double-observer structure
mark-recapture needs. Apply a correction from external sources at the abundance
step, with its standard error propagated. `?detection_data` says so where someone
about to fit a model will see it.

## Filling blank survey-state columns

NARWC records a value once and leaves it blank until it changes — `LEGTYPE` is
entered as `2` at the start of a census line and the rows beneath are empty until
the leg type changes. `fill_narwc()` carries that state forward.

* **Grouped by `FILEID` and `DATE` by default.** The scripts this was ported from
  filled ungrouped, so a sea state from the last record of one survey day carried
  into the next, and a leg number crossed a `FILEID` boundary into a different
  survey. A frame with neither column warns rather than filling across
  everything.
* **Sighting columns are refused, not merely left out of the default.** Carrying
  `SPECCODE` and `NUMBER` forward would replicate one group of three right whales
  onto every row until the next sighting. `narwc_never_fill()` lists what is
  refused and why; asking for one is an error.
* **The report separates recovery from inference.** `"downup"` fills down and
  then up, so its backward fills are the values before the first record of a
  group — state that was never logged. Those are counted separately, because only
  the forward fills recover something.
* `narwc_fill_columns()` is the default set, and documents the distinction
  between state that persists and measurements that belong to one record.

Note that `LEGSTAGE` is the least safe of the defaults: if a file records `1` and
leaves the continuation blank, filling down marks the whole line "begin line"
rather than `2`, and on-effort eligibility is `LEGSTAGE == 2`. Check the
per-column counts against what you expect.

## Columns from other survey programmes

A NARWC extract is not the only shape this data arrives in. Survey programmes add
their own derived columns, and `read_narwc()` used to discard every column it did
not recognise **without saying so** — a Center for Coastal Studies file lost
`IS_LAT`, `IS_LONG`, and `Tr_SIGHTING` silently, and `extra_columns` only helped
if you already knew what to name.

* `read_narwc()` now reports dropped columns by name, and names the survey
  programme when they match a registered one. `quiet = TRUE` suppresses it.
* `narwc_profiles()` is the registry: programme, column, meaning, the role
  `distsamp` gives it, and how confident that meaning is.
  `read_narwc(profile = "ccs")` keeps a programme's columns.
* `validate_narwc()` gains `columns_outside_handbook`, for data frames that never
  went through `read_narwc()`.

**A profile is never applied because a column name matched.** `Tr_SIGHTING` means
"sighting made from the track-line" in a CCS file, and nothing stops another
programme using that name for something else — a column name is not a contract
between programmes. `read_narwc()` will say what a file looks like; naming the
profile is the caller's decision. Keeping a profile's columns also does not
interpret them: every registry entry is currently `role = "passthrough"`.

CCS is the only profile registered so far, and is an exception rather than a
representative case. Adding one needs a data dictionary, not just a column list;
entries whose meaning was inferred from the name are marked `unconfirmed`.

## Reading real extracts

Found by testing against real data rather than the fixture.

* **Column names no longer have to match exactly.** Matching ignores case and
  separators, so `Event`, `event_no`, and `EventNo` all reach `EVENTNO`. The
  alias table gained roughly twenty entries — `TIME_UTC`, `GMT`, `TIME_LOC`,
  `Field_SIGHTNO`, `Sea_State`, `Event_No` and others.

  It is **not** fuzzy matching: nothing is guessed by edit distance, nothing is
  renamed onto a canonical column that is already present, and inferred matches
  are reported. Exact alias-table entries stay silent, since announcing `LAT_DD`
  on every read would bury the ones worth checking.

* **`TIME` is taken from whichever clock the file records** — `TIME`, then a UTC
  column (`TIME_UTC`, `GMT`, `TIME_GMT`), then a local one. A file carrying both
  lands on UTC.

* **Records with no position are dropped**, and reported. Left in they do not
  announce themselves: `gc_distance()` returns `NA` and
  `point_to_point_effort()` turns that into a zero, so the record silently
  counts as zero distance flown. `drop_missing_position = FALSE` keeps them.

* **`extra_columns` takes glob patterns**, so `"Trk*"` keeps a family of columns
  whose exact names differ between extracts.

## Reading from cloud storage

* `narwc_cloud_roots()` — where OneDrive and Google Drive sync to on this
  platform. Only documented locations are checked; nothing is searched for.
* `narwc_fetch()` — resolves a Google Drive id or URL, or a path within an
  authenticated OneDrive or SharePoint drive, to a local file path, so it
  composes with `read_narwc()`. A local path is returned unchanged, so wrapping
  one is safe.

**`distsamp` never handles credentials.** You authenticate in your own session —
`googledrive::drive_auth()`, or `Microsoft365R::get_business_onedrive()` — and
pass the result. No argument accepts a token, and nothing is stored or cached.
That is also why OneDrive takes a drive object rather than a URL: resolving a
SharePoint link means knowing whose tenant it is, and that is not something to
guess at.

Usually none of this is needed — both clients sync to a local folder, and a file
inside one is an ordinary path `read_narwc()` already reads.

## Survey lines, sequence checks, and a quadratic term removed

* `line_effort()` and `reflight_summary()` — effort per survey line rather than
  per continuous track, which is what `segs$tracks` cannot tell you. A line
  started, abandoned, and flown again is two *occupations* of one line;
  `combine = "line"` sums them.

  Two defects came with the port from `ds_data_dmr.R`. It reduced on the
  occupation id rather than the line id, so it never combined re-flights — the
  one thing that table existed to do. And its "% of lines reflown" measured the
  share of *occupations* that were repeats, which is a different number; the
  original carried the comment "ask dan about this". Both rates are now
  reported, `prop_lines_reflown` and `prop_occupations_repeat`, named for what
  they measure.

* `validate_narwc()` gains `legstage_sequence`, `legstage_break_off_unresumed`,
  and `legstage_line_not_closed`. Handbook 8.A.20 gives `LEGSTAGE` as a
  progression — a line begins (1), continues (2), may break off to circle (3)
  and resume (4), and ends (5) — and only the code book was being checked.
  Nothing may follow an end-line, a break-off must be resumed, and a line must
  begin with 1. The last check is a note rather than a warning because a line
  abandoned for weather legitimately has no end-line; the fixture contains one.

* **`attach_circling_sightings()` was quadratic.** It scanned the segment table
  and then the whole point table once per circling sighting to apply the
  same-species rule. At a low circling rate that is invisible; with every
  sighting circled, doubling the data multiplied the time by 2.6 then 2.9, on
  its way to 4. Right whale surveys circle often, so this was a real path.
  Replaced with a rolling lookup per day and a membership set built once: 7.5x
  faster at 100k records, and linear.

* Profiled end to end on synthetic seasons up to 242k records — about twenty
  seconds, linear throughout. `data-raw/make-season.R` generates them, and
  `docs/04-verification.md` records the numbers so a future change can be
  checked against them.

## Diagnostic plots

`plot()` methods on `distsamp_segments`, behind `Suggests` on `ggplot2`. Each
returns an ordinary `ggplot` object.

* `plot(segs)` — the track flown, segment midpoints sized by effort, and the
  sightings. A segmentation gone wrong is usually obvious here.
* `plot(segs, what = "tracks")` — positions coloured by `new_trackno`, faceted by
  date. Shows whether track splitting did the right thing.
* `plot(segs, what = "effort")` — segment lengths against the target, with the
  tolerance band marked.
* `plot(segs, what = "distances")` — the detection-function diagnostic, with the
  documentation spelling out that a dip in the first bin may be a blind spot
  rather than an absence of animals, and that a smooth curve says nothing about
  `g(0)`.

`species` filters the views that draw sightings.

`coastline = TRUE` draws Natural Earth land under the map views, and `coastline`
also takes your own `sf` object — which is the right answer at bay scale, since
Natural Earth's medium coastline is 1:50m and coarse enough to put a shore-hugging
survey apparently on land. Tile basemaps remain out of scope: they need a tile
source and network access, which a diagnostic plot should not.

## Vignettes

* `segmenting-narwc-data` — the full walkthrough.
* Both vignettes extended: `segmenting-narwc-data` gains sections on columns
  from other survey programmes, filling blank state columns, all four
  right-angle distance sources, and the diagnostic plots;
  `from-segments-to-density` gains a "look at the distances first" section and
  the two traps in comparing several detection functions by AIC.
* `from-segments-to-density` — new. Picks up where the first ends: fitting a
  detection function with `Distance`, mapping the output onto the
  `segment.data`/`observation.data` shape `dsm` expects, projecting midpoints
  before smoothing, and sampling covariates. Covers the units trap explicitly,
  since effort is in km while distances default to metres.

## Keeping citations current

* `tools/citations.csv` — a registry of every source the package cites.
* `tools/check-citations.R` — verifies registry coverage, CrossRef metadata,
  URL liveness, and whether a newer handbook version has been published.
* `.github/workflows/check-citations.yaml` — runs it monthly and on pull
  requests that touch citations; opens an issue on a scheduled failure.
* `.github/workflows/R-CMD-check.yaml` — `R CMD check` on Linux, macOS, and
  Windows, on R release and oldrel.

First release. The segmentation core of the research scripts in `original/`,
rebuilt as an installable package with tests and documentation.

## Features

* `read_narwc()` and `validate_narwc()` — ingest and check data against the NARWC
  handbook (Kenney 2023, Version 7). Validation reports findings and never stops.
* `narwc_codes()` and `narwc_schema()` — the handbook code books as data.
* `flag_effort()`, `visibility_ok()`, `make_leg_id()`, `flag_circling()` —
  on-effort determination with every threshold as an argument.
* `gc_distance()`, `point_to_point_effort()`, `dist_methods()` — vectorised
  great-circle distance with three selectable methods.
* `split_tracks()`, `track_effort()` — continuous-effort tracks.
* `plan_segments()`, `cut_segments()` — segmentation following Becker.
* `segment_midpoints()`, `gc_interpolate()` — along-track segment midpoints.
* `segment_sightings()`, `attach_circling_sightings()` — per-segment counts and
  conditions.
* `segment_survey()` — the whole pipeline; `segments_wide()`,
  `segments_as_sf()`, `crop_to_bbox()`, `write_segments()` for output.

## Behaviour changes from `original/`

Each is documented in full, with file and line references, in
`docs/03-bug-fixes.md`.

* **Legacy visibility codes no longer discard effort.** `VISIBLTY >= 2` marked
  every pre-2004 record as off effort, including `-1`, which means *clear for at
  least 2 nautical miles*. Multi-year analyses were silently running on
  post-2004 data only.
* **The last trackline is no longer dropped.** The chopping loop ran to
  `nrow - 1`, so the final track of a dataset produced no segments.
* **Segmentation is reproducible.** Both random draws now take a seed. The
  caller's RNG stream is left untouched.
* **The leftover can land on the final segment.** `floor(runif(1, 1, n))` could
  never return `n`, so the odd segment was never at the end of a track.
* **Cutting error no longer accumulates.** Cut points are measured from the start
  of the track, so per-segment rounding cancels instead of piling onto the final
  segment and pushing it outside the tolerance band.
* **Pilot sightings are excluded by default.** `LEGSTAGE == 6` was previously
  kept, inflating counts with detections that did not arise from standard search
  effort.
* **Circling sightings are no longer hard-coded to right whales.** They are
  attached following the CETAP same-species rule, with `"all"` and `"none"`
  available.
* **A break in effort produces one track, not one per record.**
* **`Area`, `Region.Label`, and the species filter are arguments,** not literals
  in the middle of a function.
* **Nothing writes to disk** except `write_segments()`.
* **Exact sighting positions are projected onto the trackline.**
  `compute_distance.R` measured the great-circle distance from the event
  position straight to the animal. That is a radial distance; it exceeds the
  perpendicular distance a detection function is defined on by however far the
  aircraft was from being abeam, always in the same direction, and so biases
  density low.

## Written from scratch

`calculate_midpoint()` and `crop_data()` were called by `chop_segments()` but
defined nowhere, so the original pipeline could not run end-to-end. They are now
`segment_midpoints()` and `crop_to_bbox()`.

## Notes

* `gc_distance()` offers `"becker"` and `"kenney"`, which are the same formula
  and return identical values. The original `dist.rdk()` passed degrees into
  `sin()`/`cos()` without converting to radians and did not compute the Kenney
  and Winn distance at all; `"kenney"` here does.
* The default method is `"haversine"` — the same sphere, but numerically stable
  at the short ranges between consecutive survey records.
