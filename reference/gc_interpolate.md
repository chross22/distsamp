# Interpolate a position along a great circle

Spherical linear interpolation between two positions: the point a given
fraction of the way along the great-circle arc joining them.

## Usage

``` r
gc_interpolate(lat1, lon1, lat2, lon2, fraction)
```

## Arguments

- lat1, lon1:

  Start positions, in decimal degrees.

- lat2, lon2:

  End positions, in decimal degrees.

- fraction:

  Fraction of the way from the start to the end, in \[0, 1\].

## Value

A tibble with columns `lat` and `lon`, in decimal degrees.

## References

Shoemake, K. (1985) Animating rotation with quaternion curves. *ACM
SIGGRAPH Computer Graphics* 19(3):245-254, for spherical linear
interpolation.
[doi:10.1145/325165.325242](https://doi.org/10.1145/325165.325242)

## Examples

``` r
# Halfway along a degree of latitude
gc_interpolate(43, -69, 44, -69, 0.5)
#> # A tibble: 1 × 2
#>     lat   lon
#>   <dbl> <dbl>
#> 1  43.5   -69
```
