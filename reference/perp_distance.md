# Perpendicular distance from a declination angle

Converts a declination angle and an aircraft altitude into the
perpendicular (right-angle) distance from the track-line to a sighting.

## Usage

``` r
perp_distance(angle, altitude, units = c("m", "km"))
```

## Arguments

- angle:

  Declination angle below the horizon, in degrees. Values outside
  `(0, 90]` cannot describe a sighting below the horizon and return
  `NA`.

- altitude:

  Aircraft altitude in metres, typically the `ALT` column. Non-positive
  or missing altitudes return `NA`.

- units:

  `"m"` (default) or `"km"`.

## Value

A numeric vector of perpendicular distances.

## The geometry

`ANGLEL` and `ANGLER` are, per handbook 8.A.2, "the declination angles,
in degrees, below the horizon of a sighting (to the left or right,
respectively) **when it is perpendicular to the track-line**". Because
the angle is taken at the moment the sighting is abeam, the aircraft,
the point on the sea surface directly below it, and the animal form a
right triangle in the vertical plane perpendicular to the track. The
perpendicular distance is therefore

\$\$x = h / \tan(\theta)\$\$

for altitude \\h\\ and declination \\\theta\\. An angle of 90 degrees is
straight down and gives a distance of zero; as the angle approaches the
horizon the distance grows without bound.

These replaced `STRIP` in 2022. Handbook 8.A.2 gives the reason: survey
altitudes had to rise once offshore wind turbines were in place, and the
fixed distance intervals `STRIP` encodes shift with altitude, whereas an
angle carries the altitude dependence explicitly.

## Units

`ALT` is in metres (8.A.1), so distances are returned in metres by
default. Note that segment effort in this package is in **kilometres** —
if you pass both to `Distance::ds()` you must either use `units = "km"`
here or supply `convert_units`. Getting this wrong scales density
estimates by 1000.

## References

Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database:
A Guide for Users and Contributors, Version 8*, section 8.A.2. NARWC
Reference Document 2023-01.

Buckland, S.T., Anderson, D.R., Burnham, K.P., Laake, J.L., Borchers,
D.L. and Thomas, L. (2001) *Introduction to Distance Sampling.* Oxford
University Press.

## See also

[`sighting_distances()`](https://camilleross.org/distsamp/reference/sighting_distances.md)
to apply this across a survey data frame.

## Examples

``` r
# Straight down
perp_distance(90, altitude = 229)
#> [1] 0

# 45 degrees below the horizon: distance equals altitude
perp_distance(45, altitude = 229)
#> [1] 229

# Shallow angles put the animal a long way off the track
perp_distance(c(60, 30, 10), altitude = 229)
#> [1]  132.2132  396.6396 1298.7235

perp_distance(30, altitude = 229, units = "km")
#> [1] 0.3966396
```
