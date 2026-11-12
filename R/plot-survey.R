#' Look at the survey partway through the pipeline
#'
#' Draws the records as they stand at whatever stage they have reached, so a
#' segmentation can be checked before it is trusted. `plot()` on a
#' `distsamp_segments` object shows the finished result; this shows the steps
#' that produced it, where a mistake is still legible.
#'
#' @section What each view is for:
#' \describe{
#'   \item{`"effort"`}{Positions coloured by `OnOff.Effort`. Look here first: a
#'     survey that is almost entirely off effort has a criterion failing, and
#'     the map shows whether that is everywhere or on particular days.}
#'   \item{`"occupations"`}{Positions coloured by `LEGNO3`, the line-occupation
#'     identifier. Adjacent occupations take different colours, so one line
#'     split into three occupations, or three merged into one, is visible
#'     immediately. This view catches a bad `make_leg_id()`. A bad `LEGNO3` is
#'     the most consequential error possible: effort is grouped by it and
#'     segments are cut within it.}
#'   \item{`"tracks"`}{Positions coloured by `new_trackno`, the stretches of
#'     *continuous* effort that are actually chopped into segments. Differs
#'     from `"occupations"` wherever effort broke mid-line.}
#'   \item{`"platform"`}{Positions coloured by `PLATFORM_KIND` from
#'     `narwcr::classify_platform()`. For an archive holding more than one kind
#'     of survey.}
#'   \item{`"legstage"`}{Positions coloured by `LEGSTAGE`. Shows where a line
#'     begins, breaks off, resumes and ends, and, on a file that records the
#'     code only at change points, how little of it is written down.}
#'   \item{`"raw"`}{Every position, coloured by `LEGTYPE`, needing nothing but
#'     the file as read. Shows the survey before this package has changed it;
#'     compare the other views against it when a later stage seems to have lost
#'     something.}
#'   \item{`"positions"`}{Every position, uncoloured. It needs only `LATITUDE`
#'     and `LONGITUDE`, so it works on a file that has not been through
#'     [prepare_survey()], or one with unexpected columns. With
#'     `sightings = TRUE` it shows the whole survey, effort and sightings, in
#'     one map.}
#' }
#'
#' @section Thinning:
#' A survey archive can hold millions of positions, and a scatter plot of five
#' million points is neither drawable nor readable. The plotted *points* are
#' thinned to `max_points` by taking every *n*th. The subtitle says when it
#' happened. Set `max_points = Inf` to draw every point.
#'
#' **Thinning never applies to the path.** Every *n*th record preserves the
#' shape of a straight line and loses it at every turn, so a path drawn through
#' the survivors cuts the corners. At three million records that is a chord
#' between fixes some 18 km apart, which can draw a trackline over land. The
#' lines in the `"occupations"` and `"tracks"` views are therefore built from
#' every fix, whatever `max_points` says. On a whole archive this costs a few
#' seconds of drawing.
#'
#' @param dat A survey data frame at any stage: `LATITUDE` and `LONGITUDE` are
#'   required, and each view needs the column it colours by.
#' @param what Which view: `"effort"` (default), `"occupations"`, `"tracks"`,
#'   `"platform"`, `"legstage"`, `"raw"`, or `"positions"`.
#' @param coastline Land to draw underneath. `TRUE` (default) fetches Natural
#'   Earth through `rnaturalearth`; `FALSE` draws none; a scale name
#'   (`"small"`, `"medium"`, `"large"`) picks the resolution; an `sf` object is
#'   drawn as given, and is the better option at bay scale. Unlike
#'   [plot.distsamp_segments()], a coastline that cannot be fetched here gives
#'   a warning and no land, rather than an error.
#' @param max_points Thin to at most this many records. Default `50000`.
#' @param max_legend Most groups to name in the legend. Default `12`. Beyond
#'   this, occupations and tracks take a recycled palette and the legend is
#'   dropped, since a hundred colours cannot be told apart.
#' @param facet_by Column to facet on, or `NULL` for none. Defaults to `DATE`
#'   when the data covers 2 to 12 days. Beyond that the panels are too small
#'   to read, and one map is drawn.
#' @param dates,years,months Which survey days to draw, passed to
#'   [filter_days()]. `NULL` (default) draws all of them. A decade of survey on
#'   one map is unreadable; `years = 2019, months = 8` is not.
#' @param sightings Draw the sightings over the effort? `FALSE` (default) draws
#'   none, `TRUE` draws every species, and a character vector of `SPECCODE`
#'   values draws only those (`sightings = "RIWH"`). They are taken from the
#'   data *before* thinning, since a few thousand sighting rows in three million
#'   would not survive it, and are drawn as outlined markers on top of the
#'   track.
#'
#' @return A `ggplot` object.
#'
#' @seealso [plot.distsamp_segments()] for the finished segmentation,
#'   [diagnose_pipeline()] for the same checks as numbers.
#'
#' @examplesIf requireNamespace("ggplot2", quietly = TRUE)
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' dat <- narwcr::flag_effort(narwcr::make_leg_id(narwcr::read_narwc(path, quiet = TRUE)))
#' plot_survey(dat, "occupations")
#'
#' # One day, or one month of one year
#' plot_survey(dat, "occupations", dates = "2024-04-01")
#' plot_survey(dat, "occupations", years = 2024, months = "April")
#'
#' @export
plot_survey <- function(dat, what = c("effort", "occupations", "tracks",
                                      "platform", "legstage", "raw",
                                      "positions"),
                        coastline = TRUE, max_points = 50000,
                        max_legend = 12, facet_by = NULL,
                        dates = NULL, years = NULL, months = NULL,
                        sightings = FALSE) {
  # Check inputs and cut to the requested days.
  what <- match.arg(what)
  check_ggplot2()
  stopifnot(is.data.frame(dat))
  require_columns(dat, c("LATITUDE", "LONGITUDE"))
  dat <- filter_days(dat, dates, years, months)

  # "positions" colours by a constant column created here, so it needs no
  # column from the data.
  if (what == "positions") {
    dat$.positions <- "position"
  }

  # Per view: the column to colour by (`col`), the legend label (`lab`), and
  # the title. For identifier views, `unit` says in words what one group is,
  # and `grey` what the uncoloured (NA) records are; both go in the subtitle.
  spec <- switch(
    what,
    effort      = list(col = "OnOff.Effort", lab = "On effort",
                       title = "Effort"),
    occupations = list(col = "LEGNO3", lab = "Occupation",
                       title = "Line occupations",
                       unit = "one pass along one survey line",
                       grey = "on no line: transit, ferrying between lines, circling"),
    tracks      = list(col = "new_trackno", lab = "Track",
                       title = "Continuous-effort tracks",
                       unit = "one unbroken stretch of on-effort flying",
                       grey = "off effort"),
    platform    = list(col = "PLATFORM_KIND", lab = "Platform",
                       title = "Platform"),
    legstage    = list(col = "LEGSTAGE", lab = "LEGSTAGE",
                       title = "Line stage"),
    raw         = list(col = "LEGTYPE", lab = "LEGTYPE",
                       title = "As read"),
    positions   = list(col = ".positions", lab = NULL,
                       title = "Every position, as recorded")
  )
  # Stop with a hint on how to produce the column if it is missing.
  if (!spec$col %in% names(dat)) {
    rlang::abort(paste0(
      "The `", what, "` view needs a `", spec$col, "` column, which this data ",
      "does not have yet. ", stage_hint(spec$col)
    ))
  }

  # Resolve the coastline once. A failed fetch gives a warning and no land.
  coastline <- resolve_coastline_soft(coastline)

  # Take sightings before thinning. They are rare rows, and keeping every nth
  # record would discard most of them.
  sight <- if (isFALSE(sightings)) NULL else survey_sightings(dat, sightings)

  # Record count before thinning, for the subtitle.
  n_before <- nrow(dat)

  # `grouped` views colour by an identifier (occupation or track) and draw
  # paths. `.grp` is the colouring value as character.
  grouped <- what %in% c("occupations", "tracks")
  dat$.grp <- as.character(dat[[spec$col]])

  # Path group: day plus identifier. Identifiers are unique only within a
  # day: `split_tracks()` restarts track numbers at 1 each date, and LEGNO3
  # repeats when a LEGNO is reused or built from the `line_<n>` fallback.
  # Grouping on the identifier alone would join one day's path to the next
  # day's with a straight line, often across land.
  dat$.pathgrp <- if ("DATE" %in% names(dat)) {
    paste(dat$DATE, dat$.grp)
  } else {
    dat$.grp
  }

  # Colour mapping. Non-identifier views (effort, platform, LEGSTAGE) have
  # few levels and always keep their names (max_legend = Inf). Identifier
  # views recycle colours beyond `max_legend`.
  cap <- capped_groups(dat$.grp, if (grouped) max_legend else Inf)
  named <- cap$named
  n_groups <- cap$n
  dat$.col <- cap$col

  # Build the path from every fix, before thinning. A path through thinned
  # points cuts corners and can cross land. Records with no identifier
  # (transit, ferrying between lines) are left out of the path; they are drawn
  # as unconnected grey points instead.
  path <- if (grouped) dat[!is.na(dat[[spec$col]]), , drop = FALSE] else NULL

  # Thin the points, then split them into coloured (`drawn`) and grey
  # (`loose`, no identifier) records.
  step <- thin_step(nrow(dat), max_points)
  dat <- thin_records(dat, max_points)

  loose <- if (grouped) is.na(dat[[spec$col]]) else rep(FALSE, nrow(dat))
  drawn <- dat[!loose, , drop = FALSE]

  # Layers, bottom to top: land, grey loose points, coloured points.
  p <- ggplot2::ggplot(
    drawn,
    ggplot2::aes(x = .data$LONGITUDE, y = .data$LATITUDE, colour = .data$.col)
  ) +
    coastline_layer(coastline) +
    (if (any(loose)) {
      ggplot2::geom_point(
        data = dat[loose, , drop = FALSE], colour = "grey75", size = 0.4,
        na.rm = TRUE, inherit.aes = FALSE,
        mapping = ggplot2::aes(x = .data$LONGITUDE, y = .data$LATITUDE)
      )
    }) +
    ggplot2::geom_point(size = 0.5, na.rm = TRUE) +
    # "positions" is a single group, drawn in neutral grey with no legend. A
    # palette colour would suggest a meaning it does not have, and grey lets
    # overlaid sightings stand out.
    (if (what == "positions") {
      ggplot2::scale_colour_manual(values = "grey40", guide = "none")
    } else {
      scale_colour_safe(nlevels(dat$.col))
    }) +
    map_coord(coastline, dat$LONGITUDE, dat$LATITUDE) +
    ggplot2::labs(
      x = "Longitude", y = "Latitude",
      colour = spec$lab,
      title = spec$title,
      subtitle = plot_survey_subtitle(drawn, spec, grouped, n_before,
                                      sum(loose), named, sight, step)
    ) +
    ggplot2::theme_minimal()

  # Paths for identifier views, from the unthinned records.
  if (grouped) {
    p <- p + ggplot2::geom_path(data = path,
                                ggplot2::aes(group = .data$.pathgrp),
                                linewidth = 0.3, na.rm = TRUE)
  }
  # Legend layout. Skipped for "positions": `guides()` overrides the scale and
  # would restore the single-entry legend the scale suppressed.
  if (what != "positions") {
    p <- p + legend_guide(nlevels(dat$.col))
  }

  # No legend when colours are recycled: they then mean only that neighbours
  # differ.
  if (grouped && !named) {
    p <- p + ggplot2::guides(colour = "none")
  }

  # Sightings on the `fill` scale, with rare species lumped into "other" so at
  # most 8 colours are needed.
  if (!is.null(sight)) {
    sight$.spp <- lump_levels(sight$SPECCODE, max_levels = min(max_legend, 8L))
    p <- p +
      ggplot2::geom_point(
        data = sight, inherit.aes = FALSE, na.rm = TRUE, shape = 21,
        size = 1.9, stroke = 0.3, colour = "grey15",
        mapping = ggplot2::aes(x = .data$LONGITUDE, y = .data$LATITUDE,
                               fill = .data$.spp)
      ) +
      scale_fill_safe(nlevels(sight$.spp), name = "Sightings") +
      ggplot2::guides(fill = ggplot2::guide_legend(
        override.aes = list(size = 2.8), order = 2
      ))
  }

  # Facet by the requested column, or by DATE for 2 to 12 days.
  facet_by <- resolve_facet(dat, facet_by)
  if (!is.null(facet_by)) {
    p <- p + ggplot2::facet_wrap(stats::as.formula(paste("~", facet_by)))
  }
  p
}

