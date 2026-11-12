#' Several views of a survey, side by side
#'
#' Draws several [plot_survey()] views on one figure, so the stages can be
#' compared directly. Optionally writes one figure per survey day.
#'
#' @section Why side by side:
#' The views answer each other. `"raw"` shows every position the file holds;
#' `"platform"` shows which of them this package will keep; `"effort"` shows
#' which of *those* count; `"occupations"` shows how they were divided into
#' lines. A record that vanishes between two panels is worth investigating, and
#' is easier to see in one figure than in four.
#'
#' @section One figure per day:
#' `by_day = TRUE` writes a figure for each survey day into `dir`. A season on
#' one map is unreadable, while one day is a handful of lines that can be
#' checked. The files are named `survey-<date>.png` and the paths are returned,
#' so a `targets` pipeline can track them.
#'
#' @param dat A survey data frame at any stage.
#' @param views Which views to draw. Defaults to the ones the data supports, in
#'   pipeline order. A view whose column is absent is skipped rather than
#'   raising an error, so the panel shows how far the data has got.
#' @param by_day Write one figure per survey day instead of returning one
#'   figure for everything? Default `FALSE`.
#' @param dir Directory the per-day figures are written to. Default
#'   `"survey-panels"`, created if needed. It is not the working directory
#'   because `by_day = TRUE` over a season writes one file per survey day.
#' @param ncol Panels per row. Defaults to 2 for up to four views and 3
#'   otherwise.
#' @param width,height,dpi Size of the written figures, in inches and dots per
#'   inch. Only used when `by_day = TRUE`; otherwise the figure is returned and
#'   the caller decides.
#' @param dates,years,months Narrow which survey days are drawn, as in
#'   [filter_days()]. They narrow together rather than adding up: `years =
#'   2019` with `months = 8` is August 2019, not all of 2019 and every August.
#' @param ... Passed to [plot_survey()] for every view: `coastline`,
#'   `sightings`, `max_points` and the rest. An `sf` coastline fetched once and
#'   passed in is much faster than `coastline = TRUE`, which refetches Natural
#'   Earth for every panel of every day.
#'
#' @seealso [plot_survey()], which draws one view.
#'
#' @export
plot_survey_panel <- function(dat, views = NULL, by_day = FALSE,
                              dir = "survey-panels",
                              ncol = NULL, width = 14, height = 9, dpi = 120,
                              dates = NULL, years = NULL, months = NULL,
                              ...) {
  # Check that the plotting packages are installed.
  check_ggplot2()
  if (!requireNamespace("patchwork", quietly = TRUE)) {
    rlang::abort(paste0(
      "`plot_survey_panel()` needs the `patchwork` package. Install it, or ",
      "call `plot_survey()` for one view at a time."
    ))
  }
  stopifnot(is.data.frame(dat))

  # Filter the days once, here. The same subset feeds every view, and with
  # `by_day = TRUE` it decides which days get a figure.
  dat <- filter_days(dat, dates, years, months)

  # Default views: those the data has columns for.
  views <- views %||% available_views(dat)
  if (!length(views)) {
    rlang::abort("None of the views can be drawn from this data.")
  }

  # One figure for everything, returned.
  if (!by_day) {
    return(panel_of(dat, views, ncol, ...))
  }

  require_columns(dat, "DATE")

  # One figure per day: write each to <dir>/survey-<date>.png, then report
  # where the files went. Records with no DATE are not drawn.
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  days <- sort(unique(stats::na.omit(dat$DATE)))

  paths <- vapply(days, function(d) {
    one <- dat[!is.na(dat$DATE) & dat$DATE == d, , drop = FALSE]
    f <- file.path(dir, paste0("survey-", format(d, "%Y-%m-%d"), ".png"))
    ggplot2::ggsave(f, panel_of(one, views, ncol, ...),
                    width = width, height = height, dpi = dpi)
    f
  }, character(1))

  rlang::inform(paste0("Wrote ", length(paths), " figures to ",
                       normalizePath(dir)))
  invisible(unname(paths))
}

# One patchwork figure of `views` for `dat`, with a figure-level title.
panel_of <- function(dat, views, ncol, ...) {
  panels <- lapply(views, function(v) {
    p <- plot_survey(dat, v, ...)
    # Drop subtitles and axis labels, which would repeat on every panel, and
    # shrink the text to fit.
    p + ggplot2::labs(subtitle = NULL, x = NULL, y = NULL) +
      ggplot2::theme(legend.key.size = ggplot2::unit(0.4, "cm"),
                     legend.text = ggplot2::element_text(size = 7),
                     legend.title = ggplot2::element_text(size = 8),
                     axis.text = ggplot2::element_text(size = 6),
                     plot.title = ggplot2::element_text(size = 10),
                     strip.text = ggplot2::element_text(size = 7))
  })
  # Two columns for up to four views, three beyond.
  ncol <- ncol %||% if (length(views) <= 4L) 2L else 3L

  patchwork::wrap_plots(panels, ncol = ncol) +
    patchwork::plot_annotation(
      title = panel_title(dat),
      theme = ggplot2::theme(plot.title = ggplot2::element_text(size = 12))
    )
}

# Figure title: the date (or the range and number of days) and the record
# count.
panel_title <- function(dat) {
  days <- if ("DATE" %in% names(dat)) unique(stats::na.omit(dat$DATE)) else NULL
  when <- if (length(days) == 1L) {
    format(days, "%Y-%m-%d")
  } else if (length(days) > 1L) {
    paste0(length(days), " survey days, ", format(min(days)), " to ",
           format(max(days)))
  } else {
    "survey"
  }
  paste0(when, " - ", format(nrow(dat), big.mark = ","), " records")
}

# Views whose column is present, in pipeline order. Which views are available
# shows how far the data has got.
#
# "positions" is excluded: it always works, and would add an uncoloured copy
# of the other maps to every figure. It can be requested by name.
available_views <- function(dat) {
  needs <- c(raw = "LEGTYPE", platform = "PLATFORM_KIND",
             legstage = "LEGSTAGE", occupations = "LEGNO3",
             effort = "OnOff.Effort", tracks = "new_trackno")
  names(needs)[vapply(needs, function(x) x %in% names(dat), logical(1))]
}
