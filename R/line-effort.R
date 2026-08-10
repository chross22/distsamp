#' Effort per survey line
#'
#' Summarises on-effort distance by survey line rather than by continuous track.
#'
#' @section Why this is not `segs$tracks`:
#' A **track** is a continuous run of effort: it ends wherever effort breaks,
#' which may be mid-line, and it says nothing about which line was being flown.
#' A **line** is a design element — the transect the survey set out to fly, named
#' by `LEGNO`. Segmentation works on tracks, so `segs$tracks` cannot answer "how
#' much of line 7 did we actually cover, and did we have to go back for it".
#'
#' @section Occupations and lines:
#' A line can be started, abandoned for weather, and flown again hours later.
#' Each attempt is an **occupation**, identified by `LEGNO3` from
#' [make_leg_id()]; the **line** is `LEGNO` itself.
#'
#' `combine = "occupation"` (the default) gives one row per attempt.
#' `combine = "line"` gives one row per line with its attempts summed, which is
#' the total coverage that line received.
#'
#' @section What it sums:
#' `pt2pt.effort`, which [point_to_point_effort()] attributes to the first
#' record of each on-effort pair and sets to zero across breaks. Summing it over
#' an occupation therefore gives distance actually flown on effort, not the
#' distance between the line's endpoints.
#'
#' @section Give it point-level data, not a segmentation:
#' Passing a `distsamp_segments` uses its `points` table, which holds only the
#' records that reached a segment.
#'
#' Usually that costs nothing: the records segmentation leaves out are off
#' effort, and an off-effort record carries zero `pt2pt.effort` — so dropping it
#' removes no distance. But a track shorter than `min_track_km`, or a segment
#' shorter than `min_segment_km`, is discarded *with* its on-effort distance, and
#' that effort was really flown. A line made up of such a track then reports less
#' effort than the survey gave it, or disappears from the summary entirely.
#'
#' So pass the point-level data after [flag_effort()] and
#' [point_to_point_effort()] when the total has to be right. A message says which
#' you gave it.
#'
#' @param x Point-level survey data with `pt2pt.effort`, `LEGNO`, and ideally
#'   `LEGNO3`, or a `distsamp_segments` object.
#' @param combine `"occupation"` (default) or `"line"`.
#'
#' @return A tibble. Per occupation: `DATE`, `FILEID`, `LEGNO`, `LEGNO3`,
#'   `occupation`, `effort_km`, `n_records`. Per line: `LEGNO`, `effort_km`,
#'   `n_occupations`, `n_days`.
#'
#' @references
#' Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database: A
#' Guide for Users and Contributors, Version 8*, section 8.A.19 (`LEGNO`). NARWC
#' Reference Document 2023-01.
#'
#' @seealso [reflight_summary()], [track_effort()], [make_leg_id()]
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' dat <- point_to_point_effort(flag_effort(make_leg_id(read_narwc(path))))
#'
#' # One row per attempt at a line
#' line_effort(dat)
#'
#' # One row per line, attempts combined
#' line_effort(dat, combine = "line")
#'
#' @export
line_effort <- function(x, combine = c("occupation", "line")) {
  combine <- match.arg(combine)
  dat <- line_effort_points(x)

  if (is_empty_df(dat)) {
    return(tibble::tibble(
      DATE = as.Date(character(0)), FILEID = character(0), LEGNO = character(0),
      LEGNO3 = character(0), occupation = integer(0),
      effort_km = numeric(0), n_records = integer(0)
    ))
  }

  require_columns(dat, c("pt2pt.effort", "LEGNO"))
  if (!"LEGNO3" %in% names(dat)) {
    dat <- make_leg_id(dat)
  }

  # A line occupation is one attempt at one line on one day.
  keys <- intersect(c("DATE", "FILEID", "LEGNO", "LEGNO3"), names(dat))
  dat <- dat[!is.na(dat$LEGNO), , drop = FALSE]
  if (is_empty_df(dat)) {
    return(line_effort(dat[0, , drop = FALSE], combine = combine))
  }

  per <- dplyr::summarise(
    dplyr::group_by(dat, dplyr::across(dplyr::all_of(keys))),
    effort_km = sum(.data$pt2pt.effort, na.rm = TRUE),
    n_records = dplyr::n(),
    .groups = "drop"
  )
  per <- dplyr::arrange(per, dplyr::across(dplyr::all_of(keys)))

  # Which attempt at this line this is: 1 for the first, 2 for a re-flight.
  per <- dplyr::mutate(
    dplyr::group_by(per, .data$LEGNO),
    occupation = seq_len(dplyr::n())
  )
  per <- dplyr::ungroup(per)

  if (combine == "occupation") {
    return(per)
  }

  out <- dplyr::summarise(
    dplyr::group_by(per, .data$LEGNO),
    effort_km = sum(.data$effort_km),
    n_occupations = dplyr::n(),
    n_days = if ("DATE" %in% names(per)) {
      length(unique(.data$DATE))
    } else {
      NA_integer_
    },
    .groups = "drop"
  )
  dplyr::arrange(out, .data$LEGNO)
}


