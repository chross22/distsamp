# Convert segments to spatial features

Builds an `sf` object from a
[`segment_survey()`](https://camilleross.org/distsamp/reference/segment_survey.md)
result, either as the segment midpoints or as the trackline geometry of
each segment.

## Usage

``` r
segments_as_sf(x, what = c("midpoints", "lines"), crs = 4326)
```

## Arguments

- x:

  A `distsamp_segments` object.

- what:

  `"midpoints"` (default) for one point per segment, or `"lines"` for
  the trackline each segment covers.

- crs:

  Coordinate reference system for the result. Default `4326` (WGS 84),
  the datum NARWC coordinates are recorded in.

## Value

An `sf` object with one feature per segment, carrying the segment
attributes.

## References

Pebesma, E. (2018) Simple features for R: standardized support for
spatial vector data. *The R Journal* 10(1):439-446.
[doi:10.32614/RJ-2018-009](https://doi.org/10.32614/RJ-2018-009)

## Examples

``` r
if (requireNamespace("sf", quietly = TRUE)) {
  path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
  segs <- segment_survey(read_narwc(path), seg_length = 5, seed = 1)
  segments_as_sf(segs)
}
#> `read_narwc()` renamed 2 columns:
#>   LAT_DD  -> LATITUDE
#>   LONG_DD -> LONGITUDE
#> All matched an exact entry in the alias table; `narwc_column_mapping()` returns this, and `quiet = TRUE` silences it.
#> Simple feature collection with 20 features and 17 fields
#> Geometry type: POINT
#> Dimension:     XY
#> Bounding box:  xmin: -69.1 ymin: 43.015 xmax: -68.6 ymax: 43.505
#> Geodetic CRS:  WGS 84
#> # A tibble: 20 × 18
#>    seg_id       DATE       FILEID LEGNO LEGNO2 LEGNO3 new_trackno seg_no seg_eff
#>  * <chr>        <date>     <chr>  <dbl> <chr>  <chr>  <chr>        <int>   <dbl>
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
#> # ℹ 9 more variables: mid_lat <dbl>, mid_lon <dbl>, mean_beaufort <dbl>,
#> #   wt_beaufort <dbl>, n_records <int>, start_time <dbl>, events <chr>,
#> #   case <chr>, geometry <POINT [°]>
```
