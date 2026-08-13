#' Several views of a survey, side by side
#'
#' Draws more than one [plot_survey()] view on one figure, so the stages can be
#' compared without holding two windows next to each other. Optionally writes
#' one figure per survey day.
#'
#' @section Why side by side:
#' The views answer each other. `"raw"` shows every position the file holds;
#' `"platform"` shows which of them this package will keep; `"effort"` shows
#' which of *those* count; `"occupations"` shows how they were divided into
#' lines. A record that vanishes between two panels is the question worth
#' asking, and it is far easier to see in one figure than in four.
#'
#' @section One figure per day:
#' `by_day = TRUE` writes a figure for each survey day into `dir`. A season on
#' one map is a smear — 24,795 line occupations over 187 days tell you nothing
#' about any of them — while a day is a handful of lines you can actually
#' check. The files are named `survey-<date>.png` and the paths are returned,
#' so a `targets` pipeline can track them.
#'
#' @param dat A survey data frame at any stage.
#' @param views Which views to draw. Defaults to the ones the data supports, in
#'   pipeline order: a view whose column is absent is skipped rather than
#'   erroring, because the point is to see how far the data has got.
#' @param by_day Write one figure per survey day instead of returning one
#'   figure for everything? Default `FALSE`.
#' @param dir Directory to write into when `by_day = TRUE`.
#' @param ncol Panels per row. `NULL` (default) picks 2 for up to four views
#'   and 3 beyond.
#' @param width,height,dpi Passed to [ggplot2::ggsave()] when writing files.
#' @param ... Passed to [plot_survey()] — `coastline`, `max_points`,
#'   `max_legend`.
#'
#' @return A `patchwork` object, or invisibly the file paths when
#'   `by_day = TRUE`.
#'
#' @seealso [plot_survey()] for one view, [diagnose_pipeline()] for the same
#'   questions as numbers.
#'
#' @examplesIf requireNamespace("patchwork", quietly = TRUE) && requireNamespace("ggplot2", quietly = TRUE)
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' air <- prepare_aerial(narwcr::read_narwc(path, quiet = TRUE), quiet = TRUE)
#' plot_survey_panel(air, c("raw", "occupations"), coastline = FALSE)
#'
#' @export
plot_survey_panel <- function(dat, views = NULL, by_day = FALSE, dir = ".",
                              ncol = NULL, width = 14, height = 9, dpi = 120,
                              ...) {
  check_ggplot2()
  if (!requireNamespace("patchwork", quietly = TRUE)) {
    rlang::abort(paste0(
      "`plot_survey_panel()` needs the `patchwork` package. Install it, or ",
      "call `plot_survey()` for one view at a time."
    ))
  }
  stopifnot(is.data.frame(dat))
  views <- views %||% available_views(dat)
  if (!length(views)) {
    rlang::abort("None of the views can be drawn from this data.")
  }

  if (!by_day) {
    return(panel_of(dat, views, ncol, ...))
  }

  require_columns(dat, "DATE")
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

panel_of <- function(dat, views, ncol, ...) {
  panels <- lapply(views, function(v) {
    p <- plot_survey(dat, v, ...)
    # Titles carry the view; a subtitle per panel repeats the record count
    # four times over, and the axes repeat on every panel for no gain.
    p + ggplot2::labs(subtitle = NULL, x = NULL, y = NULL) +
      ggplot2::theme(legend.key.size = ggplot2::unit(0.4, "cm"),
                     legend.text = ggplot2::element_text(size = 7),
                     legend.title = ggplot2::element_text(size = 8),
                     axis.text = ggplot2::element_text(size = 6),
                     plot.title = ggplot2::element_text(size = 10),
                     strip.text = ggplot2::element_text(size = 7))
  })
  ncol <- ncol %||% if (length(views) <= 4L) 2L else 3L

  patchwork::wrap_plots(panels, ncol = ncol) +
    patchwork::plot_annotation(
      title = panel_title(dat),
      theme = ggplot2::theme(plot.title = ggplot2::element_text(size = 12))
    )
}

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

# Views in pipeline order, keeping the ones this frame can answer. Skipping is
# the point: which views are available says how far the data has got.
available_views <- function(dat) {
  needs <- c(raw = "LEGTYPE", platform = "PLATFORM_KIND",
             legstage = "LEGSTAGE", occupations = "LEGNO3",
             effort = "OnOff.Effort", tracks = "new_trackno")
  names(needs)[vapply(needs, function(x) x %in% names(dat), logical(1))]
}
