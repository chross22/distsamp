# Locate the along-track midpoint of each segment

Finds the position half of a segment's realised effort along the
segment, interpolating along the great circle between the two survey
records that bracket the half-way distance.

## Usage

``` r
segment_midpoints(chopped)
```

## Arguments

- chopped:

  Point-level segmented data from
  [`cut_segments()`](https://camilleross.org/distsamp/reference/cut_segments.md),
  in survey order, with `DATE`, `new_trackno`, `seg_id`, `seg_eff`,
  `LATITUDE`, `LONGITUDE`, and `pt2pt.effort`.

## Value

A tibble with one row per segment: `seg_id`, `mid_lat`, `mid_lon`.

## Why along-track, not centroid

A segment is a piece of trackline, and the location that represents it
for a covariate lookup should be a point on that line. Averaging the
coordinates of the records in the segment gives a centroid that is
pulled towards wherever records happen to be dense, and on a curved or
dog-legged track can fall off the line entirely. Walking half the
segment's effort puts the midpoint on the track by construction, and
weights it by distance rather than by record count.

The segment mid-point is the location at which habitat covariates are
conventionally sampled in this family of models. Becker et al. (2019)
describe covariates "derived based on the segment's geographical
mid-point", with sea surface temperature and depth standard deviations
taken over a 3 x 3-pixel box around it. That is the intended use of
these coordinates.

## References

Becker, E.A., Forney, K.A., Redfern, J.V., Barlow, J., Jacox, M.G.,
Roberts, J.J. and Palacios, D.M. (2019) Predicting cetacean abundance
and distribution in a changing climate. *Diversity and Distributions*
25:626-643. [doi:10.1111/ddi.12867](https://doi.org/10.1111/ddi.12867)

Becker, E.A., Forney, K.A., Ferguson, M.C., Foley, D.G., Smith, R.C.,
Barlow, J. and Redfern, J.V. (2010) Comparing California Current
cetacean-habitat models developed using in situ and remotely sensed sea
surface temperature data. *Marine Ecology Progress Series* 413:163-183.
[doi:10.3354/meps08696](https://doi.org/10.3354/meps08696)

## See also

[`cut_segments()`](https://camilleross.org/distsamp/reference/cut_segments.md),
[`gc_interpolate()`](https://camilleross.org/distsamp/reference/gc_interpolate.md)

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

# The position half of each segment's realised effort along it - not the
# mean of its coordinates, which would sit off the track on a turn.
mids <- segment_midpoints(chopped)
head(mids)
#> # A tibble: 6 × 3
#>   seg_id         mid_lat mid_lon
#>   <chr>            <dbl>   <dbl>
#> 1 2024-04-01_2_1    43.0   -69  
#> 2 2024-04-01_2_2    43.1   -69  
#> 3 2024-04-01_2_3    43.1   -69  
#> 4 2024-04-01_2_4    43.2   -69  
#> 5 2024-04-01_4_1    43.3   -69.1
#> 6 2024-04-01_4_2    43.3   -69.1

# Every segment gets exactly one midpoint
nrow(mids) == length(unique(chopped$seg_id))
#> [1] TRUE
```