# Subtitle for plot_survey(), in plain words. Line 1 (identifier views only):
# how many groups there are, what one group is, and whether colours repeat.
# Line 2: how many records are drawn, whether they were thinned, what the
# grey points are, and how many sightings are drawn.
plot_survey_subtitle <- function(dat, spec, grouped, n_before, n_loose = 0L,
                                 named = TRUE, sight = NULL, step = 1L) {
  # Records drawn after thinning, coloured plus grey.
  shown <- nrow(dat) + n_loose
  big <- fmt_count

  what_colours <- if (grouped) {
    n <- length(unique(dat$.grp))
    paste0(
      big(n), " ", tolower(spec$lab), "s - ", spec$unit, ". ",
      # Kept short so the line is not clipped at the figure's width.
      if (named) "Each has its own colour." else "Colours repeat; neighbours differ."
    )
  } else NULL

  how_much <- paste0(
    big(shown), " records",
    if (shown < n_before) {
      paste0(" of ", big(n_before), " (1 in every ", big(step), ")")
    } else "",
    if (n_loose) {
      paste0("; ", big(n_loose), " in grey are ", spec$grey)
    } else "",
    if (!is.null(sight)) {
      paste0("; ", big(nrow(sight)), " sightings, all of them (never thinned)")
    } else ""
  )

  paste(c(what_colours, how_much), collapse = "\n")
}