#' How much of the survey was re-flown
#'
#' Counts lines that took more than one attempt, and reports the rate two ways
#' because they are different numbers and the distinction matters.
#'
#' @section Two rates, deliberately both:
#' Suppose ten occupations covered eight lines, because two lines were flown
#' twice.
#'
#' * `prop_lines_reflown` is 2/8 = 0.25 — a quarter of the lines needed a second
#'   attempt. This is what "what fraction of lines were re-flown" asks.
#' * `prop_occupations_repeat` is 2/10 = 0.20 — a fifth of the flying was a
#'   repeat of something already attempted. This is the one that bears on
#'   effort.
#'
#' The scripts this package was rewritten from computed the second and labelled
#' it the first (`ds_data_dmr.R:229`, carrying the comment "ask dan about this").
#' Both are reported here, named for what they measure, so neither can stand in
#' for the other by accident.
#'
#' @param x Point-level survey data, or a `distsamp_segments`; as
#'   [line_effort()].
#'
#' @return A one-row tibble: `n_lines`, `n_occupations`, `n_lines_reflown`,
#'   `prop_lines_reflown`, `prop_occupations_repeat`, `effort_km`,
#'   `effort_km_repeat`.
#'
#' @seealso [line_effort()]
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' dat <- point_to_point_effort(flag_effort(make_leg_id(read_narwc(path))))
#' reflight_summary(dat)
#'
#' @export
reflight_summary <- function(x) {
  per <- line_effort(x, combine = "occupation")

  if (is_empty_df(per)) {
    return(tibble::tibble(
      n_lines = 0L, n_occupations = 0L, n_lines_reflown = 0L,
      prop_lines_reflown = NA_real_, prop_occupations_repeat = NA_real_,
      effort_km = 0, effort_km_repeat = 0
    ))
  }

  by_line <- line_effort(x, combine = "line")
  n_lines <- nrow(by_line)
  n_occ <- nrow(per)
  reflown <- sum(by_line$n_occupations > 1L)

  tibble::tibble(
    n_lines = n_lines,
    n_occupations = n_occ,
    n_lines_reflown = as.integer(reflown),
    prop_lines_reflown = reflown / n_lines,
    # Occupations beyond the first, over all occupations.
    prop_occupations_repeat = (n_occ - n_lines) / n_occ,
    effort_km = sum(per$effort_km),
    effort_km_repeat = sum(per$effort_km[per$occupation > 1L])
  )
}

# Point-level records, from either accepted input. A segmentation only carries
# the records that made it into a segment, so say so when that has cost effort.
line_effort_points <- function(x) {
  if (!inherits(x, "distsamp_segments")) {
    return(x)
  }
  pts <- x$points
  rlang::inform(paste0(
    "Summarising a `distsamp_segments`, so this covers the ", nrow(pts),
    " records that reached a segment. Off-effort records carry no distance and ",
    "cost nothing here, but a track dropped for `min_track_km` takes its ",
    "on-effort distance with it - pass the point-level data if the total has ",
    "to be right."
  ))
  pts
}
