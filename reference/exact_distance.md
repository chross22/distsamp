# Perpendicular distances from exact sighting positions

Computes the perpendicular distance from the track-line to each sighting
that carries an exact position in `S_LAT`/`S_LONG` (handbook 8.A.33,
8.A.34).

## Usage

``` r
exact_distance(
  dat,
  by = NULL,
  units = c("m", "km", "nmi"),
  on_effort_only = TRUE
)
```

## Arguments

- dat:

  A data frame of NARWC survey data with `LATITUDE`, `LONGITUDE`, and
  ideally `S_LAT`/`S_LONG`. Data without the sighting-position columns
  comes back with the columns present and all `NA`.

- by:

  Grouping columns identifying one occupation of a survey line, passed
  to
  [`track_bearing()`](https://camilleross.org/distsamp/reference/track_bearing.md).

- units:

  `"m"` (default), `"km"`, or `"nmi"`.

- on_effort_only:

  Restrict to on-effort census records. Default `TRUE`.

## Value

A tibble with one row per row of `dat`:

- `distance`:

  Perpendicular distance from the track-line.

- `along`:

  Signed along-track offset between the logged position and the point
  where the sighting was abeam.

- `side`:

  `"left"`, `"right"`, `"on-track"`, or `NA`.

- `bearing`:

  The track bearing used, for diagnosis.

## Where this fits

This is the most direct of the three right-angle distance sources this
package supports, because it measures the quantity a detection function
is defined on rather than inferring it. It needs the sighting position
to have been fixed independently — from a GPS mark, a photograph, or a
circling pass — so it is available only where the survey recorded one,
which in the NARWC archive is mostly the NLPSC-era and later data. Where
`S_LAT`/`S_LONG` and a declination angle both exist, comparing the two
is a useful check on both; they are independent measurements of the same
thing.

## How it differs from the original scripts

The processing scripts this package was rewritten from computed the
great-circle distance from the *event position* straight to the sighting
position. That is a radial distance, not a perpendicular one, and it
exceeds the perpendicular distance by however far the aircraft was from
being abeam when the sighting was logged. This function projects onto
the track instead, and returns the along-track offset in `along` so the
size of that difference is visible rather than silently folded into the
distance.

## Restricted to census records

Like
[`sighting_distances()`](https://camilleross.org/distsamp/reference/sighting_distances.md),
and for the same reason, distances are computed only for on-effort
records on a census line at `LEGSTAGE == 2` by default. Off the census
line there is no track-line to be perpendicular to: a position logged
while circling has a well-defined distance to the animal and no useful
perpendicular distance at all. Setting `on_effort_only = FALSE` computes
them anyway, which is occasionally useful for diagnostics and never
appropriate for fitting.

## References

Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database:
A Guide for Users and Contributors, Version 8*, sections 8.A.33 and
8.A.34. NARWC Reference Document 2023-01.

## See also

[`cross_track_distance()`](https://camilleross.org/distsamp/reference/cross_track_distance.md),
[`track_bearing()`](https://camilleross.org/distsamp/reference/track_bearing.md),
[`sighting_distances()`](https://camilleross.org/distsamp/reference/sighting_distances.md),
[`strip_distance()`](https://camilleross.org/distsamp/reference/strip_distance.md)

## Examples

``` r
path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
dat <- flag_effort(make_leg_id(read_narwc(path)))
#> `read_narwc()` renamed 2 columns:
#>   LAT_DD  -> LATITUDE
#>   LONG_DD -> LONGITUDE
#> All matched an exact entry in the alias table; `narwc_column_mapping()` returns this, and `quiet = TRUE` silences it.
d <- exact_distance(dat)
cbind(dat[!is.na(d$distance), c("SPECCODE", "S_LAT", "S_LONG")],
      d[!is.na(d$distance), c("distance", "along", "side")])
#>   SPECCODE   S_LAT    S_LONG distance along  side
#> 1     RIWH 43.0400 -68.99718 229.0000     0 right
#> 2     RIWH 43.0927 -69.00163 132.2132   300  left
#> 3     RIWH 43.0700 -68.80198 160.3475     0  left
```
