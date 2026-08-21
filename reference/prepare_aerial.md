# Get a NARWC extract ready to segment

Runs the steps between reading a file and segmenting it, in the order
they have to happen: line occupations, line state, platform, effort.
Each is exported and can be run by hand; this exists because the order
is not obvious and getting it wrong is quiet.

## Usage

``` r
prepare_aerial(
  dat,
  platform = c("aerial", "all"),
  fill_legstage = TRUE,
  correct = NULL,
  effort_args = list(),
  quiet = FALSE
)
```

## Arguments

- dat:

  A NARWC data frame from
  [`narwcr::read_narwc()`](https://rdrr.io/pkg/narwcr/man/read_narwc.html).

- platform:

  Which platform to keep: `"aerial"` (default), or `"all"` to classify
  without filtering. This package is aerial by construction — its effort
  criteria and
  [`perp_distance()`](https://camilleross.org/distsamp/reference/perp_distance.md)
  both assume an aircraft.

- fill_legstage:

  Reconstruct the line state where no `LEGSTAGE` was written? Default
  `TRUE`. See
  [`narwcr::fill_legstage()`](https://rdrr.io/pkg/narwcr/man/fill_legstage.html).

- correct:

  A function applied to the filtered frame *before* effort is flagged,
  or `NULL`. This is where a correction that only applies to the aerial
  records goes — an altitude recorded in feet, most often. It has to
  happen here:
  [`flag_effort()`](https://rdrr.io/pkg/narwcr/man/flag_effort.html)
  reads `ALT`, so correcting afterwards leaves every record failing the
  altitude ceiling, and correcting before the platform filter scales
  ship altitudes that were already metres.

- effort_args:

  Named list passed to
  [`narwcr::flag_effort()`](https://rdrr.io/pkg/narwcr/man/flag_effort.html),
  for a programme whose criteria differ from the CETAP defaults.

- quiet:

  Suppress the running commentary. Default `FALSE`.

## Value

`dat` with `LEGNO2`, `LEGNO3`, `LEGSTAGE_FILLED`, `PLATFORM_KIND` and
`OnOff.Effort` added, filtered to `platform`.

## The order, and why it is not obvious

- [`make_leg_id()`](https://rdrr.io/pkg/narwcr/man/make_leg_id.html)
  first:

  Everything downstream groups by `LEGNO3`.

- `fill_legstage()` second:

  It needs `LEGNO3` to know where an occupation ends, and it must run
  before effort, because a right-angle distance needs `LEGSTAGE == 2`
  (handbook 8.A.31). On a real archive 1,928 of 2,280 on-effort census
  sightings were ineligible without it — for a code recorded only when
  it changed.

- `classify_platform()` third, and the filter *after*
  [`make_leg_id()`](https://rdrr.io/pkg/narwcr/man/make_leg_id.html):

  Removing records before occupations are built makes two occupations of
  one line adjacent, so they merge and the ferry between them becomes
  survey effort. Measured at 224.5 km where 4.4 km was right.

- [`flag_effort()`](https://rdrr.io/pkg/narwcr/man/flag_effort.html)
  last:

  It reads `LEGTYPE`, `LEGSTAGE`, `ALT`, `BEAUFORT` and `VISIBLTY`, so
  anything that corrects those has to have happened already.

## What it deliberately does not do

Anything that is an assertion about a particular file rather than a fact
about NARWC data. Mapping a declination angle out of a column the
handbook does not name, and correcting an altitude recorded in feet, are
claims only you can make. The first goes before this call; the second
goes in `correct`, because where it happens changes what it does:

    dat <- narwcr::angles_from_declination(dat, "Decl_Angle", "Left_or_Right")

    air <- prepare_aerial(dat, correct = function(x) {
      feet <- !is.na(x$ALT) & x$DATE >= as.Date("2024-01-01")
      x$ALT[feet] <- x$ALT[feet] * 0.3048
      x
    })

`correct` runs after the platform filter and before effort is flagged,
which is the only place it can go: applying it earlier scales ship
altitudes that were already metres, and applying it later leaves every
record failing the altitude ceiling that
[`flag_effort()`](https://rdrr.io/pkg/narwcr/man/flag_effort.html) has
already tested.

## See also

[`diagnose_pipeline()`](https://camilleross.org/distsamp/reference/diagnose_pipeline.md)
to check the result,
[`plot_survey()`](https://camilleross.org/distsamp/reference/plot_survey.md)
to look at it,
[`segment_survey()`](https://camilleross.org/distsamp/reference/segment_survey.md)
for what comes next.

## Examples

``` r
path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
dat <- narwcr::read_narwc(path, quiet = TRUE)
air <- prepare_aerial(dat, quiet = TRUE)
table(air$PLATFORM_KIND)
#> 
#> stationary     vessel     aerial 
#>          0          0        113 
```
