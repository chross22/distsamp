# Segment table with one column per species

Reshapes a
[`segment_survey()`](https://camilleross.org/distsamp/reference/segment_survey.md)
result into the layout density surface models expect: one row per
segment, with a count column for each species.

## Usage

``` r
segments_wide(x, value = c("animals", "sightings"), prefix = "n_")
```

## Arguments

- x:

  A `distsamp_segments` object.

- value:

  Which count to spread: `"animals"` (default, the sum of `NUMBER`) or
  `"sightings"` (the number of sighting records).

- prefix:

  Prefix for the generated count columns. Default `"n_"`.

## Value

A tibble: the `segments` table with one count column per species.
Segments with no sightings of a species get `0`, not `NA`.

## References

Miller, D.L., Burt, M.L., Rexstad, E.A. and Thomas, L. (2013) Spatial
models for distance sampling data: recent developments and future
directions. *Methods in Ecology and Evolution* 4:1001-1010.
[doi:10.1111/2041-210X.12105](https://doi.org/10.1111/2041-210X.12105)

## Examples

``` r
path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
segs <- segment_survey(read_narwc(path), seg_length = 5, seed = 1)
#> `read_narwc()` renamed 2 columns:
#>   LAT_DD  -> LATITUDE
#>   LONG_DD -> LONGITUDE
#> All matched an exact entry in the alias table; `narwc_column_mapping()` returns this, and `quiet = TRUE` silences it.
segments_wide(segs)
#> # A tibble: 20 × 20
#>    seg_id       DATE       FILEID LEGNO LEGNO2 LEGNO3 new_trackno seg_no seg_eff
#>    <chr>        <date>     <chr>  <dbl> <chr>  <chr>  <chr>        <int>   <dbl>
#>  1 2024-04-01_… 2024-04-01 AA240…     1 1      1_2    2                1    7.78
#>  2 2024-04-01_… 2024-04-01 AA240…     1 1      1_2    2                2    5.56
#>  3 2024-04-01_… 2024-04-01 AA240…     1 1      1_2    2                3    3.33
#>  4 2024-04-01_… 2024-04-01 AA240…     1 1      1_2    2                4    5.56
#>  5 2024-04-01_… 2024-04-01 AA240…     2 2      2_3    4                1    4.44
#>  6 2024-04-01_… 2024-04-01 AA240…     2 2      2_3    4                2    3.33
#>  7 2024-04-01_… 2024-04-01 AA240…     2 2      2_3    6                1    4.44
#>  8 2024-04-01_… 2024-04-01 AA240…     2 2      2_3    6                2    4.44
#>  9 2024-04-02_… 2024-04-02 AA240…     3 3      3_4    1                1    3.33
#> 10 2024-04-02_… 2024-04-02 AA240…     3 3      3_4    1                2    4.44
#> 11 2024-04-02_… 2024-04-02 AA240…     3 3      3_4    1                3    5.56
#> 12 2024-04-02_… 2024-04-02 AA240…     3 3      3_4    1                4    4.44
#> 13 2024-04-02_… 2024-04-02 AA240…     3 3      3_4    1                5    6.67
#> 14 2024-04-02_… 2024-04-02 AA240…     3 3      3_4    1                6    4.44
#> 15 2024-04-02_… 2024-04-02 AA240…     3 3      3_4    1                7    4.44
#> 16 2024-04-02_… 2024-04-02 AA240…     4 4      4_5    2                1    3.33
#> 17 2024-04-02_… 2024-04-02 AA240…     5 5      5_6    4                1    5.56
#> 18 2024-04-02_… 2024-04-02 AA240…     5 5      5_6    4                2    2.22
#> 19 2024-04-02_… 2024-04-02 AA240…     4 4      4_7    5                1    3.33
#> 20 2024-04-02_… 2024-04-02 AA240…     4 4      4_7    5                2    5.56
#> # ℹ 11 more variables: mid_lat <dbl>, mid_lon <dbl>, mean_beaufort <dbl>,
#> #   wt_beaufort <dbl>, n_records <int>, start_time <dbl>, events <chr>,
#> #   case <chr>, n_RIWH <dbl>, n_FIWH <dbl>, n_SEWH <dbl>
```
