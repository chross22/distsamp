# Summarise sightings and conditions by segment

Counts sightings and animals per segment per species, and summarises the
survey conditions over each segment.

## Usage

``` r
segment_sightings(
  chopped,
  species = NULL,
  legstage_exclude = c(6, 7),
  idrel_keep = c(2, 3)
)
```

## Arguments

- chopped:

  Point-level segmented data from
  [`cut_segments()`](https://camilleross.org/distsamp/reference/cut_segments.md).

- species:

  Character vector of `SPECCODE` values to count, or `NULL` (default)
  for every species present.

- legstage_exclude:

  `LEGSTAGE` values whose sightings are not counted. Default `c(6, 7)`.

- idrel_keep:

  `IDREL` values whose sightings are counted. Default `c(2, 3)`.

## Value

A list with three tibbles:

- `sightings`:

  One row per segment per species, with `n_sightings` (number of
  sighting records) and `n_animals` (sum of `NUMBER`).

- `conditions`:

  One row per segment, with `mean_beaufort`, `wt_beaufort`, and
  `n_records`.

- `detections`:

  One row per qualifying sighting, with `distance`, `side`, and `size`.

## Which sightings count

Only sightings usable in a density estimate are counted. By default that
excludes:

- `LEGSTAGE == 6` — a sighting by someone other than an on-duty
  observer, typically the pilot. Handbook 4.2 is explicit that such a
  sighting "cannot be included in a density estimate", because it did
  not arise from the standard search effort the detection function
  describes.

- `LEGSTAGE == 7` — a sighting detected afterwards in a vertical
  photograph (handbook 8.A.20), which likewise is not a visual detection
  by an observer.

- `IDREL` of `1` (possible) or `9` (unknown). Handbook 8.A.16 records
  Kenney's own practice of using only definite and probable
  identifications.

The original processing code excluded `LEGSTAGE == 7` but kept
`LEGSTAGE == 6`, which lets pilot sightings inflate counts.

## Beaufort summaries

Two are produced. `mean_beaufort` is the plain mean over the segment's
records; `wt_beaufort` weights each record by the distance it
contributes, so a sea state recorded over 3 km counts for more than one
recorded over 200 m. Prefer the weighted value as a detection covariate.

## Detections

The `detections` table has one row per qualifying sighting rather than
per segment, carrying the perpendicular distance from
[`sighting_distances()`](https://camilleross.org/distsamp/reference/sighting_distances.md)
when `ANGLEL`/`ANGLER` are available. That is the shape a detection
function wants: pass it to `Distance::ds()`, keyed back to the segments
by `seg_id`.

A sighting recorded while circling carries the perpendicular distance of
the on-effort group it was counted with, marked
`distance_source == "circling"`, and the measured `break_off_distance`
from the point on the line where the aircraft broke off. The first is
what lets it count towards the segment's abundance, which needs a
detection probability; the second is what lets you judge whether the
attachment was reasonable. Neither belongs in a detection function — the
inherited one is already in it, under the sighting it was inherited from
— and
[`detection_data()`](https://camilleross.org/distsamp/reference/detection_data.md)
excludes them by default.

## References

Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database:
A Guide for Users and Contributors, Version 8*, sections 4.2, 8.A.16,
8.A.20. NARWC Reference Document 2023-01.

Becker, E.A., Forney, K.A., Ferguson, M.C., Foley, D.G., Smith, R.C.,
Barlow, J. and Redfern, J.V. (2010) Comparing California Current
cetacean-habitat models developed using in situ and remotely sensed sea
surface temperature data. *Marine Ecology Progress Series* 413:163-183.
[doi:10.3354/meps08696](https://doi.org/10.3354/meps08696)

## See also

[`segment_survey()`](https://camilleross.org/distsamp/reference/segment_survey.md)

## Examples

``` r
path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
dat <- point_to_point_effort(flag_effort(make_leg_id(read_narwc(path))))
#> `read_narwc()` renamed 2 columns:
#>   LAT_DD  -> LATITUDE
#>   LONG_DD -> LONGITUDE
#> All matched an exact entry in the alias table; `narwc_column_mapping()` returns this, and `quiet = TRUE` silences it.
dat <- split_tracks(dat)
chopped <- cut_segments(
  plan_segments(track_effort(dat), seg_length = 5, seed = 1), dat, seed = 1
)

# Counts per segment and species, with pilot sightings (LEGSTAGE 6) and
# photographic detections (7) excluded, and only probable or definite
# identifications kept.
segment_sightings(chopped)
#> $sightings
#> # A tibble: 6 × 4
#>   seg_id         SPECCODE n_sightings n_animals
#>   <chr>          <chr>          <int>     <dbl>
#> 1 2024-04-01_2_1 RIWH               1         1
#> 2 2024-04-01_2_2 FIWH               1         3
#> 3 2024-04-01_2_2 RIWH               2         3
#> 4 2024-04-01_4_2 RIWH               2         4
#> 5 2024-04-02_1_3 RIWH               1         4
#> 6 2024-04-02_1_5 SEWH               1         2
#> 
#> $conditions
#> # A tibble: 20 × 4
#>    seg_id         mean_beaufort wt_beaufort n_records
#>    <chr>                  <dbl>       <dbl>     <int>
#>  1 2024-04-01_2_1             2           2         8
#>  2 2024-04-01_2_2             2           2         8
#>  3 2024-04-01_2_3             2           2         4
#>  4 2024-04-01_2_4             2           2         6
#>  5 2024-04-01_4_1             2           2         4
#>  6 2024-04-01_4_2             2           2         7
#>  7 2024-04-01_6_1             2           2         4
#>  8 2024-04-01_6_2             2           2         5
#>  9 2024-04-02_1_1             2           2         3
#> 10 2024-04-02_1_2             2           2         5
#> 11 2024-04-02_1_3             2           2         5
#> 12 2024-04-02_1_4             2           2         4
#> 13 2024-04-02_1_5             2           2         7
#> 14 2024-04-02_1_6             2           2         5
#> 15 2024-04-02_1_7             2           2         5
#> 16 2024-04-02_2_1             2           2         4
#> 17 2024-04-02_4_1             2           2         5
#> 18 2024-04-02_4_2             2           2         3
#> 19 2024-04-02_5_1             2           2         3
#> 20 2024-04-02_5_2             2           2         6
#> 
#> $detections
#> # A tibble: 8 × 13
#>   seg_id         DATE       SPECCODE  size distance distbegin distend side 
#>   <chr>          <date>     <chr>    <dbl>    <dbl>     <dbl>   <dbl> <chr>
#> 1 2024-04-01_2_1 2024-04-01 RIWH         1       NA        NA      NA NA   
#> 2 2024-04-01_2_2 2024-04-01 RIWH         2       NA        NA      NA NA   
#> 3 2024-04-01_2_2 2024-04-01 RIWH         1       NA        NA      NA NA   
#> 4 2024-04-01_2_2 2024-04-01 FIWH         3       NA        NA      NA NA   
#> 5 2024-04-01_4_2 2024-04-01 RIWH         3       NA        NA      NA NA   
#> 6 2024-04-01_4_2 2024-04-01 RIWH         1       NA        NA      NA NA   
#> 7 2024-04-02_1_3 2024-04-02 RIWH         4       NA        NA      NA NA   
#> 8 2024-04-02_1_5 2024-04-02 SEWH         2       NA        NA      NA NA   
#> # ℹ 5 more variables: distance_source <chr>, EVENTNO <dbl>, SIGHTNO <dbl>,
#> #   circling <int>, break_off_distance <dbl>
#> 

# One species only
segment_sightings(chopped, species = "RIWH")
#> $sightings
#> # A tibble: 4 × 4
#>   seg_id         SPECCODE n_sightings n_animals
#>   <chr>          <chr>          <int>     <dbl>
#> 1 2024-04-01_2_1 RIWH               1         1
#> 2 2024-04-01_2_2 RIWH               2         3
#> 3 2024-04-01_4_2 RIWH               2         4
#> 4 2024-04-02_1_3 RIWH               1         4
#> 
#> $conditions
#> # A tibble: 20 × 4
#>    seg_id         mean_beaufort wt_beaufort n_records
#>    <chr>                  <dbl>       <dbl>     <int>
#>  1 2024-04-01_2_1             2           2         8
#>  2 2024-04-01_2_2             2           2         8
#>  3 2024-04-01_2_3             2           2         4
#>  4 2024-04-01_2_4             2           2         6
#>  5 2024-04-01_4_1             2           2         4
#>  6 2024-04-01_4_2             2           2         7
#>  7 2024-04-01_6_1             2           2         4
#>  8 2024-04-01_6_2             2           2         5
#>  9 2024-04-02_1_1             2           2         3
#> 10 2024-04-02_1_2             2           2         5
#> 11 2024-04-02_1_3             2           2         5
#> 12 2024-04-02_1_4             2           2         4
#> 13 2024-04-02_1_5             2           2         7
#> 14 2024-04-02_1_6             2           2         5
#> 15 2024-04-02_1_7             2           2         5
#> 16 2024-04-02_2_1             2           2         4
#> 17 2024-04-02_4_1             2           2         5
#> 18 2024-04-02_4_2             2           2         3
#> 19 2024-04-02_5_1             2           2         3
#> 20 2024-04-02_5_2             2           2         6
#> 
#> $detections
#> # A tibble: 6 × 13
#>   seg_id         DATE       SPECCODE  size distance distbegin distend side 
#>   <chr>          <date>     <chr>    <dbl>    <dbl>     <dbl>   <dbl> <chr>
#> 1 2024-04-01_2_1 2024-04-01 RIWH         1       NA        NA      NA NA   
#> 2 2024-04-01_2_2 2024-04-01 RIWH         2       NA        NA      NA NA   
#> 3 2024-04-01_2_2 2024-04-01 RIWH         1       NA        NA      NA NA   
#> 4 2024-04-01_4_2 2024-04-01 RIWH         3       NA        NA      NA NA   
#> 5 2024-04-01_4_2 2024-04-01 RIWH         1       NA        NA      NA NA   
#> 6 2024-04-02_1_3 2024-04-02 RIWH         4       NA        NA      NA NA   
#> # ℹ 5 more variables: distance_source <chr>, EVENTNO <dbl>, SIGHTNO <dbl>,
#> #   circling <int>, break_off_distance <dbl>
#> 

# Keep possible identifications too (IDREL 1), which the default drops
segment_sightings(chopped, idrel_keep = c(1, 2, 3))
#> $sightings
#> # A tibble: 7 × 4
#>   seg_id         SPECCODE n_sightings n_animals
#>   <chr>          <chr>          <int>     <dbl>
#> 1 2024-04-01_2_1 RIWH               1         1
#> 2 2024-04-01_2_2 FIWH               1         3
#> 3 2024-04-01_2_2 RIWH               2         3
#> 4 2024-04-01_4_2 RIWH               2         4
#> 5 2024-04-02_1_3 RIWH               1         4
#> 6 2024-04-02_1_5 SEWH               1         2
#> 7 2024-04-02_5_2 RIWH               1         1
#> 
#> $conditions
#> # A tibble: 20 × 4
#>    seg_id         mean_beaufort wt_beaufort n_records
#>    <chr>                  <dbl>       <dbl>     <int>
#>  1 2024-04-01_2_1             2           2         8
#>  2 2024-04-01_2_2             2           2         8
#>  3 2024-04-01_2_3             2           2         4
#>  4 2024-04-01_2_4             2           2         6
#>  5 2024-04-01_4_1             2           2         4
#>  6 2024-04-01_4_2             2           2         7
#>  7 2024-04-01_6_1             2           2         4
#>  8 2024-04-01_6_2             2           2         5
#>  9 2024-04-02_1_1             2           2         3
#> 10 2024-04-02_1_2             2           2         5
#> 11 2024-04-02_1_3             2           2         5
#> 12 2024-04-02_1_4             2           2         4
#> 13 2024-04-02_1_5             2           2         7
#> 14 2024-04-02_1_6             2           2         5
#> 15 2024-04-02_1_7             2           2         5
#> 16 2024-04-02_2_1             2           2         4
#> 17 2024-04-02_4_1             2           2         5
#> 18 2024-04-02_4_2             2           2         3
#> 19 2024-04-02_5_1             2           2         3
#> 20 2024-04-02_5_2             2           2         6
#> 
#> $detections
#> # A tibble: 9 × 13
#>   seg_id         DATE       SPECCODE  size distance distbegin distend side 
#>   <chr>          <date>     <chr>    <dbl>    <dbl>     <dbl>   <dbl> <chr>
#> 1 2024-04-01_2_1 2024-04-01 RIWH         1       NA        NA      NA NA   
#> 2 2024-04-01_2_2 2024-04-01 RIWH         2       NA        NA      NA NA   
#> 3 2024-04-01_2_2 2024-04-01 RIWH         1       NA        NA      NA NA   
#> 4 2024-04-01_2_2 2024-04-01 FIWH         3       NA        NA      NA NA   
#> 5 2024-04-01_4_2 2024-04-01 RIWH         3       NA        NA      NA NA   
#> 6 2024-04-01_4_2 2024-04-01 RIWH         1       NA        NA      NA NA   
#> 7 2024-04-02_1_3 2024-04-02 RIWH         4       NA        NA      NA NA   
#> 8 2024-04-02_1_5 2024-04-02 SEWH         2       NA        NA      NA NA   
#> 9 2024-04-02_5_2 2024-04-02 RIWH         1       NA        NA      NA NA   
#> # ℹ 5 more variables: distance_source <chr>, EVENTNO <dbl>, SIGHTNO <dbl>,
#> #   circling <int>, break_off_distance <dbl>
#> 
```
