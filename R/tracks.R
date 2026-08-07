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
#' record between two on-effort ones is not treated as a break, so a momentary
#' excursion logged as one point does not fragment the track, while a sustained
#' break — circling for photographs, transiting around fog — does. This is the
#' rule from the original `create_new_track_nos()`.
#'
#' A sustained break yields three tracks, not two: the effort before it, the
#' break itself, and the effort after. The middle one carries no effort and is
#' dropped by [track_effort()]. The original incremented the track number on
#' *every* record of a break, so a five-record circling excursion produced four
#' spurious tracks and left the first two off-effort records attached to the
#' track that resumed afterwards. Grouping the break into one track leaves each
#' on-effort track containing only on-effort records.
#'
#' One consequence is worth knowing: a circling excursion logged as a single
#' record (as in handbook Figure 2, event 13) does **not** split the track,
#' because the record after it is back on effort. Computer-logged surveys record
#' many positions while circling, so in modern data the break is seen and the
#' track does split.
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

  if (is_empty_df(dat)) {
    dat$new_trackno <- character(0)
    return(dat)
  }

  dat <- dplyr::group_by(dat, .data$DATE)
  dat <- dplyr::mutate(dat, new_trackno = track_index(.data$LEGNO3, .data$OnOff.Effort))
  dplyr::ungroup(dat)
}

# Vectorised equivalent of the original row-walking loop.
track_index <- function(leg, on_effort) {
  n <- length(leg)
  if (n == 0L) return(character(0))
  if (n == 1L) return("1")

  key <- ifelse(is.na(leg), "NA", as.character(leg))
  new_leg <- c(FALSE, key[-1] != key[-n])

  on <- ifelse(is.na(on_effort), 0L, as.integer(on_effort))

  # A single off-effort record between two on-effort ones is not a break in
  # effort, so smooth it out before looking for state changes.
  prev_on <- c(1L, on[-n])
  next_on <- c(on[-1], 1L)
  isolated <- on == 0L & prev_on == 1L & next_on == 1L
  state <- on
  state[isolated] <- 1L

  # A new track begins at every change of effort state and at every change of
  # line occupation.
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
#' @param min_track_km Tracks with less than this much effort are dropped.
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

  out <- dplyr::summarise(
    dplyr::group_by(dat, .data$DATE, .data$new_trackno),
    track_effort = sum(.data$pt2pt.effort, na.rm = TRUE),
    start_time = suppressWarnings(min(as.numeric(.data$TIME), na.rm = TRUE)),
    .groups = "drop"
  )
  out$start_time[!is.finite(out$start_time)] <- NA_real_

  out <- dplyr::filter(out, .data$track_effort > min_track_km)
  dplyr::arrange(out, .data$DATE, .data$start_time, .data$new_trackno)
}
