#' Look at the survey partway through the pipeline
#'
#' Draws the records as they stand at whatever stage they have reached, so a
#' segmentation can be checked before it is trusted. `plot()` on a
#' `distsamp_segments` object shows the finished result; this shows the steps
#' that produced it, where a mistake is still legible.
#'
#' @section What each view is for:
#' \describe{
#'   \item{`"effort"`}{Positions coloured by `OnOff.Effort`. The first thing to
#'     look at: a survey that is almost entirely off effort has a criterion
#'     failing, and the map says whether it is everywhere or on particular
#'     days.}
#'   \item{`"occupations"`}{Positions coloured by `LEGNO3`, the line-occupation
#'     identifier. Adjacent occupations take different colours, so a line that
#'     should be one occupation and is drawn in three — or three that are drawn
#'     as one — is visible immediately. This is the view that catches a bad
#'     `make_leg_id()`, and a bad `LEGNO3` is the single most consequential
#'     thing that can go wrong: effort is grouped by it and segments are cut
#'     within it.}
#'   \item{`"tracks"`}{Positions coloured by `new_trackno`, the stretches of
#'     *continuous* effort that are actually chopped into segments. Differs
#'     from `"occupations"` wherever effort broke mid-line.}
#'   \item{`"platform"`}{Positions coloured by `PLATFORM_KIND` from
#'     `narwcr::classify_platform()`. For an archive holding more than one kind
#'     of survey.}
#'   \item{`"legstage"`}{Positions coloured by `LEGSTAGE`. Shows where a line
#'     begins, breaks off, resumes and ends — and, on a file that records the
#'     code only at change points, how little of it is written down.}
#'   \item{`"raw"`}{Every position, coloured by `LEGTYPE`, needing nothing but
#'     the file as read. What the survey looks like before any of this package
#'     has touched it — the view to compare the others against when a later
#'     stage seems to have lost something.}
#'   \item{`"positions"`}{Every position, uncoloured. The only view that cannot
#'     fail for want of a column: it needs `LATITUDE` and `LONGITUDE` and
#'     nothing else, so it works on a file that has not been through
#'     [prepare_aerial()], or one whose columns are not what you expected.
#'     Where `"raw"` still asks for `LEGTYPE`, this asks for nothing. Add
#'     `sightings = TRUE` and it is the whole survey — effort and what was seen
#'     on it — in one map.}
#' }
#'
#' @section Thinning:
#' A survey archive can hold millions of positions, and a scatter plot of five
#' million points is neither drawable nor readable. Records are thinned to
#' `max_points` by taking every *n*th, which preserves the shape of a track
#' where random sampling would not. The subtitle says when it happened. Set
#' `max_points = Inf` to draw everything.
#'
#' @param dat A survey data frame at any stage: `LATITUDE` and `LONGITUDE` are
#'   required, and each view needs the column it colours by.
#' @param what Which view: `"effort"` (default), `"occupations"`, `"tracks"`,
#'   `"platform"`, `"legstage"`, `"raw"`, or `"positions"`.
#' @param coastline Land to draw underneath. `TRUE` (default) fetches Natural
#'   Earth through `rnaturalearth`; `FALSE` draws none; a scale name —
#'   `"small"`, `"medium"`, `"large"` — picks the resolution; or pass your own
#'   `sf`, which is the better option at bay scale. Unlike
#'   [plot.distsamp_segments()], a coastline that cannot be fetched here warns
#'   and draws nothing rather than erroring: this is a look-at-it function, and
#'   losing the land is better than losing the plot.
#' @param max_points Thin to at most this many records. Default `50000`.
#' @param max_legend Most groups to name in the legend. Default `12`. Beyond
#'   this, occupations and tracks take a recycled palette and the legend is
#'   dropped — a hundred labels is not a legend, and a hundred colours cannot
#'   be told apart.
#' @param facet_by Column to facet on, or `NULL` for none. Defaults to `DATE`
#'   when the data covers 2 to 12 days — beyond that the panels are too small
#'   to read, and one map of everything is more use.
#' @param dates,years,months Which survey days to draw, passed to
#'   [filter_days()]. `NULL` (default) draws all of them. A decade of survey on
#'   one map is a smear; `years = 2019, months = 8` is a question a map can
#'   answer.
#' @param sightings Draw the sightings over the effort? `FALSE` (default) draws
#'   none, `TRUE` draws every species, and a character vector of `SPECCODE`
#'   values draws only those — `sightings = "RIWH"`. They are taken from the
#'   data *before* thinning, since a few thousand sighting rows in three million
#'   would not survive it, and are drawn as outlined markers so they read on top
#'   of the track rather than as more of it.
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
  what <- match.arg(what)
  check_ggplot2()
  stopifnot(is.data.frame(dat))
  require_columns(dat, c("LATITUDE", "LONGITUDE"))
  dat <- filter_days(dat, dates, years, months)

  # The one view that cannot fail for want of a column: everything is one
  # group, so there is nothing to look up and nothing to colour by.
  if (what == "positions") {
    dat$.positions <- "position"
  }

  # `unit` and `grey` are what the subtitle says in words. "8,175 occupations
  # drawn; 5,787 on none" is only readable to someone who already knows what an
  # occupation is and what having none means, which is nobody looking at the
  # figure to find out.
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
  if (!spec$col %in% names(dat)) {
    rlang::abort(paste0(
      "The `", what, "` view needs a `", spec$col, "` column, which this data ",
      "does not have yet. ", stage_hint(spec$col)
    ))
  }

  # Resolved once, softly: a failed fetch loses the land, not the plot.
  coastline <- resolve_coastline_soft(coastline)

  # Taken before thinning, deliberately. Sightings are the rare rows - a few
  # thousand in three million - and keeping every 65th record would throw away
  # 64 of every 65 of them. The effort layer is what thinning is for.
  sight <- if (isFALSE(sightings)) NULL else survey_sightings(dat, sightings)

  n_before <- nrow(dat)
  dat <- thin_records(dat, max_points)

  grouped <- what %in% c("occupations", "tracks")
  dat$.grp <- as.character(dat[[spec$col]])

  # A view that is not an identifier - effort, platform, LEGSTAGE - has few
  # enough levels to always name, and naming them is the whole point.
  cap <- capped_groups(dat$.grp, if (grouped) max_legend else Inf)
  named <- cap$named
  n_groups <- cap$n
  dat$.col <- cap$col

  # A record belonging to no occupation - the transit out, the ferry between
  # lines - is not an occupation of its own. Joining those with a path draws a
  # survey line where none was flown, so they are shown as grey points and
  # left unconnected.
  loose <- if (grouped) is.na(dat[[spec$col]]) else rep(FALSE, nrow(dat))
  drawn <- dat[!loose, , drop = FALSE]

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
    # "positions" is one group, and giving it the first palette colour makes a
    # map of bright orange effort that looks like it means something. It does
    # not: neutral grey is the honest colour for "this is simply where the
    # aircraft was", and it lets an overlaid sighting be the thing you see.
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
                                      sum(loose), named, sight)
    ) +
    ggplot2::theme_minimal()

  if (grouped) {
    p <- p + ggplot2::geom_path(ggplot2::aes(group = .data$.grp),
                                linewidth = 0.3, na.rm = TRUE)
  }
  # Not for "positions": `guides()` overrides the scale, so adding one here
  # would put back the single-entry legend the scale just suppressed.
  if (what != "positions") {
    p <- p + legend_guide(nlevels(dat$.col))
  }

  # No legend where the colour carries no meaning: one recycled palette over
  # 8,175 occupations says only "neighbours differ".
  if (grouped && !named) {
    p <- p + ggplot2::guides(colour = "none")
  }

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

  facet_by <- resolve_facet(dat, facet_by)
  if (!is.null(facet_by)) {
    p <- p + ggplot2::facet_wrap(stats::as.formula(paste("~", facet_by)))
  }
  p
}

