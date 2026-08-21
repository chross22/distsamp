# Diagnose common reasons a segmentation might be wrong before you trust it

Runs the reading and segmentation pipeline —
[`read_narwc()`](https://rdrr.io/pkg/narwcr/man/read_narwc.html),
[`validate_narwc()`](https://camilleross.org/distsamp/reference/validate_narwc.md),
[`make_leg_id()`](https://rdrr.io/pkg/narwcr/man/make_leg_id.html),
[`flag_effort()`](https://rdrr.io/pkg/narwcr/man/flag_effort.html),
[`point_to_point_effort()`](https://camilleross.org/distsamp/reference/point_to_point_effort.md)
and
[`segment_survey()`](https://camilleross.org/distsamp/reference/segment_survey.md)
— and reports on the ways a real extract goes wrong quietly. Meant to be
run once against a new dataset, before any of its numbers are used.

## Usage

``` r
diagnose_pipeline(x, days = NULL, seg_length = 10, species = NULL, ...)
```

## Arguments

- x:

  A path to a NARWC CSV, or a data frame. A path is read with
  [`read_narwc()`](https://rdrr.io/pkg/narwcr/man/read_narwc.html); a
  data frame is taken as already read.

- days:

  Which survey days to diagnose, so a large extract can be checked in
  seconds before it is run in full. `"auto"` picks the day with the most
  census records carrying every criterion
  [`flag_effort()`](https://rdrr.io/pkg/narwcr/man/flag_effort.html)
  needs; a number takes that many days from the start; a `Date` or date
  string takes exactly those days. `NULL` (default) uses everything.

  `"auto"` is the one to reach for. The start of a season is often
  atypical — a day may not record the altitude or sea state the rest of
  the file does — and every criterion fails on a missing value, so an
  unrepresentative day reports no effort at all while the file is fine.

  Whole days are kept, never a sample of records. Effort and
  segmentation are computed from consecutive positions along a line, so
  a random subset of records would report distances across gaps that are
  an artefact of the sampling — a diagnosis of the subset rather than of
  the data. Every total printed is then for the subset, and the header
  says so.

- seg_length:

  Segment length in km, passed to
  [`segment_survey()`](https://camilleross.org/distsamp/reference/segment_survey.md).
  Default `10`.

- species:

  Passed to
  [`segment_survey()`](https://camilleross.org/distsamp/reference/segment_survey.md).
  Default `NULL`.

- ...:

  Passed to
  [`read_narwc()`](https://rdrr.io/pkg/narwcr/man/read_narwc.html) when
  `x` is a path — `profile`, `extra_columns`, `prefer_source` and so on.

## Value

Invisibly, a list with whichever of `dat`, `findings` and `segments` the
checks reached before a fatal problem stopped them, so investigating can
carry on from there.

## Details

The failure this exists for is not the one that errors. It is the one
that returns a plausible number: effort that silently includes the ferry
between two survey days, an altitude read as metres when the column was
named in feet, a position taken from the vessel when the aircraft's GPS
track was sitting in the file. Each of those produces a density estimate
that is wrong by a factor and looks entirely reasonable.

Every check reports rather than fixes. This function never modifies the
data or the arguments it was given.

## See also

[`validate_narwc()`](https://camilleross.org/distsamp/reference/validate_narwc.md)
for the per-record checks this summarises,
[`line_effort()`](https://camilleross.org/distsamp/reference/line_effort.md)
and
[`reflight_summary()`](https://camilleross.org/distsamp/reference/reflight_summary.md)
for the per-line detail behind the effort totals, and
[`plot()`](https://rdrr.io/r/graphics/plot.default.html) on the result
of
[`segment_survey()`](https://camilleross.org/distsamp/reference/segment_survey.md).

## Examples

``` r
path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
invisible(diagnose_pipeline(path, seg_length = 5))
#> distsamp pipeline diagnosis
#> 
#> == Reading ==
#>   ok    113 records, 30 columns
#> 
#> == Handbook validation ==
#>   ok    legstage_line_not_closed (1 records): A line occupation has no end-line (LEGSTAGE 5). This is normal for a line abandoned mid-flight - for weather, or to re-fly it later - and a problem only if the line was flown to completion.
#> 
#> == Platform ==
#>   ok    1 distinct PLATFORM value(s): 210 x 113
#> 
#> == Line identity ==
#>   ok    6 line occupation(s) over 2 survey day(s), 5 record(s) on no line
#> 
#> == Altitude ==
#>   ok    median ALT 229 m
#> 
#> == Effort ==
#>         off effort by criterion (defaults; a record can fail more than one):
#>           BEAUFORT above 3: 2
#>           LEGTYPE not 2: 10
#>   ok    101 of 113 records on effort
#>   ok    92.2 km of on-effort track
#>   ok    grouping without DATE gives the same total; no days are merging
#>   ok    median speed 86 knots, consistent with a survey aircraft
#> 
#> == Right-angle distance sources ==
#>   ok    14 sighting record(s)
#>   ok    9 with a declination angle
#>   ok    4 with an exact position
#>   ok    9 with a strip code
#> 
#> == Segments ==
#>   ok    20 segment(s) at seg_length = 5 km
#>   ok    every segment carries effort
#> 
#> Nothing above needs attention.
```
