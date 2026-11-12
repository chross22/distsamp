#' Split survey lines at breaks in effort
#'
#' Assigns `new_trackno`, an identifier for each stretch of *continuous* effort.
#' These stretches, not the designated survey lines, are what get chopped into
#' segments.
#'
#' @section The rule:
#' Walking through a survey day's records in order, a new track begins when
#' either
#'
#' * the line occupation changes (`LEGNO3` differs from the previous record), or
#' * effort breaks — this record and the next are both off effort.
#'
#' Otherwise the record continues the current track. A *single* off-effort
#' record between two on-effort ones is not a break, so one bad fix does not
#' split the track. A sustained break (circling for photographs, transiting
#' around fog) does. This is the rule from the original
#' `create_new_track_nos()`.
#'
#' A sustained break gives three tracks: the effort before it, the break
#' itself, and the effort after. The middle track carries no effort and is
#' dropped by [track_effort()]. Each on-effort track therefore holds only
#' on-effort records.
#'
#' A circling excursion logged as a single record (as in handbook Figure 2,
#' event 13) does **not** split the track, because the record after it is back
#' on effort. Computer-logged surveys record many positions while circling, so
#' in modern data the track does split.
#'
#' Track numbers restart at 1 on each survey date.
#'
#' @param dat A data frame with `LEGNO3` (see [make_leg_id()]), `OnOff.Effort`
#'   (see [flag_effort()]), and `DATE`, in survey order.
#'
#' @return `dat` with a character `new_trackno` column added.
#'
#' @references
#' Becker, E.A., Forney, K.A., Ferguson, M.C., Foley, D.G., Smith, R.C., Barlow,
#' J. and Redfern, J.V. (2010) Comparing California Current cetacean-habitat
#' models developed using in situ and remotely sensed sea surface temperature
#' data. *Marine Ecology Progress Series* 413:163-183.
#' \doi{10.3354/meps08696}
#'
#' @seealso [make_leg_id()], [flag_effort()], [segment_survey()]
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' dat <- split_tracks(flag_effort(make_leg_id(read_narwc(path))))
#' table(dat$DATE, dat$new_trackno)
#'
#' @export
split_tracks <- function(dat) {
  require_columns(dat, c("LEGNO3", "OnOff.Effort", "DATE"))

  # Empty input: add an empty column and return.
  if (is_empty_df(dat)) {
    dat$new_trackno <- character(0)
    return(dat)
  }

  # Number tracks within each survey date, so numbering restarts each day.
  dat <- dplyr::group_by(dat, .data$DATE)
  dat <- dplyr::mutate(dat, new_trackno = track_index(.data$LEGNO3, .data$OnOff.Effort))
  dplyr::ungroup(dat)
}

# Track numbers for one survey day's records, in survey order. `leg` is
# LEGNO3; `on_effort` is OnOff.Effort. Returns "1", "2", ... as character.
track_index <- function(leg, on_effort) {
  n <- length(leg)
  if (n == 0L) return(character(0))
  if (n == 1L) return("1")

  # Mark each change of line occupation. NA (off any line) is compared as the
  # string "NA", so a run of NA records is one occupation, not a change at
  # every record.
  key <- ifelse(is.na(leg), "NA", as.character(leg))
  new_leg <- c(FALSE, key[-1] != key[-n])

  # Effort state, 1 or 0; a missing flag counts as off effort.
  on <- ifelse(is.na(on_effort), 0L, as.integer(on_effort))

  # Smooth isolated records: a single off-effort record with on-effort records
  # on both sides is treated as on effort here, so one bad fix does not split
  # the track. The record keeps OnOff.Effort = 0 and pt2pt.effort = 0. The
  # first and last records count their missing neighbour as on effort.
  prev_on <- c(1L, on[-n])
  next_on <- c(on[-1], 1L)
  isolated <- on == 0L & prev_on == 1L & next_on == 1L
  state <- on
  state[isolated] <- 1L

  # Start a new track at every change of (smoothed) effort state and at every
  # change of line occupation. Number tracks from 1.
  changed <- c(FALSE, state[-1] != state[-n])

  as.character(cumsum(new_leg | changed) + 1L)
}


#' Summarise effort by continuous track
#'
#' Totals the point-to-point effort on each continuous track and drops tracks
#' too short to be worth segmenting.
#'
#' @param dat A data frame with `DATE`, `new_trackno`, `pt2pt.effort`, and
#'   `TIME`.
#' @param min_track_km Tracks with this much effort or less are dropped.
#'   Default `1`.
#'
#' @return A tibble with one row per track: `DATE`, `new_trackno`,
#'   `track_effort` (km), and `start_time` (the earliest `TIME` on the track,
#'   used to keep tracks in survey order).
#'
#' @references
#' Becker, E.A., Forney, K.A., Ferguson, M.C., Foley, D.G., Smith, R.C., Barlow,
#' J. and Redfern, J.V. (2010) Comparing California Current cetacean-habitat
#' models developed using in situ and remotely sensed sea surface temperature
#' data. *Marine Ecology Progress Series* 413:163-183.
#' \doi{10.3354/meps08696}
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' dat <- point_to_point_effort(
#'   split_tracks(flag_effort(make_leg_id(read_narwc(path))))
#' )
#' track_effort(dat)
#'
#' @export
track_effort <- function(dat, min_track_km = 1) {
  require_columns(dat, c("DATE", "new_trackno", "pt2pt.effort", "TIME"))

  # Total effort (km) and earliest TIME per track. A track with no valid TIME
  # gives -Inf from min(); set it to NA.
  out <- dplyr::summarise(
    dplyr::group_by(dat, .data$DATE, .data$new_trackno),
    track_effort = sum(.data$pt2pt.effort, na.rm = TRUE),
    start_time = suppressWarnings(min(as.numeric(.data$TIME), na.rm = TRUE)),
    .groups = "drop"
  )
  out$start_time[!is.finite(out$start_time)] <- NA_real_

  # Drop short tracks. Off-effort tracks have zero effort and go here too.
  # Then sort tracks in survey order.
  out <- dplyr::filter(out, .data$track_effort > min_track_km)
  dplyr::arrange(out, .data$DATE, .data$start_time, .data$new_trackno)
}
