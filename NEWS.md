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

None of these sources are wired into `sighting_distances()` or `segment_survey()`
yet; unifying them behind a `distance_source` column is the next step.

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

## Vignettes

* `segmenting-narwc-data` — the full walkthrough.
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
