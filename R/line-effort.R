#' Effort per survey line
#'
#' Summarises on-effort distance by survey line rather than by continuous track.
#'
#' @section Why this is not `segs$tracks`:
#' A **track** is a continuous run of effort: it ends wherever effort breaks,
#' which may be mid-line, and it says nothing about which line was being flown.
#' A **line** is a design element: the transect the survey set out to fly, named
#' by `LEGNO`. Segmentation works on tracks, so `segs$tracks` cannot say how much
#' of line 7 was covered, or whether it had to be flown again.
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
#' effort, and an off-effort record carries zero `pt2pt.effort`, so dropping it
#' removes no distance. But a track shorter than `min_track_km`, or a segment
#' shorter than `min_segment_km`, is discarded *with* its on-effort distance,
#' which was really flown. A line made of such a track then reports too little
#' effort, or disappears from the summary.
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
  # Get point-level records (from a segmentation, its `points` table).
  combine <- match.arg(combine)
  dat <- line_effort_points(x)

  # Empty input gives an empty table of the requested shape.
  if (is_empty_df(dat)) {
    if (combine == "line") {
      return(tibble::tibble(
        LEGNO = character(0), effort_km = numeric(0),
        n_occupations = integer(0), n_days = integer(0)
      ))
    }
    return(tibble::tibble(
      DATE = as.Date(character(0)), FILEID = character(0), LEGNO = character(0),
      LEGNO3 = character(0), occupation = integer(0),
      effort_km = numeric(0), n_records = integer(0)
    ))
  }

  # Line-occupation IDs are created if missing.
  require_columns(dat, c("pt2pt.effort", "LEGNO"))
  if (!"LEGNO3" %in% names(dat)) {
    dat <- make_leg_id(dat)
  }

  # A line occupation is one attempt at one line on one day; `keys` are the
  # columns that identify it. Records on no line (LEGNO missing) are dropped.
  keys <- intersect(c("DATE", "FILEID", "LEGNO", "LEGNO3"), names(dat))
  dat <- dat[!is.na(dat$LEGNO), , drop = FALSE]
  if (is_empty_df(dat)) {
    return(line_effort(dat[0, , drop = FALSE], combine = combine))
  }

  # Sum on-effort distance (km) and count records per occupation, in key
  # order.
  # Occupations are put in the order they were flown: by day and file, then
  # by first EVENTNO. Sorting LEGNO3 as text would put "_10" before "_9".
  ev <- if ("EVENTNO" %in% names(dat)) as.numeric(dat$EVENTNO) else seq_len(nrow(dat))
  dat$.first_ev <- ev
  per <- dplyr::summarise(
    dplyr::group_by(dat, dplyr::across(dplyr::all_of(keys))),
    effort_km = sum(.data$pt2pt.effort, na.rm = TRUE),
    n_records = dplyr::n(),
    .first_ev = min(.data$.first_ev, na.rm = TRUE),
    .groups = "drop"
  )
  order_by <- c(intersect(c("DATE", "FILEID"), names(per)), ".first_ev")
  per <- dplyr::arrange(per, dplyr::across(dplyr::all_of(order_by)))
  per$.first_ev <- NULL

  # Number the attempts at each line in key order: 1 for the first, 2 for
  # the first re-flight, and so on.
  per <- dplyr::mutate(
    dplyr::group_by(per, .data$LEGNO),
    occupation = seq_len(dplyr::n())
  )
  per <- dplyr::ungroup(per)

  if (combine == "occupation") {
    return(per)
  }

  # Per line: total effort over all attempts, the number of attempts, and the
  # number of distinct days flown.
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
#' Counts lines that took more than one attempt, and reports the rate in two
#' ways because the two numbers differ.
#'
#' @section Two rates, deliberately both:
#' Suppose ten occupations covered eight lines, because two lines were flown
#' twice.
#'
#' * `prop_lines_reflown` is 2/8 = 0.25: a quarter of the lines needed a second
#'   attempt. This answers "what fraction of lines were re-flown".
#' * `prop_occupations_repeat` is 2/10 = 0.20: a fifth of the flying repeated a
#'   line already attempted. This is the one that bears on effort.
#'
#' The original processing scripts computed the second and labelled it the
#' first (`ds_data_dmr.R:229`). Both are reported here, each named for what it
#' measures.
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
  # Per-occupation effort; an empty survey gives zero counts and NA rates.
  per <- line_effort(x, combine = "occupation")

  if (is_empty_df(per)) {
    return(tibble::tibble(
      n_lines = 0L, n_occupations = 0L, n_lines_reflown = 0L,
      prop_lines_reflown = NA_real_, prop_occupations_repeat = NA_real_,
      effort_km = 0, effort_km_repeat = 0
    ))
  }

  # Count lines, occupations, and lines with more than one occupation.
  by_line <- line_effort(x, combine = "line")
  n_lines <- nrow(by_line)
  n_occ <- nrow(per)
  reflown <- sum(by_line$n_occupations > 1L)

  tibble::tibble(
    n_lines = n_lines,
    n_occupations = n_occ,
    n_lines_reflown = as.integer(reflown),
    prop_lines_reflown = reflown / n_lines,
    # Occupations beyond the first of each line, over all occupations.
    prop_occupations_repeat = (n_occ - n_lines) / n_occ,
    # Total effort, and the part flown on repeat occupations.
    effort_km = sum(per$effort_km),
    effort_km_repeat = sum(per$effort_km[per$occupation > 1L])
  )
}

# Point-level records from either accepted input. A data frame is returned
# as is. A segmentation returns its `points` table, which holds only records
# that reached a segment, with a message saying so.
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
