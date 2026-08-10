#' Plan how many segments each track carries
#'
#' Decides, for every continuous track, how many segments to cut and what target
#' length each should have. This is the planning half of the segmentation; the
#' cutting half is [cut_segments()].
#'
#' @section The method:
#' Adapted from Elizabeth Becker's `segchopr` code, which implements the
#' segmenting approach of Becker et al. (2010): continuous portions of survey
#' effort are divided into segments of approximately equal length, sightings are
#' assigned to the segment they fall in, and habitat covariates are taken at each
#' segment's mid-point. It sits within the segmented line-transect framework of
#' Hedley and Buckland (2004) and Miller et al. (2013).
#'
#' For a track of length `L` and a target segment length `s`:
#'
#' * `L` shorter than `s` gives a single segment of length `L`.
#' * Otherwise `floor(L / s)` whole segments fit, leaving a remainder
#'   `rem = L - floor(L / s) * s`.
#' * If `rem` is at least the tolerance `seg_tol_frac * s`, it is large enough
#'   to stand on its own and becomes an extra segment.
#' * If `rem` is smaller than the tolerance, it is absorbed instead: one segment
#'   is stretched to `s + rem`.
#'
#' Either way the leftover is assigned to a **randomly chosen** segment rather
#' than always the last one, so that the short (or long) segment is not
#' systematically at the end of every track. The target lengths always sum to
#' `L`.
#'
#' @section Reproducibility:
#' The random choice makes segmentation non-deterministic. Pass a `seed` to fix
#' it. The RNG state of the calling session is left unchanged either way.
#'
#' @param tracks A tibble from [track_effort()].
#' @param seg_length Target segment length in km.
#' @param seg_tol_frac Tolerance as a fraction of `seg_length`, controlling
#'   whether a remainder becomes its own segment or is absorbed. Default `0.5`,
#'   so segments run between `0.5 * seg_length` and `1.5 * seg_length`.
#' @param seed Integer RNG seed, or `NULL` for unseeded.
#'
#' @return A tibble with one row per planned segment: `DATE`, `new_trackno`,
#'   `start_time`, `track_effort`, `seg_no` (position within the track), and
#'   `tgtdist` (target length in km).
#'
#' @section On the published record:
#' Becker et al. (2010) is the citation the literature uses for this approach —
#' later papers describe their samples as "divided into approximate 5-km segments
#' of continuous survey effort using the approach described by Becker et al.
#' (2010)" (Becker et al. 2019). What the published methods state is the target
#' length and the use of continuous effort; the specific handling of the leftover
#' distance at the end of a track — the tolerance test, and assigning the
#' remainder to a randomly chosen segment rather than the last one — is a
#' property of the `segchopr` implementation and does not appear to be described
#' in print. It is documented here instead, and is controlled by `seg_tol_frac`.
#'
#' @references
#' Becker, E.A., Forney, K.A., Ferguson, M.C., Foley, D.G., Smith, R.C., Barlow,
#' J. and Redfern, J.V. (2010) Comparing California Current cetacean-habitat
#' models developed using in situ and remotely sensed sea surface temperature
#' data. *Marine Ecology Progress Series* 413:163-183.
#' \doi{10.3354/meps08696}
#'
#' Becker, E.A., Forney, K.A., Redfern, J.V., Barlow, J., Jacox, M.G., Roberts,
#' J.J. and Palacios, D.M. (2019) Predicting cetacean abundance and distribution
#' in a changing climate. *Diversity and Distributions* 25:626-643.
#' \doi{10.1111/ddi.12867}
#'
#' Hedley, S.L. and Buckland, S.T. (2004) Spatial models for line transect
#' sampling. *Journal of Agricultural, Biological, and Environmental Statistics*
#' 9:181-199. \doi{10.1198/1085711043578}
#'
#' Miller, D.L., Burt, M.L., Rexstad, E.A. and Thomas, L. (2013) Spatial models
#' for distance sampling data: recent developments and future directions.
#' *Methods in Ecology and Evolution* 4:1001-1010.
#' \doi{10.1111/2041-210X.12105}
#'
#' @seealso [cut_segments()], [segment_survey()]
#'
#' @examples
#' tracks <- tibble::tibble(
#'   DATE = as.Date("2024-04-01"), new_trackno = "1",
#'   track_effort = 23, start_time = 120000
#' )
#' plan_segments(tracks, seg_length = 5, seed = 1)
#'
#' @export
plan_segments <- function(tracks, seg_length, seg_tol_frac = 0.5, seed = NULL) {
  require_columns(tracks, c("DATE", "new_trackno", "track_effort", "start_time"))
  stopifnot(is.numeric(seg_length), length(seg_length) == 1L, seg_length > 0)

  if (is_empty_df(tracks)) {
    return(tibble::tibble(
      DATE = tracks$DATE, new_trackno = tracks$new_trackno,
      start_time = numeric(0), track_effort = numeric(0),
      seg_no = integer(0), tgtdist = numeric(0)
    ))
  }

  seg_tol <- seg_tol_frac * seg_length

  with_optional_seed(seed, {
    plans <- lapply(seq_len(nrow(tracks)), function(i) {
      total <- tracks$track_effort[i]
      tgt <- plan_one_track(total, seg_length, seg_tol)
      tibble::tibble(
        DATE = tracks$DATE[i],
        new_trackno = tracks$new_trackno[i],
        start_time = tracks$start_time[i],
        track_effort = total,
        seg_no = seq_along(tgt),
        tgtdist = tgt
      )
    })
    dplyr::bind_rows(plans)
  })
}

