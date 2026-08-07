#' Flag records made while circling
#'
#' Marks the records where the aircraft had left the census track to circle a
#' sighting.
#'
#' Two signals are used, either of which is sufficient:
#'
#' * `LEGTYPE == 4`, the line-transect "other (circling)" code (handbook
#'   8.A.21); and
#' * any record between a `LEGSTAGE == 3` (break off line to circle) and the
#'   following `LEGSTAGE == 4` (resume line) within the same survey line
#'   occupation (handbook 8.A.20).
#'
#' The second signal matters because a survey may log positions during circling
#' without changing `LEGTYPE`, and because the break-off and resume records
#' themselves stay at `LEGTYPE == 2`.
#'
#' @param dat A data frame of NARWC survey data in survey order, with `LEGTYPE`
#'   and ideally `LEGSTAGE` and `LEGNO3`.
#'
#' @return `dat` with an integer `CIRCLE` column: `1` while circling, `0`
#'   otherwise.
#'
#' @references
#' Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database: A
#' Guide for Users and Contributors, Version 8*, sections 8.A.20 and 8.A.21. NARWC Reference Document
#' 2023-01.
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' dat <- flag_circling(make_leg_id(read_narwc(path)))
#' sum(dat$CIRCLE)
#'
#' @export
flag_circling <- function(dat) {
  require_columns(dat, "LEGTYPE")

  if (is_empty_df(dat)) {
    dat$CIRCLE <- integer(0)
    return(dat)
  }

  circ <- !is.na(dat$LEGTYPE) & dat$LEGTYPE == 4

  if ("LEGSTAGE" %in% names(dat)) {
    group <- if ("LEGNO3" %in% names(dat)) {
      paste(dat$DATE %||% "", dat$LEGNO3)
    } else {
      rep("all", nrow(dat))
    }
    stage <- dat$LEGSTAGE
    open <- logical(nrow(dat))
    state <- FALSE
    prev <- NA_character_
    for (i in seq_len(nrow(dat))) {
      if (!identical(group[i], prev)) {
        state <- FALSE
        prev <- group[i]
      }
      if (!is.na(stage[i]) && stage[i] == 3) {
        state <- TRUE
        open[i] <- FALSE # the break-off record itself is still on the line
        next
      }
      if (!is.na(stage[i]) && stage[i] == 4) {
        state <- FALSE
        open[i] <- FALSE # the resume record is back on the line
        next
      }
      open[i] <- state
    }
    circ <- circ | open
  }

  dat$CIRCLE <- as.integer(circ)
  dat
}

`%||%` <- function(x, y) if (is.null(x)) y else x


#' Attach sightings made while circling to the segment they came from
#'
#' A group sighted from the census track is often circled for photographs, and
#' the position recorded for it is the one taken during circling, off effort.
#' Dropping those records loses detections that genuinely arose from on-effort
#' search. This function attributes them back to the segment that was in
#' progress when the aircraft broke off.
#'
#' @section What the protocol says:
#' Handbook 4.2 (event 11) sets out the CETAP rule: counted with the original
#' on-effort group are any further individuals *of the same species* seen while
#' circling that can reasonably be called associated, plus one further
#' unassociated group of the same species. Groups of *other* species, not
#' originally seen from the track-line, are new off-effort sightings and do not
#' belong to the segment.
#'
#' `mode = "same_species"` implements that rule: a circling sighting is attached
#' only when the preceding segment already holds an on-effort sighting of the
#' same species. It is the default.
#'
#' The original processing code instead hard-coded right whales, attaching every
#' circling right whale and discarding circling sightings of everything else.
#'
#' @param chopped Point-level segmented data from [cut_segments()].
#' @param dat The full point-level data, including the off-effort records that
#'   segmentation left out, with `CIRCLE` from [flag_circling()].
#' @param mode `"same_species"` (default), `"all"`, or `"none"`; see Details.
#'
#' @return `chopped` with the attachable circling records appended, carrying the
#'   `seg_id`, `seg_no`, and `seg_eff` of the segment they were attached to and
#'   `case = "circling"`. Their `pt2pt.effort` is set to `0` so that attaching
#'   them cannot change any segment's length.
#'
#' @references
#' Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database: A
#' Guide for Users and Contributors, Version 8*, section 4.2 (event 11). NARWC
#' Reference Document 2023-01.
#'
#' CETAP (1982) *A Characterization of Marine Mammals and Turtles in the Mid- and
#' North-Atlantic Areas of the U.S. Outer Continental Shelf, Final Report.*
#' Cetacean and Turtle Assessment Program, University of Rhode Island. Bureau of
#' Land Management, Washington, DC.
#'
#' @seealso [flag_circling()], [segment_sightings()]
#' @export
attach_circling_sightings <- function(chopped, dat,
                                      mode = c("same_species", "all", "none")) {
  mode <- match.arg(mode)
  if (mode == "none" || is_empty_df(chopped)) {
    return(chopped)
  }
  if (!all(c("CIRCLE", "SPECCODE", "EVENTNO", "DATE") %in% names(dat))) {
    return(chopped)
  }

  cand <- dat[
    !is.na(dat$CIRCLE) & dat$CIRCLE == 1 &
      !is.na(dat$SPECCODE) & dat$SPECCODE != "", ,
    drop = FALSE
  ]
  if (!nrow(cand)) {
    return(chopped)
  }

  # Where each segment ended, so a circling sighting can be traced back to the
  # segment that was in progress immediately before the break-off.
  bounds <- dplyr::summarise(
    dplyr::group_by(chopped, .data$DATE, .data$seg_id),
    seg_no = dplyr::first(.data$seg_no),
    seg_eff = dplyr::first(.data$seg_eff),
    new_trackno = dplyr::first(.data$new_trackno),
    first_event = min(.data$EVENTNO, na.rm = TRUE),
    last_event = max(.data$EVENTNO, na.rm = TRUE),
    .groups = "drop"
  )

  keep <- vector("list", nrow(cand))
  for (i in seq_len(nrow(cand))) {
    same_day <- bounds[bounds$DATE == cand$DATE[i], , drop = FALSE]
    before <- same_day[same_day$last_event <= cand$EVENTNO[i], , drop = FALSE]
    if (!nrow(before)) next
    target <- before[which.max(before$last_event), , drop = FALSE]

    if (mode == "same_species") {
      in_seg <- chopped$seg_id == target$seg_id &
        !is.na(chopped$SPECCODE) & chopped$SPECCODE == cand$SPECCODE[i]
      if (!any(in_seg)) next
    }

    row <- cand[i, , drop = FALSE]
    row$seg_id <- target$seg_id
    row$seg_no <- target$seg_no
    row$seg_eff <- target$seg_eff
    row$new_trackno <- target$new_trackno
    row$events <- paste(target$first_event, target$last_event, sep = "_")
    row$case <- "circling"
    # Attaching a record must not change how long the segment is.
    row$pt2pt.effort <- 0
    keep[[i]] <- row
  }

  extra <- dplyr::bind_rows(keep)
  if (is_empty_df(extra)) {
    return(chopped)
  }

  out <- dplyr::bind_rows(chopped, extra[, intersect(names(chopped), names(extra))])
  dplyr::arrange(out, .data$DATE, .data$seg_id, .data$EVENTNO)
}
