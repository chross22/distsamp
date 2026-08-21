# Checks that only matter for distance sampling

The checks in this package, for use alongside the handbook-general set
that
[`narwcr::narwc_checks()`](https://rdrr.io/pkg/narwcr/man/narwc_checks.html)
provides.

## Usage

``` r
distsamp_checks()
```

## Value

A named list of functions, in the shape
[`narwcr::narwc_checks()`](https://rdrr.io/pkg/narwcr/man/narwc_checks.html)
uses.

## Why these are separate

Everything here is a problem *only if you are computing a right-angle
distance*. A declination angle above the horizon and an exact sighting
position 200 km from the aircraft that logged it are both perfectly
ordinary columns to carry around; they become defects at the point where
a detection function is fitted to them. So they live with the package
that fits one, rather than in the reader that every analysis shares.

- `exact_position_far_from_event`:

  An exact sighting position more than 20 km from the event position
  that recorded it. A sighting is made from the aircraft, so this is a
  coordinate problem — usually a dropped minus sign, or degrees and
  decimal minutes read as decimal degrees — rather than a distant
  animal.

- `angle_out_of_range`:

  `ANGLEL` or `ANGLER` outside `(0, 90]`. Handbook 8.A.2 defines these
  as declination angles below the horizon, so a value at or below zero
  is at or above the horizon and one above 90 is behind the aircraft.
  Neither yields a perpendicular distance.

- `angle_both_sides`:

  Both `ANGLEL` and `ANGLER` recorded on one record. A sighting is on
  one side of the track, so the side is ambiguous and no distance can be
  computed.

- `angle_without_altitude`:

  A declination angle with no `ALT`. Handbook 8.A.2: the distance
  calculation must factor in altitude, so an angle without one is
  unusable.

## References

Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database:
A Guide for Users and Contributors, Version 8*, section 8.A.2. NARWC
Reference Document 2023-01.

## See also

[`narwcr::validate_narwc()`](https://rdrr.io/pkg/narwcr/man/validate_narwc.html),
[`narwcr::narwc_checks()`](https://rdrr.io/pkg/narwcr/man/narwc_checks.html)

## Examples

``` r
path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
dat <- read_narwc(path, quiet = TRUE)

# The handbook rules and the distance-sampling ones together
issues <- validate_narwc(dat, checks = c(narwc_checks(), distsamp_checks()))
issues[, c("check", "severity", "n")]
#> # A tibble: 1 × 3
#>   check                    severity     n
#>   <chr>                    <chr>    <int>
#> 1 legstage_line_not_closed note         1
```
