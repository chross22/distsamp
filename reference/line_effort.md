# Effort per survey line

Summarises on-effort distance by survey line rather than by continuous
track.

## Usage

``` r
line_effort(x, combine = c("occupation", "line"))
```

## Arguments

- x:

  Point-level survey data with `pt2pt.effort`, `LEGNO`, and ideally
  `LEGNO3`, or a `distsamp_segments` object.

- combine:

  `"occupation"` (default) or `"line"`.

## Value

A tibble. Per occupation: `DATE`, `FILEID`, `LEGNO`, `LEGNO3`,
`occupation`, `effort_km`, `n_records`. Per line: `LEGNO`, `effort_km`,
`n_occupations`, `n_days`.

## Why this is not `segs$tracks`

A **track** is a continuous run of effort: it ends wherever effort
breaks, which may be mid-line, and it says nothing about which line was
being flown. A **line** is a design element — the transect the survey
set out to fly, named by `LEGNO`. Segmentation works on tracks, so
`segs$tracks` cannot answer "how much of line 7 did we actually cover,
and did we have to go back for it".

## Occupations and lines

A line can be started, abandoned for weather, and flown again hours
later. Each attempt is an **occupation**, identified by `LEGNO3` from
[`make_leg_id()`](https://rdrr.io/pkg/narwcr/man/make_leg_id.html); the
**line** is `LEGNO` itself.

`combine = "occupation"` (the default) gives one row per attempt.
`combine = "line"` gives one row per line with its attempts summed,
which is the total coverage that line received.

## What it sums

`pt2pt.effort`, which
[`point_to_point_effort()`](https://camilleross.org/distsamp/reference/point_to_point_effort.md)
attributes to the first record of each on-effort pair and sets to zero
across breaks. Summing it over an occupation therefore gives distance
actually flown on effort, not the distance between the line's endpoints.

## Give it point-level data, not a segmentation

Passing a `distsamp_segments` uses its `points` table, which holds only
the records that reached a segment.

Usually that costs nothing: the records segmentation leaves out are off
effort, and an off-effort record carries zero `pt2pt.effort` — so
dropping it removes no distance. But a track shorter than
`min_track_km`, or a segment shorter than `min_segment_km`, is discarded
*with* its on-effort distance, and that effort was really flown. A line
made up of such a track then reports less effort than the survey gave
it, or disappears from the summary entirely.

So pass the point-level data after
[`flag_effort()`](https://rdrr.io/pkg/narwcr/man/flag_effort.html) and
[`point_to_point_effort()`](https://camilleross.org/distsamp/reference/point_to_point_effort.md)
when the total has to be right. A message says which you gave it.

## References

Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database:
A Guide for Users and Contributors, Version 8*, section 8.A.19
(`LEGNO`). NARWC Reference Document 2023-01.

## See also

[`reflight_summary()`](https://camilleross.org/distsamp/reference/reflight_summary.md),
[`track_effort()`](https://camilleross.org/distsamp/reference/track_effort.md),
[`make_leg_id()`](https://rdrr.io/pkg/narwcr/man/make_leg_id.html)

## Examples

``` r
path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
dat <- point_to_point_effort(flag_effort(make_leg_id(read_narwc(path))))
#> `read_narwc()` renamed 2 columns:
#>   LAT_DD  -> LATITUDE
#>   LONG_DD -> LONGITUDE
#> All matched an exact entry in the alias table; `narwc_column_mapping()` returns this, and `quiet = TRUE` silences it.

# One row per attempt at a line
line_effort(dat)
#> # A tibble: 6 × 7
#>   DATE       FILEID   LEGNO LEGNO3 effort_km n_records occupation
#>   <date>     <chr>    <dbl> <chr>      <dbl>     <int>      <int>
#> 1 2024-04-01 AA240401     1 1_2        22.2         26          1
#> 2 2024-04-01 AA240401     2 2_3        16.7         25          1
#> 3 2024-04-02 AA240402     3 3_4        33.3         34          1
#> 4 2024-04-02 AA240402     4 4_5         3.33         6          1
#> 5 2024-04-02 AA240402     4 4_7         8.89         9          2
#> 6 2024-04-02 AA240402     5 5_6         7.78         8          1

# One row per line, attempts combined
line_effort(dat, combine = "line")
#> # A tibble: 5 × 4
#>   LEGNO effort_km n_occupations n_days
#>   <dbl>     <dbl>         <int>  <int>
#> 1     1     22.2              1      1
#> 2     2     16.7              1      1
#> 3     3     33.3              1      1
#> 4     4     12.2              2      1
#> 5     5      7.78             1      1
```