# Target lengths for one track. Returns a numeric vector summing to `total`.
plan_one_track <- function(total, seg_length, seg_tol) {
  if (!is.finite(total) || total <= 0) {
    return(numeric(0))
  }
  if (total < seg_length) {
    return(total)
  }

  n_whole <- floor(total / seg_length)
  leftover <- total - n_whole * seg_length

  if (leftover >= seg_tol || n_whole == 0) {
    # Big enough to be a segment in its own right.
    n_seg <- n_whole + 1L
    extra <- leftover
  } else {
    # Too short to stand alone; stretch one segment to swallow it.
    n_seg <- n_whole
    extra <- seg_length + leftover
  }

  tgt <- rep(seg_length, n_seg)
  # sample.int, not floor(runif(1, 1, n_seg)): the latter can never return
  # n_seg, so the leftover could never land on the final segment.
  tgt[sample.int(n_seg, 1L)] <- extra
  tgt
}


#' Cut tracks into segments
#'
#' Walks each continuous track record by record, accumulating point-to-point
#' effort until the target length for the current segment is reached, then
#' starts the next segment. This is the cutting half of the segmentation;
#' [plan_segments()] supplies the targets.
#'
#' @section Where the cut falls:
#' Segments are cut at record boundaries — a survey record is never split — so a
#' segment rarely lands exactly on its target. For each segment the function
#' finds the first record at which cumulative effort reaches the target, then
#' flips a coin: heads, that record is included and the segment runs slightly
#' long; tails, it is excluded and the segment runs slightly short. Over many
#' segments the two errors cancel instead of biasing every segment long.
#'
#' The final segment of each track takes all remaining records, so no effort is
#' lost off the end of a track.
#'
#' @param plan A tibble from [plan_segments()].
#' @param dat The point-level survey data, with `DATE`, `new_trackno`,
#'   `pt2pt.effort`, and `EVENTNO`.
#' @param min_segment_km Segments shorter than this are dropped from the result.
#'   Default `1`.
#' @param seed Integer RNG seed for the coin flips, or `NULL`.
#'
#' @return The point-level data, restricted to records that fell inside a kept
#'   segment, with columns added:
#'   \describe{
#'     \item{`seg_no`}{Position of the segment within its track.}
#'     \item{`seg_id`}{Unique segment identifier, `DATE_track_segno`.}
#'     \item{`seg_eff`}{Realised segment length in km, repeated on each record.}
#'     \item{`events`}{`EVENTNO` range spanned, as `"first_last"`.}
#'     \item{`case`}{Which rule ended the segment; see Details.}
#'   }
#'
#' @details
#' The `case` column records why each segment ended, preserving the diagnostic
#' labels from the original implementation:
#' \describe{
#'   \item{`case2`}{The first remaining record alone met the target.}
#'   \item{`case3`}{Several records were needed; the coin flip decided whether
#'     to include the record that crossed the target.}
#'   \item{`case4`}{Not enough effort remained to reach the target, so the
#'     segment took what was left.}
#'   \item{`case5`}{Last segment of the track; it absorbed all remaining
#'     records.}
#' }
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
#' dat <- point_to_point_effort(flag_effort(make_leg_id(read_narwc(path))))
#' dat <- split_tracks(dat)
#' plan <- plan_segments(track_effort(dat), seg_length = 5, seed = 1)
#'
#' chopped <- cut_segments(plan, dat, seed = 1)
#'
#' # One row per survey record, now carrying the segment it fell in
#' head(chopped[, c("seg_id", "seg_no", "seg_eff", "EVENTNO")])
#'
#' # Realised effort per segment, against the 5 km target
#' tapply(chopped$pt2pt.effort, chopped$seg_id, sum)
#'
#' @seealso [plan_segments()], [segment_survey()]
#' @export
cut_segments <- function(plan, dat, min_segment_km = 1, seed = NULL) {
  require_columns(plan, c("DATE", "new_trackno", "seg_no", "tgtdist"), what = "plan")
  require_columns(dat, c("DATE", "new_trackno", "pt2pt.effort", "EVENTNO"))

  if (is_empty_df(plan) || is_empty_df(dat)) {
    return(empty_chopped(dat))
  }

  plan_key <- paste(plan$DATE, plan$new_trackno, sep = "\r")
  dat_key <- paste(dat$DATE, dat$new_trackno, sep = "\r")

  pieces <- with_optional_seed(seed, {
    lapply(unique(plan_key), function(k) {
      cut_one_track(
        plan[plan_key == k, , drop = FALSE],
        dat[dat_key == k, , drop = FALSE]
      )
    })
  })

  out <- dplyr::bind_rows(pieces)
  if (is_empty_df(out)) {
    return(empty_chopped(dat))
  }
  dplyr::filter(out, .data$seg_eff > min_segment_km)
}

