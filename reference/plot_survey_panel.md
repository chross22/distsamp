# Several views of a survey, side by side

Draws more than one
[`plot_survey()`](https://camilleross.org/distsamp/reference/plot_survey.md)
view on one figure, so the stages can be compared without holding two
windows next to each other. Optionally writes one figure per survey day.

## Usage

``` r
plot_survey_panel(
  dat,
  views = NULL,
  by_day = FALSE,
  dir = "survey-panels",
  ncol = NULL,
  width = 14,
  height = 9,
  dpi = 120,
  dates = NULL,
  years = NULL,
  months = NULL,
  ...
)
```

## Arguments

- dat:

  A survey data frame at any stage.

- views:

  Which views to draw. Defaults to the ones the data supports, in
  pipeline order: a view whose column is absent is skipped rather than
  erroring, because the point is to see how far the data has got.

- by_day:

  Write one figure per survey day instead of returning one figure for
  everything? Default `FALSE`.

- dir:

  Directory the per-day figures are written to. Default
  `"survey-panels"`, created if needed. It is deliberately not the
  working directory: `by_day = TRUE` over a season writes one file per
  survey day.

- ncol:

  Panels per row. Defaults to a layout chosen from how many views there
  are, which is what you want unless a particular figure needs a shape.

- width, height, dpi:

  Size of the written figures, in inches and dots per inch. Only used
  when `by_day = TRUE`; otherwise the figure is returned and the caller
  decides.

- dates, years, months:

  Narrow which survey days are drawn, as in
  [`filter_days()`](https://camilleross.org/distsamp/reference/filter_days.md).
  They narrow together rather than adding up: `years = 2019` with
  `months = 8` is August 2019, not all of 2019 and every August.

- ...:

  Passed to
  [`plot_survey()`](https://camilleross.org/distsamp/reference/plot_survey.md)
  for every view - `coastline`, `sightings`, `max_points` and the rest.
  A coastline resolved once and passed in is much faster than
  `coastline = TRUE`, which refetches Natural Earth for every panel of
  every day.

## Why side by side

The views answer each other. `"raw"` shows every position the file
holds; `"platform"` shows which of them this package will keep;
`"effort"` shows which of *those* count; `"occupations"` shows how they
were divided into lines. A record that vanishes between two panels is
the question worth asking, and it is far easier to see in one figure
than in four.

## One figure per day

`by_day = TRUE` writes a figure for each survey day into `dir`. A season
on one map is a smear — 24,795 line occupations over 187 days tell you
nothing about any of them — while a day is a handful of lines you can
actually check. The files are named `survey-<date>.png` and the paths
are returned, so a `targets` pipeline can track them.

## See also

[`plot_survey()`](https://camilleross.org/distsamp/reference/plot_survey.md),
which draws one view.
