# Cut tracks into segments

Walks each continuous track record by record, accumulating
point-to-point effort until the target length for the current segment is
reached, then starts the next segment. This is the cutting half of the
segmentation;
[`plan_segments()`](https://camilleross.org/distsamp/reference/plan_segments.md)
supplies the targets.

## Usage

``` r
cut_segments(plan, dat, min_segment_km = 1, seed = NULL)
```

## Arguments

- plan:

  A tibble from
  [`plan_segments()`](https://camilleross.org/distsamp/reference/plan_segments.md).

- dat:

  The point-level survey data, with `DATE`, `new_trackno`,
  `pt2pt.effort`, and `EVENTNO`.

- min_segment_km:

  Segments shorter than this are dropped from the result. Default `1`.

- seed:

  Integer RNG seed for the coin flips, or `NULL`.

## Value

The point-level data, restricted to records that fell inside a kept
segment, with columns added:

- `seg_no`:

  Position of the segment within its track.

- `seg_id`:

  Unique segment identifier, `DATE_track_segno`.

- `seg_eff`:

  Realised segment length in km, repeated on each record.

- `events`:

  `EVENTNO` range spanned, as `"first_last"`.

- `case`:

  Which rule ended the segment; see Details.

## Details

The `case` column records why each segment ended, preserving the
diagnostic labels from the original implementation:

- `case2`:

  The first remaining record alone met the target.

- `case3`:

  Several records were needed; the coin flip decided whether to include
  the record that crossed the target.

- `case4`:

  Not enough effort remained to reach the target, so the segment took
  what was left.

- `case5`:

  Last segment of the track; it absorbed all remaining records.

## Where the cut falls

Segments are cut at record boundaries — a survey record is never split —
so a segment rarely lands exactly on its target. For each segment the
function finds the first record at which cumulative effort reaches the
target, then flips a coin: heads, that record is included and the
segment runs slightly long; tails, it is excluded and the segment runs
slightly short. Over many segments the two errors cancel instead of
biasing every segment long.

The final segment of each track takes all remaining records, so no
effort is lost off the end of a track.

## References

Becker, E.A., Forney, K.A., Ferguson, M.C., Foley, D.G., Smith, R.C.,
Barlow, J. and Redfern, J.V. (2010) Comparing California Current
cetacean-habitat models developed using in situ and remotely sensed sea
surface temperature data. *Marine Ecology Progress Series* 413:163-183.
[doi:10.3354/meps08696](https://doi.org/10.3354/meps08696)

## See also

[`plan_segments()`](https://camilleross.org/distsamp/reference/plan_segments.md),
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
plan <- plan_segments(track_effort(dat), seg_length = 5, seed = 1)

chopped <- cut_segments(plan, dat, seed = 1)

# One row per survey record, now carrying the segment it fell in
head(chopped[, c("seg_id", "seg_no", "seg_eff", "EVENTNO")])
#> # A tibble: 6 × 4
#>   seg_id         seg_no seg_eff EVENTNO
#>   <chr>           <int>   <dbl>   <dbl>
#> 1 2024-04-01_2_1      1    7.78       4
#> 2 2024-04-01_2_1      1    7.78       5
#> 3 2024-04-01_2_1      1    7.78       6
#> 4 2024-04-01_2_1      1    7.78       7
#> 5 2024-04-01_2_1      1    7.78       8
#> 6 2024-04-01_2_1      1    7.78       9

# Realised effort per segment, against the 5 km target
tapply(chopped$pt2pt.effort, chopped$seg_id, sum)
#> 2024-04-01_2_1 2024-04-01_2_2 2024-04-01_2_3 2024-04-01_2_4 2024-04-01_4_1 
#>         7.7784         5.5560         3.3336         5.5560         4.4448 
#> 2024-04-01_4_2 2024-04-01_6_1 2024-04-01_6_2 2024-04-02_1_1 2024-04-02_1_2 
#>         3.3336         4.4448         4.4448         3.3336         4.4448 
#> 2024-04-02_1_3 2024-04-02_1_4 2024-04-02_1_5 2024-04-02_1_6 2024-04-02_1_7 
#>         5.5560         4.4448         6.6672         4.4448         4.4448 
#> 2024-04-02_2_1 2024-04-02_4_1 2024-04-02_4_2 2024-04-02_5_1 2024-04-02_5_2 
#>         3.3336         5.5560         2.2224         3.3336         5.5560 
```
