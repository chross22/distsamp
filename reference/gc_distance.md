# Great-circle distance between positions

Vectorised great-circle distance in kilometres on a spherical Earth.

## Usage

``` r
gc_distance(
  lat1,
  lon1,
  lat2,
  lon2,
  method = c("haversine", "becker", "kenney", "eab", "rdk")
)
```

## Arguments

- lat1, lon1:

  Numeric vectors of latitudes and longitudes, in decimal degrees, of
  the first positions. West longitudes are negative (handbook 8.A.22).

- lat2, lon2:

  Numeric vectors of the second positions. Recycled against
  `lat1`/`lon1` following the usual R rules.

- method:

  One of `"haversine"` (default), `"becker"`, or `"kenney"`; see
  Methods. `"eab"` and `"rdk"` are accepted as aliases for the latter
  two.

## Value

A numeric vector of distances in kilometres. `NA` where any input
coordinate is `NA`, and exactly `0` where the two positions coincide.

## Methods

- `"becker"` (alias `"eab"`):

  The `fn.grcirclkm` routine from Elizabeth Becker's `segchopr` code.
  Spherical law of cosines: convert to radians, take the arc cosine,
  convert the resulting angle back to degrees, then scale by 60 nautical
  miles per degree and 1.852 km per nautical mile.

- `"kenney"` (alias `"rdk"`):

  Kenney and Winn (1986), p. 347, who give the formula as
  `D = 111.12 arccos[sin(X1) sin(X2) + cos(X1) cos(X2) cos(Y2 - Y1)]`
  for latitudes `X` and longitudes `Y`, with the arc cosine in degrees.

- `"haversine"`:

  The haversine formula, on the same sphere. Default.

## The Becker and Kenney methods are the same formula

Both are the spherical law of cosines, and both scale by the same
constant: 60 x 1.852 = 111.12. They therefore return identical values,
to the last bit. Both names are kept so that existing scripts and
configuration files keep reading sensibly, and so you can record in an
analysis which lineage you meant to follow — but choosing between them
will not change your results.

Two caveats about the historical implementations:

- The `dist.rdk` function in the original processing code passed decimal
  degrees straight into [`sin()`](https://rdrr.io/r/base/Trig.html) and
  [`cos()`](https://rdrr.io/r/base/Trig.html) with no conversion to
  radians, so it did not compute the Kenney and Winn distance at all.
  `"kenney"` here will not reproduce that function's output.

- The law of cosines loses precision at short range, because the arc
  cosine of a number very close to 1 is ill-conditioned. Consecutive
  positions in a computer-logged aerial survey are often only tens of
  metres apart, which is squarely in that regime. `"haversine"` is
  numerically stable there, agrees with the other two to well within
  survey accuracy at all ranges, and is the default for that reason.

## Great circles versus rhumb lines

A survey aircraft flies a rhumb line, not a great circle, so these
distances are formally the wrong ones. Kenney and Winn (1986, p. 347)
addressed this directly and dismissed it: "for two points around 10 km
apart, typical of track line segments in the data, great circle and
rhumb line distance differ by \<1 m, an error of \<0.01%." Consecutive
positions in modern computer-logged data are far closer together than 10
km, so the discrepancy is smaller still.

## References

Kenney, R.D. and Winn, H.E. (1986) Cetacean high-use habitats of the
northeast United States continental shelf. *Fishery Bulletin*
84(2):345-357. (The distance formula is on p. 347.)

Sinnott, R.W. (1984) Virtues of the haversine. *Sky and Telescope*
68(2):159.

## Examples

``` r
# Roughly one degree of latitude, in km
gc_distance(43, -69, 44, -69)
#> [1] 111.12

# Becker and Kenney are the same formula and agree exactly
gc_distance(43, -69, 44, -70, method = "becker") ==
  gc_distance(43, -69, 44, -70, method = "kenney")
#> [1] TRUE

# Haversine agrees to within millimetres at survey scales
gc_distance(43, -69, 43.01, -69, method = "haversine")
#> [1] 1.1112
gc_distance(43, -69, 43.01, -69, method = "becker")
#> [1] 1.1112
```
