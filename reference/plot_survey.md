# Look at the survey partway through the pipeline

Draws the records as they stand at whatever stage they have reached, so
a segmentation can be checked before it is trusted.
[`plot()`](https://rdrr.io/r/graphics/plot.default.html) on a
`distsamp_segments` object shows the finished result; this shows the
steps that produced it, where a mistake is still legible.

## Usage

``` r
plot_survey(
  dat,
  what = c("effort", "occupations", "tracks", "platform", "legstage", "raw", "positions"),
  coastline = TRUE,
  max_points = 50000,
  max_legend = 12,
  facet_by = NULL,
  dates = NULL,
  years = NULL,
  months = NULL,
  sightings = FALSE
)
```

## Arguments

- dat:

  A survey data frame at any stage: `LATITUDE` and `LONGITUDE` are
  required, and each view needs the column it colours by.

- what:

  Which view: `"effort"` (default), `"occupations"`, `"tracks"`,
  `"platform"`, `"legstage"`, `"raw"`, or `"positions"`.

- coastline:

  Land to draw underneath. `TRUE` (default) fetches Natural Earth
  through `rnaturalearth`; `FALSE` draws none; a scale name (`"small"`,
  `"medium"`, `"large"`) picks the resolution; an `sf` object is drawn
  as given, and is the better option at bay scale. Unlike
  [`plot.distsamp_segments()`](https://camilleross.org/distsamp/reference/plot.distsamp_segments.md),
  a coastline that cannot be fetched here gives a warning and no land,
  rather than an error.

- max_points:

  Thin to at most this many records. Default `50000`.

- max_legend:

  Most groups to name in the legend. Default `12`. Beyond this,
  occupations and tracks take a recycled palette and the legend is
  dropped, since a hundred colours cannot be told apart.

- facet_by:

  Column to facet on, or `NULL` for none. Defaults to `DATE` when the
  data covers 2 to 12 days. Beyond that the panels are too small to
  read, and one map is drawn.

- dates, years, months:

  Which survey days to draw, passed to
  [`filter_days()`](https://camilleross.org/distsamp/reference/filter_days.md).
  `NULL` (default) draws all of them. A decade of survey on one map is
  unreadable; `years = 2019, months = 8` is not.

- sightings:

  Draw the sightings over the effort? `FALSE` (default) draws none,
  `TRUE` draws every species, and a character vector of `SPECCODE`
  values draws only those (`sightings = "RIWH"`). They are taken from
  the data *before* thinning, since a few thousand sighting rows in
  three million would not survive it, and are drawn as outlined markers
  on top of the track.

## Value

A `ggplot` object.

## What each view is for

- `"effort"`:

  Positions coloured by `OnOff.Effort`. Look here first: a survey that
  is almost entirely off effort has a criterion failing, and the map
  shows whether that is everywhere or on particular days.

- `"occupations"`:

  Positions coloured by `LEGNO3`, the line-occupation identifier.
  Adjacent occupations take different colours, so one line split into
  three occupations, or three merged into one, is visible immediately.
  This view catches a bad
  [`make_leg_id()`](https://camilleross.org/narwcr/reference/make_leg_id.html).
  A bad `LEGNO3` is the most consequential error possible: effort is
  grouped by it and segments are cut within it.

- `"tracks"`:

  Positions coloured by `new_trackno`, the stretches of *continuous*
  effort that are actually chopped into segments. Differs from
  `"occupations"` wherever effort broke mid-line.

- `"platform"`:

  Positions coloured by `PLATFORM_KIND` from
  [`narwcr::classify_platform()`](https://camilleross.org/narwcr/reference/classify_platform.html).
  For an archive holding more than one kind of survey.

- `"legstage"`:

  Positions coloured by `LEGSTAGE`. Shows where a line begins, breaks
  off, resumes and ends, and, on a file that records the code only at
  change points, how little of it is written down.

- `"raw"`:

  Every position, coloured by `LEGTYPE`, needing nothing but the file as
  read. Shows the survey before this package has changed it; compare the
  other views against it when a later stage seems to have lost
  something.

- `"positions"`:

  Every position, uncoloured. It needs only `LATITUDE` and `LONGITUDE`,
  so it works on a file that has not been through
  [`prepare_survey()`](https://camilleross.org/distsamp/reference/prepare_survey.md),
  or one with unexpected columns. With `sightings = TRUE` it shows the
  whole survey, effort and sightings, in one map.

## Thinning

A survey archive can hold millions of positions, and a scatter plot of
five million points is neither drawable nor readable. The plotted
*points* are thinned to `max_points` by taking every *n*th. The subtitle
says when it happened. Set `max_points = Inf` to draw every point.

**Thinning never applies to the path.** Every *n*th record preserves the
shape of a straight line and loses it at every turn, so a path drawn
through the survivors cuts the corners. At three million records that is
a chord between fixes some 18 km apart, which can draw a trackline over
land. The lines in the `"occupations"` and `"tracks"` views are
therefore built from every fix, whatever `max_points` says. On a whole
archive this costs a few seconds of drawing.

## See also

[`plot.distsamp_segments()`](https://camilleross.org/distsamp/reference/plot.distsamp_segments.md)
for the finished segmentation,
[`diagnose_pipeline()`](https://camilleross.org/distsamp/reference/diagnose_pipeline.md)
for the same checks as numbers.

## Examples

``` r
path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
dat <- narwcr::flag_effort(narwcr::make_leg_id(narwcr::read_narwc(path, quiet = TRUE)))
plot_survey(dat, "occupations")


# One day, or one month of one year
plot_survey(dat, "occupations", dates = "2024-04-01")

plot_survey(dat, "occupations", years = 2024, months = "April")
```
