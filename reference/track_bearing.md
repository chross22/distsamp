# Local bearing of the track-line at each record

Estimates the direction the aircraft was flying at each record, from the
positions logged either side of it on the same survey line.

## Usage

``` r
track_bearing(dat, by = NULL, track_rows = NULL)
```

## Arguments

- dat:

  A data frame with `LATITUDE` and `LONGITUDE`, in survey order.

- by:

  Character vector of columns identifying one continuous occupation of a
  survey line. `NULL` (default) picks `c("FILEID", "LEGNO3")` if
  [`make_leg_id()`](https://rdrr.io/pkg/narwcr/man/make_leg_id.html) has
  been run, then `c("FILEID", "LEGNO")`, then `"FILEID"`, and prepends
  `DATE` to whichever it picks when that column is present. Getting this
  wrong joins the end of one line to the start of the next and produces
  a bearing that belongs to neither — which is why `DATE` is included:
  two days sharing a `LEGNO` are separated by `FILEID` alone, and some
  extracts carry a constant `FILEID`.

- track_rows:

  Logical vector marking the records that define the track. `NULL`
  (default) uses the census records, `LEGTYPE == 2`, when `LEGTYPE` is
  present. Circling and transit positions must be excluded: an aircraft
  orbiting a whale has a bearing, but it is not the track-line's.

## Value

A numeric vector of bearings in degrees, one per row of `dat`, `NA` for
records that do not define a track.

## How the bearing is taken

Consecutive records often share a position — a sighting is logged at the
same latitude and longitude as the routine position it follows (handbook
4.2) — and a bearing between two identical points is undefined. Records
are therefore collapsed into runs of distinct positions first, and the
bearing for a run is taken from the previous distinct position to the
next one. That centred difference is less sensitive to a single jittery
fix than a forward difference. At the first and last position of a line,
where there is only one neighbour, the one-sided difference is used.

A line with only one distinct position has no direction, and gets `NA`.

## See also

[`gc_bearing()`](https://camilleross.org/distsamp/reference/gc_bearing.md),
[`exact_distance()`](https://camilleross.org/distsamp/reference/exact_distance.md)

## Examples

``` r
path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
dat <- make_leg_id(read_narwc(path))
#> `read_narwc()` renamed 2 columns:
#>   LAT_DD  -> LATITUDE
#>   LONG_DD -> LONGITUDE
#> All matched an exact entry in the alias table; `narwc_column_mapping()` returns this, and `quiet = TRUE` silences it.
# The fixture's lines all run due north
unique(round(track_bearing(dat)))
#> [1] NA  0
```
