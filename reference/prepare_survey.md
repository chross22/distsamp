# Get a NARWC extract ready to segment

Runs the steps between reading a file and segmenting it, in the order
they have to happen: line occupations, line state, platform, effort.
Each is exported and can be run by hand; this exists because the order
is not obvious and getting it wrong is quiet.

## Usage

``` r
prepare_survey(
  dat,
  platform = c("aerial", "vessel", "ship", "all"),
  fill_legstage = TRUE,
  correct = NULL,
  effort_args = list(),
  quiet = FALSE
)

prepare_aerial(
  dat,
  platform = c("aerial", "vessel", "ship", "all"),
  fill_legstage = TRUE,
  correct = NULL,
  effort_args = list(),
  quiet = FALSE
)
```

## Arguments

- dat:

  A NARWC data frame from
  [`narwcr::read_narwc()`](https://camilleross.org/narwcr/reference/read_narwc.html).

- platform:

  Which platform to keep: `"aerial"` (default), `"vessel"` (or `"ship"`,
  the same thing), or `"all"` to classify without filtering. See
  [`platform_defaults()`](https://camilleross.org/distsamp/reference/platform_defaults.md)
  for what each one changes.

- fill_legstage:

  Reconstruct the line state where no `LEGSTAGE` was written? Default
  `TRUE`. See
  [`narwcr::fill_legstage()`](https://camilleross.org/narwcr/reference/fill_legstage.html).

- correct:

  A function applied to the filtered frame *before* effort is flagged,
  or `NULL`. This is where a correction that only applies to the records
  being kept goes — an altitude recorded in feet, most often. It has to
  happen here:
  [`flag_effort()`](https://camilleross.org/narwcr/reference/flag_effort.html)
  reads `ALT`, so correcting afterwards leaves every record failing the
  altitude ceiling, and correcting before the platform filter scales
  ship altitudes that were already metres.

- effort_args:

  Named list passed to
  [`narwcr::flag_effort()`](https://camilleross.org/narwcr/reference/flag_effort.html),
  for a programme whose criteria differ from the defaults. Merged over
  the platform's own defaults, so naming an argument here overrides it.

- quiet:

  Suppress the running commentary. Default `FALSE`.

## Value

`dat` with `LEGNO2`, `LEGNO3`, `LEGSTAGE_FILLED`, `PLATFORM_KIND` and
`OnOff.Effort` added, filtered to `platform`.

## Details

`prepare_aerial()` is the same function with `platform = "aerial"` in
its name rather than its arguments. It takes the platform argument too,
so existing code keeps working.

## The order, and why it is not obvious

- [`make_leg_id()`](https://camilleross.org/narwcr/reference/make_leg_id.html)
  first:

  Everything downstream groups by `LEGNO3`.

- `fill_legstage()` second:

  It needs `LEGNO3` to know where an occupation ends, and it must run
  before effort, because a right-angle distance needs `LEGSTAGE == 2`
  (handbook 8.A.31). On a real archive 1,928 of 2,280 on-effort census
  sightings were ineligible without it — for a code recorded only when
  it changed.

- `classify_platform()` third, and the filter *after*
  [`make_leg_id()`](https://camilleross.org/narwcr/reference/make_leg_id.html):

  Removing records before occupations are built makes two occupations of
  one line adjacent, so they merge and the ferry between them becomes
  survey effort. Measured at 224.5 km where 4.4 km was right.

- [`flag_effort()`](https://camilleross.org/narwcr/reference/flag_effort.html)
  last:

  It reads `LEGTYPE`, `LEGSTAGE`, `ALT`, `BEAUFORT` and `VISIBLTY`, so
  anything that corrects those has to have happened already.

## Aerial or vessel

The platform decides which records survive the filter *and* which effort
criteria apply. Those two have to move together: the handbook's altitude
ceiling is an aircraft criterion, and a vessel record carries no `ALT`,
so a survey filtered to its vessel records and then judged on the aerial
criteria is a survey with no effort at all. `platform = "vessel"` sets
both, from
[`platform_defaults()`](https://camilleross.org/distsamp/reference/platform_defaults.md),
and anything you name in `effort_args` still wins over what it chose.

`"ship"` is accepted as a synonym for `"vessel"`. `"all"` classifies
without filtering and leaves the effort criteria at the aerial defaults,
because on a mixed file there is no one right answer — it is for looking
at what the filter would do, not for feeding a model.

## What it deliberately does not do

Anything that is an assertion about a particular file rather than a fact
about NARWC data. Mapping a declination angle out of a column the
handbook does not name, and correcting an altitude recorded in feet, are
claims only you can make. The first goes before this call; the second
goes in `correct`, because where it happens changes what it does:

    dat <- narwcr::angles_from_declination(dat, "Decl_Angle", "Left_or_Right")

    air <- prepare_survey(dat, correct = function(x) {
      feet <- !is.na(x$ALT) & x$DATE >= as.Date("2024-01-01")
      x$ALT[feet] <- x$ALT[feet] * 0.3048
      x
    })

`correct` runs after the platform filter and before effort is flagged,
which is the only place it can go: applying it earlier scales ship
altitudes that were already metres, and applying it later leaves every
record failing the altitude ceiling that
[`flag_effort()`](https://camilleross.org/narwcr/reference/flag_effort.html)
has already tested.

## See also

[`platform_defaults()`](https://camilleross.org/distsamp/reference/platform_defaults.md)
for what a platform decides,
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
air <- prepare_survey(dat, quiet = TRUE)
table(air$PLATFORM_KIND)
#> 
#> stationary     vessel     aerial 
#>          0          0        113 

# The shipboard records of the same file, judged on criteria an aircraft
# altitude plays no part in
sea <- prepare_survey(dat, platform = "vessel", quiet = TRUE)
table(sea$PLATFORM_KIND)
#> 
#> stationary     vessel     aerial 
#>          0          0          0 
```
