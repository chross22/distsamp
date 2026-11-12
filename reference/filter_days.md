# Keep the survey days you want to look at

Subsets a survey to particular days, years, or months. The plotting
functions take the same three arguments and pass them here, so this is
mainly useful when the subset is wanted for something other than a plot.

## Usage

``` r
filter_days(dat, dates = NULL, years = NULL, months = NULL)
```

## Arguments

- dat:

  A survey data frame with a `DATE` column.

- dates:

  Days to keep: `Date` objects, or strings
  [`as.Date()`](https://rdrr.io/r/base/as.Date.html) accepts, such as
  `"2019-08-14"`. `NULL` (default) keeps every day.

- years:

  Years to keep, as numbers: `2019`, or `2015:2019`.

- months:

  Months to keep, as numbers (`8`), full names (`"August"`), or
  abbreviations (`"Aug"`). Names are matched without regard to case.

## Value

`dat` with the unwanted rows removed.

## Why this exists

A NARWC extract spans decades, and little is learned by drawing it
whole. A plot usually answers a question about one stretch: the day an
occupation looked wrong, the August the survey pattern changed, the year
an era boundary falls in. Naming that stretch gives one readable figure
instead of hundreds.

## How the three combine

Given together they narrow; they do not accumulate.
`years = 2019, months = 8` keeps August 2019, not all of 2019 plus every
August. `dates` is combined the same way, so `dates` plus a `years` that
excludes them keeps nothing, and raises an error rather than drawing an
empty map.

Records with no `DATE` are dropped whenever any of the three is given: a
record with no date is in no month. With all three `NULL` the data is
returned unchanged, undated records included.

## See also

[`plot_survey()`](https://camilleross.org/distsamp/reference/plot_survey.md)
and
[`plot_survey_panel()`](https://camilleross.org/distsamp/reference/plot_survey_panel.md),
which take these arguments directly.

## Examples

``` r
path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
dat <- read_narwc(path, quiet = TRUE)

# One day, by name
nrow(filter_days(dat, dates = "2024-04-01"))
#> [1] 56

# A whole month, and a month within a year
nrow(filter_days(dat, months = "April"))
#> [1] 113
nrow(filter_days(dat, years = 2024, months = 4))
#> [1] 113
```
