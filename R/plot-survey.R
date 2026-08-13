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
#'   `"platform"`, or `"legstage"`.
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
#' @export
plot_survey <- function(dat, what = c("effort", "occupations", "tracks",
                                      "platform", "legstage"),
                        coastline = TRUE, max_points = 50000,
                        max_legend = 12, facet_by = NULL) {
  what <- match.arg(what)
  check_ggplot2()
  stopifnot(is.data.frame(dat))
  require_columns(dat, c("LATITUDE", "LONGITUDE"))

  spec <- switch(
    what,
    effort      = list(col = "OnOff.Effort", lab = "On effort",
                       title = "Effort"),
    occupations = list(col = "LEGNO3", lab = "Occupation",
                       title = "Line occupations"),
    tracks      = list(col = "new_trackno", lab = "Track",
                       title = "Continuous-effort tracks"),
    platform    = list(col = "PLATFORM_KIND", lab = "Platform",
                       title = "Platform"),
    legstage    = list(col = "LEGSTAGE", lab = "LEGSTAGE",
                       title = "Line stage")
  )
  if (!spec$col %in% names(dat)) {
    rlang::abort(paste0(
      "The `", what, "` view needs a `", spec$col, "` column, which this data ",
      "does not have yet. ", stage_hint(spec$col)
    ))
  }

  # Resolved once, softly: a failed fetch loses the land, not the plot.
  coastline <- resolve_coastline_soft(coastline)

  n_before <- nrow(dat)
  dat <- thin_records(dat, max_points)

  grouped <- what %in% c("occupations", "tracks")
  dat$.grp <- as.character(dat[[spec$col]])

  # Colour by the identifier itself where there are few enough to tell apart,
  # so the legend says which line is which. Beyond that a legend is a wall of
  # labels and the colours cannot be distinguished anyway, so a small palette
  # is recycled: what has to be visible then is only that neighbours differ.
  n_groups <- length(unique(stats::na.omit(dat$.grp)))
  named <- !grouped || n_groups <= max_legend
  dat$.col <- if (named) {
    factor(dat$.grp, levels = unique(stats::na.omit(dat$.grp)))
  } else {
    factor(match(dat$.grp, unique(dat$.grp)) %% 8L)
  }

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
    map_coord(coastline, dat$LONGITUDE, dat$LATITUDE) +
    ggplot2::labs(
      x = "Longitude", y = "Latitude",
      colour = spec$lab,
      title = spec$title,
      subtitle = plot_survey_subtitle(drawn, spec, grouped, n_before,
                                      sum(loose), named)
    ) +
    ggplot2::theme_minimal()

  if (grouped) {
    p <- p + ggplot2::geom_path(ggplot2::aes(group = .data$.grp),
                                linewidth = 0.3, na.rm = TRUE)
    if (!named) p <- p + ggplot2::guides(colour = "none")
  }
  p <- p + ggplot2::guides(
    colour = ggplot2::guide_legend(override.aes = list(size = 3))
  )

  facet_by <- resolve_facet(dat, facet_by)
  if (!is.null(facet_by)) {
    p <- p + ggplot2::facet_wrap(stats::as.formula(paste("~", facet_by)))
  }
  p
}

plot_survey_subtitle <- function(dat, spec, grouped, n_before, n_loose = 0L,
                                 named = TRUE) {
  n <- if (grouped) length(unique(dat$.grp)) else NA_integer_
  shown <- nrow(dat) + n_loose
  paste0(
    if (grouped) {
      paste0(n, " ", tolower(spec$lab), "s drawn",
             if (!named) ", colours recycled" else "", "; ")
    } else "",
    format(nrow(dat), big.mark = ","), " records",
    if (n_loose) paste0(", ", format(n_loose, big.mark = ","),
                        " on none (grey)") else "",
    if (shown < n_before) {
      paste0(" (thinned from ", format(n_before, big.mark = ","),
             "; every ", ceiling(n_before / shown), "th)")
    } else ""
  )
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

stage_hint <- function(col) {
  switch(
    col,
    OnOff.Effort = "It is added by `narwcr::flag_effort()`.",
    LEGNO3 = "It is added by `narwcr::make_leg_id()`.",
    new_trackno = "It is added by `split_tracks()`, after `flag_effort()`.",
    PLATFORM_KIND = paste0(
      "Assign it yourself: `dat$PLATFORM_KIND <- ",
      "narwcr::classify_platform(dat)`."
    ),
    LEGSTAGE = "It comes from the survey file, and `narwcr::fill_legstage()` completes it.",
    ""
  )
}
