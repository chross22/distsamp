# Segment a line-transect survey

Runs the whole segmentation pipeline: identify line occupations, flag
effort, accumulate along-track distance, split lines where effort
breaks, plan how many segments each continuous track carries, cut them,
and summarise sightings and conditions onto each segment.

## Usage

``` r
segment_survey(
  dat,
  seg_length,
  species = NULL,
  seed = NULL,
  seg_tol_frac = 0.5,
  min_track_km = 1,
  min_segment_km = 1,
  dist_method = c("haversine", "becker", "kenney", "eab", "rdk"),
  circling = c("same_species", "all", "none"),
  circling_distance = c("with_group", "break_off"),
  distance_units = c("m", "km"),
  distance_sources = c("angle", "exact", "strip"),
  effort_args = list(),
  sighting_args = list()
)
```

## Arguments

- dat:

  NARWC survey data, ideally from
  [`read_narwc()`](https://rdrr.io/pkg/narwcr/man/read_narwc.html).

- seg_length:

  Target segment length in km.

- species:

  Character vector of `SPECCODE` values to count, or `NULL` for all.

- seed:

  Integer RNG seed, or `NULL` for unseeded (not reproducible).

- seg_tol_frac:

  Passed to
  [`plan_segments()`](https://camilleross.org/distsamp/reference/plan_segments.md).

- min_track_km:

  Passed to
  [`track_effort()`](https://camilleross.org/distsamp/reference/track_effort.md).

- min_segment_km:

  Passed to
  [`cut_segments()`](https://camilleross.org/distsamp/reference/cut_segments.md).

- dist_method:

  Great-circle distance method: `"haversine"` (default), `"becker"`, or
  `"kenney"`. See
  [`gc_distance()`](https://camilleross.org/distsamp/reference/gc_distance.md)
  and
  [`dist_methods()`](https://camilleross.org/distsamp/reference/dist_methods.md).
  Becker and Kenney are the same formula and give identical results.

- circling:

  How to handle sightings recorded while circling off the census track:
  `"same_species"` (default), `"all"`, or `"none"`. See
  [`attach_circling_sightings()`](https://camilleross.org/distsamp/reference/attach_circling_sightings.md).

- circling_distance:

  What an attached circling record carries: `"inherit"` (default), the
  perpendicular distance of the on-effort group it was counted with;
  `"break_off"`, the measured great-circle distance from where the
  aircraft left the line; or `"with_group"`, which gives it no distance
  and no detection of its own, adding the animals to the group they were
  counted with instead. See
  [`attach_circling_sightings()`](https://camilleross.org/distsamp/reference/attach_circling_sightings.md).
  `settings$circling_distance` records which was used.

- distance_units:

  Units for perpendicular sighting distances computed from
  `ANGLEL`/`ANGLER`: `"m"` (default) or `"km"`. Note that `seg_eff` is
  always in km — see
  [`perp_distance()`](https://camilleross.org/distsamp/reference/perp_distance.md).

- distance_sources:

  Precedence order over the right-angle distance sources, passed to
  [`sighting_distances()`](https://camilleross.org/distsamp/reference/sighting_distances.md).
  Defaults to `c("angle", "exact", "strip")`; `"circling"` is available
  but not on by default. Each detection records which source supplied
  it, in `distance_source`.

- effort_args:

  Named list of arguments for
  [`flag_effort()`](https://rdrr.io/pkg/narwcr/man/flag_effort.html),
  used only when `dat` has no `OnOff.Effort` column.

- sighting_args:

  Named list of arguments for
  [`segment_sightings()`](https://camilleross.org/distsamp/reference/segment_sightings.md).

## Value

An object of class `distsamp_segments`: a list with

- `segments`:

  One row per segment — `seg_id`, `DATE`, `FILEID`, `LEGNO`, `LEGNO3`,
  `new_trackno`, `seg_no`, `seg_eff` (km), `mid_lat`, `mid_lon`,
  `mean_beaufort`, `wt_beaufort`, `n_records`, `events`, `case`,
  `start_time`.

- `sightings`:

  One row per segment per species.

- `detections`:

  One row per qualifying sighting, with perpendicular `distance` and
  `side` when `ANGLEL`/`ANGLER` were recorded. The input for a detection
  function.

- `tracks`:

  One row per continuous track.

- `points`:

  The point-level data with segment assignments, for diagnostics and
  mapping.

- `call`, `settings`:

  The call and the parameters used.

## Details

This is the function most users want. The individual steps are exported
too, so you can run them yourself when you need to intervene between
stages.

## Pipeline

1.  [`make_leg_id()`](https://rdrr.io/pkg/narwcr/man/make_leg_id.html) —
    separate re-occupations of the same survey line.

2.  [`flag_effort()`](https://rdrr.io/pkg/narwcr/man/flag_effort.html) —
    decide which records are on effort.

3.  [`point_to_point_effort()`](https://camilleross.org/distsamp/reference/point_to_point_effort.md)
    — great-circle distance between consecutive on-effort positions.

4.  [`split_tracks()`](https://camilleross.org/distsamp/reference/split_tracks.md)
    — start a new track wherever effort breaks.

5.  [`track_effort()`](https://camilleross.org/distsamp/reference/track_effort.md)
    — total effort per continuous track.

6.  [`plan_segments()`](https://camilleross.org/distsamp/reference/plan_segments.md)
    — how many segments, and how long each should be.

7.  [`cut_segments()`](https://camilleross.org/distsamp/reference/cut_segments.md)
    — walk the records and make the cuts.

8.  [`segment_midpoints()`](https://camilleross.org/distsamp/reference/segment_midpoints.md)
    — the along-track midpoint of each segment.

9.  [`segment_sightings()`](https://camilleross.org/distsamp/reference/segment_sightings.md)
    — counts and conditions per segment.

Steps 1 and 2 are skipped when the input already carries `LEGNO3` or
`OnOff.Effort` respectively, so you can substitute your own definitions.

## Reproducibility

Segmentation makes two random choices: which segment absorbs a track's
leftover distance, and whether a segment that cannot land exactly on its
target runs slightly long or slightly short. Pass a `seed` to make a run
repeatable. The calling session's RNG state is never disturbed.

## References

Becker, E.A., Forney, K.A., Ferguson, M.C., Foley, D.G., Smith, R.C.,
Barlow, J. and Redfern, J.V. (2010) Comparing California Current
cetacean-habitat models developed using in situ and remotely sensed sea
surface temperature data. *Marine Ecology Progress Series* 413:163-183.
[doi:10.3354/meps08696](https://doi.org/10.3354/meps08696)

Hedley, S.L. and Buckland, S.T. (2004) Spatial models for line transect
sampling. *Journal of Agricultural, Biological, and Environmental
Statistics* 9:181-199.
[doi:10.1198/1085711043578](https://doi.org/10.1198/1085711043578)

Miller, D.L., Burt, M.L., Rexstad, E.A. and Thomas, L. (2013) Spatial
models for distance sampling data: recent developments and future
directions. *Methods in Ecology and Evolution* 4:1001-1010.
[doi:10.1111/2041-210X.12105](https://doi.org/10.1111/2041-210X.12105)

Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database:
A Guide for Users and Contributors, Version 8*. NARWC Reference Document
2023-01. University of Rhode Island, Graduate School of Oceanography.

## See also

[`segments_wide()`](https://camilleross.org/distsamp/reference/segments_wide.md)
for a segment table with one count column per species, which is the
shape `dsm` expects.

## Examples

``` r
path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
segs <- segment_survey(read_narwc(path), seg_length = 5, seed = 1)
#> `read_narwc()` renamed 2 columns:
#>   LAT_DD  -> LATITUDE
#>   LONG_DD -> LONGITUDE
#> All matched an exact entry in the alias table; `narwc_column_mapping()` returns this, and `quiet = TRUE` silences it.
segs
#> <distsamp_segments>
#>   segments:  20
#>   tracks:    7
#>   total effort: 92.23 km
#>   segment length: median 4.44 km, range 2.22-7.78 km
#>   target length: 5 km   seed: 1
#>   species:   FIWH, RIWH, SEWH
#>   detections: 8 (8 with a perpendicular distance, m)
segs$segments[, c("seg_id", "seg_eff", "mid_lat", "mid_lon")]
#> # A tibble: 20 × 4
#>    seg_id         seg_eff mid_lat mid_lon
#>    <chr>            <dbl>   <dbl>   <dbl>
#>  1 2024-04-01_2_1    7.78    43.0   -69  
#>  2 2024-04-01_2_2    5.56    43.1   -69  
#>  3 2024-04-01_2_3    3.33    43.1   -69  
#>  4 2024-04-01_2_4    5.56    43.2   -69  
#>  5 2024-04-01_4_1    4.44    43.3   -69.1
#>  6 2024-04-01_4_2    3.33    43.3   -69.1
#>  7 2024-04-01_6_1    4.44    43.4   -69.1
#>  8 2024-04-01_6_2    4.44    43.4   -69.1
#>  9 2024-04-02_1_1    3.33    43.0   -68.8
#> 10 2024-04-02_1_2    4.44    43.0   -68.8
#> 11 2024-04-02_1_3    5.56    43.1   -68.8
#> 12 2024-04-02_1_4    4.44    43.1   -68.8
#> 13 2024-04-02_1_5    6.67    43.2   -68.8
#> 14 2024-04-02_1_6    4.44    43.2   -68.8
#> 15 2024-04-02_1_7    4.44    43.3   -68.8
#> 16 2024-04-02_2_1    3.33    43.4   -68.7
#> 17 2024-04-02_4_1    5.56    43.4   -68.6
#> 18 2024-04-02_4_2    2.22    43.4   -68.6
#> 19 2024-04-02_5_1    3.33    43.5   -68.7
#> 20 2024-04-02_5_2    5.56    43.5   -68.7
```
