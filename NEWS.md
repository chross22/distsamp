# distsamp 0.1.0

First release. The segmentation core of the research scripts in `original/`,
rebuilt as an installable package with tests and documentation.

## Features

* `read_narwc()` and `validate_narwc()` — ingest and check data against the NARWC
  handbook (Kenney 2021, Version 7). Validation reports findings and never stops.
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
