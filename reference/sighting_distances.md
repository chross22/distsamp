# Perpendicular distances for a survey data frame

Resolves a right-angle distance for each sighting from whichever of the
archive's sources is available, and records which one was used.

## Usage

``` r
sighting_distances(
  dat,
  sources = NULL,
  units = c("m", "km", "nmi"),
  platform = c("aerial", "vessel", "ship"),
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
  `"circling"`. `NULL` (default) takes the platform's order:
  `c("angle", "exact", "strip")` for an aircraft, `"exact"` for a
  vessel.

- units:

  `"m"` (default), `"km"`, or `"nmi"`.

- platform:

  `"aerial"` (default), `"vessel"`, or `"ship"` as a synonym for
  `"vessel"`. Decides the default `sources`, and which sources may be
  asked for at all. See
  [`platform_defaults()`](https://camilleross.org/distsamp/reference/platform_defaults.md).

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

## Two of the four are aircraft measurements

`"angle"` is an altitude divided by a tangent, and the `"strip"` code
books are the Skymaster's and the AT-11's (8.A.31). Neither exists on a
vessel. `platform = "vessel"` therefore leaves `"exact"` — a recorded
sighting position projected onto the track, which is geometry rather
than platform — and asking for either of the others errors rather than
returning a column of `NA`. `"circling"` is a break-off from the census
line and applies to both, but is opt-in for both too.

Leave `sources` at `NULL` to take the platform's own order. Naming it
overrides the platform, within what the platform can supply.

## Why the provenance column is not optional

Mixing sources in one detection function should be a deliberate choice.
Point and interval distances cannot share a likelihood (`STRIP` rows
must be fitted binned), and circling distances are estimated minutes
after the detection they describe. `distance_source` makes this visible
in the table a model is fitted to.

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
real on-effort detections, and dropping them thins the near-zero end of
the distance distribution. But the position is fixed after the animal
has moved, so they are a weaker source. Ask for them deliberately, and
see
[`circling_distance()`](https://camilleross.org/distsamp/reference/circling_distance.md).
[`segment_survey()`](https://camilleross.org/distsamp/reference/segment_survey.md)
does not take this source from `distance_sources`, and warns if it is
asked for: a circling record's distance is set when it is attached, and
`segment_survey(circling_distance = "break_off")` uses this same
computation wherever an exact position exists.

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

# A vessel has only the position; the aircraft sources are not offered
sea <- sighting_distances(dat, platform = "vessel")
table(sea$distance_source, useNA = "no")
#> 
#> exact 
#>     3 
```