# Cut a single track. `plan_i` is that track's planned segments in order;
# `dat_i` is its records in survey order.
cut_one_track <- function(plan_i, dat_i) {
  n_rows <- nrow(dat_i)
  n_seg <- nrow(plan_i)
  if (n_rows == 0L || n_seg == 0L) {
    return(NULL)
  }

  plan_i <- plan_i[order(plan_i$seg_no), , drop = FALSE]
  # Cut points measured from the start of the track, not from wherever the
  # previous segment happened to end. Because a cut can only fall on a record
  # boundary, each segment lands a little over or under its target; measuring
  # from the track start stops those errors accumulating down the track and
  # dumping the arrears on the final segment.
  cut_at <- cumsum(plan_i$tgtdist)
  covered <- 0
  pos <- 1L
  pieces <- vector("list", n_seg)

  for (i in seq_len(n_seg)) {
    if (pos > n_rows) break

    idx <- pos:n_rows
    eff <- dat_i$pt2pt.effort[idx]
    eff[is.na(eff)] <- 0
    tgt <- max(cut_at[i] - covered, 0)

    if (i == n_seg) {
      # Last planned segment: take everything that is left, so that no effort
      # falls off the end of the track.
      take <- length(idx)
      case <- "case5"
    } else if (eff[1] >= tgt) {
      take <- 1L
      case <- "case2"
    } else if (sum(eff) <= tgt) {
      take <- length(idx)
      case <- "case4"
    } else {
      k <- which(cumsum(eff) >= tgt)[1]
      # Heads, overshoot; tails, undershoot. Never take zero records.
      if (stats::runif(1) >= 0.5 && k > 1L) {
        k <- k - 1L
      }
      take <- k
      case <- "case3"
    }

    rows <- pos:(pos + take - 1L)
    piece <- dat_i[rows, , drop = FALSE]
    piece$seg_no <- plan_i$seg_no[i]
    piece$seg_id <- paste(
      plan_i$DATE[i], plan_i$new_trackno[i], plan_i$seg_no[i],
      sep = "_"
    )
    piece$seg_eff <- sum(piece$pt2pt.effort, na.rm = TRUE)
    piece$events <- paste(
      min(piece$EVENTNO, na.rm = TRUE), max(piece$EVENTNO, na.rm = TRUE),
      sep = "_"
    )
    piece$case <- case
    pieces[[i]] <- piece

    covered <- covered + piece$seg_eff[1]
    pos <- pos + take
  }

  dplyr::bind_rows(pieces)
}

empty_chopped <- function(dat) {
  out <- dat[0, , drop = FALSE]
  out$seg_no <- integer(0)
  out$seg_id <- character(0)
  out$seg_eff <- numeric(0)
  out$events <- character(0)
  out$case <- character(0)
  out
}
