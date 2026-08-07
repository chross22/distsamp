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