# Thin to at most `max_points` rows by keeping every nth row, n =
# ceiling(rows / max_points). Every nth rather than a random sample keeps the
# shape of the track visible. Infinite `max_points` keeps everything.
thin_records <- function(dat, max_points) {
  dat[seq(1L, nrow(dat), by = thin_step(nrow(dat), max_points)), , drop = FALSE]
}

# Every how many records thin_records() keeps one: 1 when no thinning is
# needed.
thin_step <- function(n, max_points) {
  if (!is.finite(max_points) || n <= max_points) 1L else ceiling(n / max_points)
}

# Column to facet on, or NULL. A requested column is used if it exists.
# Otherwise DATE is used when the data covers 2 to 12 days.
resolve_facet <- function(dat, facet_by) {
  if (!is.null(facet_by)) {
    return(if (facet_by %in% names(dat)) facet_by else NULL)
  }
  if (!"DATE" %in% names(dat)) {
    return(NULL)
  }
  n <- length(unique(dat$DATE))
  if (n >= 2L && n <= 12L) "DATE" else NULL
}

# Error-message hint for a missing column `col`.
#
# The preparation steps must run in a fixed order. For example, filtering by
# platform before `make_leg_id()` makes two occupations of one line adjacent,
# so they merge and the ferry between them counts as effort. Each hint
# therefore names `prepare_survey()`, which runs the steps in order, and says
# where in that order the missing column is created.
stage_hint <- function(col) {
  prep <- "Run `prepare_survey()`, which does these steps in the order they have to happen."
  switch(
    col,
    OnOff.Effort = paste0(
      prep, " Effort is flagged last: `narwcr::flag_effort()` reads LEGTYPE, ",
      "LEGSTAGE, ALT, BEAUFORT and VISIBLTY, so anything that corrects those ",
      "has to have run before it."
    ),
    LEGNO3 = paste0(
      prep, " Occupations come first, from `narwcr::make_leg_id()`, because ",
      "everything after them groups by them."
    ),
    new_trackno = paste0(
      prep, " Tracks are cut by `split_tracks()` from `LEGNO3` and ",
      "`OnOff.Effort`, so both have to exist already."
    ),
    PLATFORM_KIND = paste0(
      prep, " Platform is classified after `make_leg_id()` and never before: ",
      "dropping records first makes two occupations of one line adjacent, so ",
      "they merge and the ferry between them counts as survey effort."
    ),
    LEGSTAGE = paste0(
      "It comes from the survey file. `prepare_survey()` completes a partial ",
      "one with `narwcr::fill_legstage()`, but it cannot invent a column that ",
      "was never recorded."
    ),
    LEGTYPE = "It comes from the survey file; every NARWC extract has one.",
    ""
  )
}
