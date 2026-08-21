# Summarise effort by continuous track

Totals the point-to-point effort on each continuous track and drops
tracks too short to be worth segmenting.

## Usage

``` r
track_effort(dat, min_track_km = 1)
```

## Arguments

- dat:

  A data frame with `DATE`, `new_trackno`, `pt2pt.effort`, and `TIME`.

- min_track_km:

  Tracks with less than this much effort are dropped. Default `1`.

## Value

A tibble with one row per track: `DATE`, `new_trackno`, `track_effort`
(km), and `start_time` (the earliest `TIME` on the track, used to keep
tracks in survey order).

## References

Becker, E.A., Forney, K.A., Ferguson, M.C., Foley, D.G., Smith, R.C.,
Barlow, J. and Redfern, J.V. (2010) Comparing California Current
cetacean-habitat models developed using in situ and remotely sensed sea
surface temperature data. *Marine Ecology Progress Series* 413:163-183.
[doi:10.3354/meps08696](https://doi.org/10.3354/meps08696)

## Examples

``` r
path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
dat <- point_to_point_effort(
  split_tracks(flag_effort(make_leg_id(read_narwc(path))))
)
#> `read_narwc()` renamed 2 columns:
#>   LAT_DD  -> LATITUDE
#>   LONG_DD -> LONGITUDE
#> All matched an exact entry in the alias table; `narwc_column_mapping()` returns this, and `quiet = TRUE` silences it.
track_effort(dat)
#> # A tibble: 7 × 4
#>   DATE       new_trackno track_effort start_time
#>   <date>     <chr>              <dbl>      <dbl>
#> 1 2024-04-01 2                  22.2      120400
#> 2 2024-04-01 4                   7.78     123000
#> 3 2024-04-01 6                   8.89     123920
#> 4 2024-04-02 1                  33.3      133000
#> 5 2024-04-02 2                   3.33     134320
#> 6 2024-04-02 4                   7.78     134640
#> 7 2024-04-02 5                   8.89     135050
```
