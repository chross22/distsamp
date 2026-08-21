# Initial great-circle bearing between positions

The bearing, in degrees clockwise from true north, along which a great
circle leaves the first position heading for the second.

## Usage

``` r
gc_bearing(lat1, lon1, lat2, lon2)
```

## Arguments

- lat1, lon1:

  Numeric vectors of latitudes and longitudes of the start positions, in
  decimal degrees. West longitudes are negative.

- lat2, lon2:

  Numeric vectors of the positions bearing is taken to. Recycled against
  `lat1`/`lon1`.

## Value

A numeric vector of bearings in `[0, 360)`. `NA` where any coordinate is
`NA`, and `NA` where the two positions coincide, which has no bearing.

## Initial, not constant

A great circle changes bearing as it is followed, so this is the bearing
*at the first position*. Over the distances between consecutive survey
positions the change is negligible — a tenth of a degree over 10 km at
these latitudes — but it is the reason
[`cross_track_distance()`](https://camilleross.org/distsamp/reference/cross_track_distance.md)
takes a bearing and a point together rather than a bearing alone.

## See also

[`gc_distance()`](https://camilleross.org/distsamp/reference/gc_distance.md),
[`cross_track_distance()`](https://camilleross.org/distsamp/reference/cross_track_distance.md),
[`track_bearing()`](https://camilleross.org/distsamp/reference/track_bearing.md)

## Examples

``` r
# Due north along a meridian
gc_bearing(43, -69, 44, -69)
#> [1] 0

# Due east, at the moment of departure
gc_bearing(43, -69, 43, -68)
#> [1] 89.659

# A position has no bearing to itself
gc_bearing(43, -69, 43, -69)
#> [1] NA
```
