# Perpendicular distance from a track to an exact sighting position

Given a point on the track-line, the bearing the track runs on there,
and the position of a sighting, returns the perpendicular (cross-track)
distance from the track to the sighting, and how far along the track the
foot of that perpendicular lies.

## Usage

``` r
cross_track_distance(
  lat,
  lon,
  bearing,
  target_lat,
  target_lon,
  units = c("m", "km", "nmi")
)
```

## Arguments

- lat, lon:

  Position on the track-line, in decimal degrees — normally the event
  position of the sighting record.

- bearing:

  Bearing of the track at that position, degrees clockwise from true
  north. See
  [`track_bearing()`](https://camilleross.org/distsamp/reference/track_bearing.md).

- target_lat, target_lon:

  Position of the sighting, in decimal degrees.

- units:

  `"m"` (default), `"km"`, or `"nmi"`.

## Value

A tibble with one row per input:

- `distance`:

  Unsigned perpendicular distance from the track.

- `along`:

  Signed along-track distance from `(lat, lon)` to the point where the
  sighting is abeam; positive ahead, negative behind.

- `side`:

  `"left"`, `"right"`, `"on-track"`, or `NA`.

## The geometry

The track through `(lat, lon)` on `bearing` defines a great circle. For
a sighting at angular distance \\\delta\_{13}\\ and initial bearing
\\\theta\_{13}\\ from that point, and a track bearing \\\theta\_{12}\\,
the cross-track angular distance is

\$\$\delta\_{xt} = \arcsin(\sin \delta\_{13} \sin(\theta\_{13} -
\theta\_{12}))\$\$

and the along-track distance is \\\arccos(\cos \delta\_{13} / \cos
\delta\_{xt})\\, signed by \\\cos(\theta\_{13} - \theta\_{12})\\.
Multiplying by the Earth's radius gives distances. The sign of
\\\delta\_{xt}\\ gives the side.

## Why not just the distance between the two positions

A sighting is not always logged at the moment it is abeam. If it is
recorded 300 m before the aircraft draws level, the straight distance
from the event position to the animal is \\\sqrt{x^2 + 300^2}\\ where
\\x\\ is the perpendicular distance the detection function needs — for a
whale 130 m off the track, that is 327 m rather than 130 m, an error of
a factor of two and always in the same direction. Distance sampling
assumes perpendicular distances, and inflating them biases the detection
function towards a wider effective strip and so density downwards.

`along` is returned so that this can be checked rather than assumed: it
is the along-track offset between the logged position and the point
where the sighting was abeam. Values near zero mean the two measures
would have agreed.

## References

Veness, C. (2019) *Calculating distance, bearing and more between
latitude/longitude points.* Movable Type Scripts. The cross-track and
along-track formulae are given there in the form used here.

Buckland, S.T., Anderson, D.R., Burnham, K.P., Laake, J.L., Borchers,
D.L. and Thomas, L. (2001) *Introduction to Distance Sampling.* Oxford
University Press. Perpendicular distance is the quantity line-transect
estimators are defined on.

## See also

[`exact_distance()`](https://camilleross.org/distsamp/reference/exact_distance.md)
to apply this across a survey data frame,
[`gc_bearing()`](https://camilleross.org/distsamp/reference/gc_bearing.md),
[`perp_distance()`](https://camilleross.org/distsamp/reference/perp_distance.md)

## Examples

``` r
# A track running due north; a sighting a little to the east is on the right
cross_track_distance(43, -69, bearing = 0, target_lat = 43, target_lon = -68.99)
#> # A tibble: 1 × 3
#>   distance along side 
#>      <dbl> <dbl> <chr>
#> 1     813.     0 right

# The same animal logged before it was abeam: the perpendicular distance is
# unchanged, and `along` records how far ahead it was
cross_track_distance(43, -69, bearing = 0, target_lat = 43.01, target_lon = -68.99)
#> # A tibble: 1 × 3
#>   distance along side 
#>      <dbl> <dbl> <chr>
#> 1     813. 1111. right
```