# Two lines: what the colours mean, then how much data is on the map.
#
# The old one line read "8175 occupations drawn, colours recycled; 43,453
# records, 5,787 on none (grey)", which requires you to already know what an
# occupation is and what having none of one means. If the figure cannot say it,
# the figure is not saying it.
plot_survey_subtitle <- function(dat, spec, grouped, n_before, n_loose = 0L,
                                 named = TRUE, sight = NULL) {
  shown <- nrow(dat) + n_loose
  big <- fmt_count

  what_colours <- if (grouped) {
    n <- length(unique(dat$.grp))
    paste0(
      big(n), " ", tolower(spec$lab), "s - ", spec$unit, ". ",
      if (named) {
        "Each has its own colour."
      } else {
        "Too many to name, so colours repeat: what to look for is that "
      },
      if (!named) "neighbouring lines differ." else ""
    )
  } else NULL

  how_much <- paste0(
    big(shown), " records",
    if (shown < n_before) {
      paste0(" of ", big(n_before), " (every ",
             ceiling(n_before / shown), "th)")
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

# Every nth rather than a random sample: a track drawn from random points is a
# cloud, and the shape is the thing being checked.
thin_records <- function(dat, max_points) {
  if (!is.finite(max_points) || nrow(dat) <= max_points) {
    return(dat)
  }
  dat[seq(1L, nrow(dat), by = ceiling(nrow(dat) / max_points)), , drop = FALSE]
}

# Facet by day where that is readable, and not otherwise.
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

# What to do about a missing column.
#
# These used to name the single function that adds each column, which was true
# and was bad advice: the steps are order-dependent, and every one of them is a
# step of `prepare_aerial()` for that reason. Told to run
# `narwcr::classify_platform()` and filter, someone does it before
# `make_leg_id()` — the message gave no reason not to — which makes two
# occupations of one line adjacent so they merge, and the ferry between them
# becomes survey effort. Measured at 224.5 km where 4.4 km was right.
#
# So each hint names the one call that gets the order right, and then says
# where in that order this particular column appears — because which column is
# missing is what tells you how far the data actually got.
stage_hint <- function(col) {
  prep <- "Run `prepare_aerial()`, which does these steps in the order they have to happen."
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
      "It comes from the survey file. `prepare_aerial()` completes a partial ",
      "one with `narwcr::fill_legstage()`, but it cannot invent a column that ",
      "was never recorded."
    ),
    LEGTYPE = "It comes from the survey file; every NARWC extract has one.",
    ""
  )
}
