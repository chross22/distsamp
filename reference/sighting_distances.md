# Perpendicular distances for a survey data frame

Resolves a right-angle distance for each sighting from whichever of the
archive's sources is available, and records which one was used.

## Usage

``` r
sighting_distances(
  dat,
  sources = c("angle", "exact", "strip"),
  units = c("m", "km", "nmi"),
  on_effort_only = TRUE,
  strip_scheme = "auto",
  strip_platform = "skymaster",
  strip_left_truncation = FALSE,
  by = NULL
)
```

## Arguments

- dat:

  A data frame of NARWC survey data. Columns that are absent simply make
  their source unavailable; nothing errors.

- sources:

  Precedence order over `"angle"`, `"exact"`, `"strip"`, and
  `"circling"`. Defaults to `c("angle", "exact", "strip")`.

- units:

  `"m"` (default), `"km"`, or `"nmi"`.

- on_effort_only:

  Restrict to on-effort census records. Default `TRUE`.

- strip_scheme, strip_platform, strip_left_truncation:

  Passed to
  [`strip_distance()`](https://camilleross.org/distsamp/reference/strip_distance.md).
  The scheme defaults to `"auto"`, which chooses the code book from
  `DATE`.

- by:

  Grouping columns identifying one occupation of a survey line, for the
  sources that need a track bearing. See
  [`track_bearing()`](https://camilleross.org/distsamp/reference/track_bearing.md).

## Value

`dat` with five columns added:

- `distance`:

  Point distance from the track-line, or `NA` for a row whose source
  gives an interval.

- `distbegin`,`distend`:

  Interval bounds, for `"strip"` rows.

- `side`:

  `"left"`, `"right"`, `"both"`, `"on-track"`, or `NA`.

- `distance_source`:

  Which source supplied the row.

## Four sources, one column

The NARWC archive records right-angle distance four different ways,
because the protocol changed and because some sightings are made off the
track-line. Each has its own function; this assembles them.

|  |  |  |
|----|----|----|
| source | from | gives |
| `"angle"` | `ANGLEL`/`ANGLER` and `ALT` (8.A.2), 2022 onwards | a point distance |
| `"exact"` | `S_LAT`/`S_LONG` (8.A.33, 8.A.34) projected onto the track | a point distance |
| `"strip"` | `STRIP` code books (8.A.31), before 2022 | an **interval** |
| `"circling"` | the break-off record on the census line | a point distance, weakly |

`sources` is a precedence order, not a set: the first one that yields a
distance for a record wins, and `distance_source` records which that
was.

## Why the provenance column is not optional

Mixing sources in one detection function is a decision, and it should be
a conscious one rather than something discovered afterwards. Point and
interval distances cannot share a likelihood — `STRIP` rows must be
fitted binned — and circling distances are estimated minutes after the
detection they describe. Without `distance_source` none of that is
visible in the table a model gets fitted to, and a reviewer will ask.

Where a record carries both an angle and an exact position, the two are
independent measurements of the same quantity. The default order prefers
the angle, because it is taken at the moment the sighting is abeam and
so measures the perpendicular distance directly, with no projection and
no position error. Passing `sources = c("exact", "angle", "strip")`
reverses that. Comparing the two is a genuine check on both, and
[`exact_distance()`](https://camilleross.org/distsamp/reference/exact_distance.md)
returns its own columns for exactly that purpose.

## Circling is opt-in

`"circling"` is not in the default order. Those sightings are usually
real on-effort detections and dropping them thins the near-zero end of
the distance distribution — but the position is fixed after the animal
has moved, so they are a weaker source. Ask for them deliberately, and
see
[`circling_distance()`](https://camilleross.org/distsamp/reference/circling_distance.md).

## Restricted to census records

Handbook 8.A.31 restricts right-angle distance measurement to on-effort
sightings during census lines, and notes that some teams record angles
during transits and circling for practice. Those must not enter a
detection function, so by default distances are left `NA` elsewhere.
`"circling"` is exempt, since those records are off effort by
definition.

## See also

[`perp_distance()`](https://camilleross.org/distsamp/reference/perp_distance.md),
[`exact_distance()`](https://camilleross.org/distsamp/reference/exact_distance.md),
[`strip_distance()`](https://camilleross.org/distsamp/reference/strip_distance.md),
[`circling_distance()`](https://camilleross.org/distsamp/reference/circling_distance.md),
[`detection_data()`](https://camilleross.org/distsamp/reference/detection_data.md),
[`segment_survey()`](https://camilleross.org/distsamp/reference/segment_survey.md)

## Examples

``` r
path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
dat <- flag_effort(make_leg_id(read_narwc(path)))
#> `read_narwc()` renamed 2 columns:
#>   LAT_DD  -> LATITUDE
#>   LONG_DD -> LONGITUDE
#> All matched an exact entry in the alias table; `narwc_column_mapping()` returns this, and `quiet = TRUE` silences it.

out <- sighting_distances(dat)
cols <- c("SPECCODE", "distance", "distbegin", "distend", "side",
          "distance_source")
subset(out, !is.na(distance_source), cols)
#> # A tibble: 8 × 6
#>   SPECCODE distance distbegin distend side  distance_source
#>   <chr>       <dbl>     <dbl>   <dbl> <chr> <chr>          
#> 1 RIWH        229          NA      NA right angle          
#> 2 RIWH        132.         NA      NA left  angle          
#> 3 RIWH        397.         NA      NA right angle          
#> 4 FIWH        629.         NA      NA right angle          
#> 5 RIWH         61.4        NA      NA left  angle          
#> 6 RIWH        855.         NA      NA right angle          
#> 7 RIWH        160.         NA      NA left  angle          
#> 8 SEWH        491.         NA      NA right angle          

# Counts by source - what a methods section has to state
table(out$distance_source, useNA = "no")
#> 
#> angle 
#>     8 

# Prefer the exact position where both it and an angle exist
rev_out <- sighting_distances(dat, sources = c("exact", "angle", "strip"))
table(rev_out$distance_source, useNA = "no")
#> 
#> angle exact 
#>     5     3 
```
