#' Interpolate a position along a great circle
#'
#' Spherical linear interpolation between two positions: the point a given
#' fraction of the way along the great-circle arc joining them.
#'
#' @param lat1,lon1 Start positions, in decimal degrees.
#' @param lat2,lon2 End positions, in decimal degrees.
#' @param fraction Fraction of the way from the start to the end, in \[0, 1\].
#'
#' @return A tibble with columns `lat` and `lon`, in decimal degrees.
#'
#' @references
#' Shoemake, K. (1985) Animating rotation with quaternion curves.
#' *ACM SIGGRAPH Computer Graphics* 19(3):245-254, for spherical linear
#' interpolation. \doi{10.1145/325165.325242}
#'
#' @examples
#' # Halfway along a degree of latitude
#' gc_interpolate(43, -69, 44, -69, 0.5)
#'
#' @export
gc_interpolate <- function(lat1, lon1, lat2, lon2, fraction) {
  # Recycle all inputs to a common length.
  n <- max(length(lat1), length(lon1), length(lat2), length(lon2), length(fraction))
  lat1 <- rep_len(lat1, n); lon1 <- rep_len(lon1, n)
  lat2 <- rep_len(lat2, n); lon2 <- rep_len(lon2, n)
  f <- rep_len(fraction, n)

  # Degrees to radians.
  d2r <- pi / 180
  phi1 <- lat1 * d2r; lam1 <- lon1 * d2r
  phi2 <- lat2 * d2r; lam2 <- lon2 * d2r

  # Angular distance d between the endpoints (spherical law of cosines).
  # cos_d is clamped to [-1, 1] so rounding cannot make acos() return NaN.
  cos_d <- sin(phi1) * sin(phi2) + cos(phi1) * cos(phi2) * cos(lam2 - lam1)
  cos_d <- pmin(1, pmax(-1, cos_d))
  d <- acos(cos_d)

  # Weights a and b on the two endpoints (Shoemake's slerp). When the
  # endpoints coincide (or d is NA) there is no arc, and linear weights are
  # used instead, which avoids dividing by sin(0).
  degenerate <- is.na(d) | d < 1e-12
  sin_d <- sin(d)
  a <- ifelse(degenerate, 1 - f, sin((1 - f) * d) / sin_d)
  b <- ifelse(degenerate, f,     sin(f * d) / sin_d)

  # Weighted sum of the endpoints as 3-D unit vectors, then back to degrees.
  x <- a * cos(phi1) * cos(lam1) + b * cos(phi2) * cos(lam2)
  y <- a * cos(phi1) * sin(lam1) + b * cos(phi2) * sin(lam2)
  z <- a * sin(phi1) + b * sin(phi2)

  lat <- atan2(z, sqrt(x^2 + y^2)) / d2r
  lon <- atan2(y, x) / d2r

  # Where the end position is missing, return the start position instead of
  # NA. `both_na` is TRUE when either end coordinate is missing.
  both_na <- is.na(lat2) | is.na(lon2)
  lat[both_na] <- lat1[both_na]
  lon[both_na] <- lon1[both_na]

  tibble::tibble(lat = lat, lon = lon)
}


#' Locate the along-track midpoint of each segment
#'
#' Finds the position half of a segment's realised effort along the segment,
#' interpolating along the great circle between the two survey records that
#' bracket the half-way distance.
#'
#' @section Why along-track, not centroid:
#' A segment is a piece of trackline, and the location that represents it for a
#' covariate lookup should be a point on that line. Averaging the coordinates of
#' the records in the segment gives a centroid that is pulled towards wherever
#' records happen to be dense, and on a curved or dog-legged track can fall off
#' the line entirely. Walking half the segment's effort puts the midpoint on the
#' track by construction, and weights it by distance rather than by record count.
#'
#' The segment mid-point is the location at which habitat covariates are
#' conventionally sampled in this family of models. Becker et al. (2019) describe
#' covariates "derived based on the segment's geographical mid-point", with sea
#' surface temperature and depth standard deviations taken over a 3 x 3-pixel box
#' around it. That is the intended use of these coordinates.
#'
#' @param chopped Point-level segmented data from [cut_segments()], in survey
#'   order, with `DATE`, `new_trackno`, `seg_id`, `seg_eff`, `LATITUDE`,
#'   `LONGITUDE`, and `pt2pt.effort`.
#'
#' @return A tibble with one row per segment: `seg_id`, `mid_lat`, `mid_lon`.
#'
#' @references
#' Becker, E.A., Forney, K.A., Redfern, J.V., Barlow, J., Jacox, M.G., Roberts,
#' J.J. and Palacios, D.M. (2019) Predicting cetacean abundance and distribution
#' in a changing climate. *Diversity and Distributions* 25:626-643.
#' \doi{10.1111/ddi.12867}
#'
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
#' chopped <- cut_segments(
#'   plan_segments(track_effort(dat), seg_length = 5, seed = 1), dat, seed = 1
#' )
#'
#' # The position half of each segment's realised effort along it - not the
#' # mean of its coordinates, which would sit off the track on a turn.
#' mids <- segment_midpoints(chopped)
#' head(mids)
#'
#' # Every segment gets exactly one midpoint
#' nrow(mids) == length(unique(chopped$seg_id))
#'
#' @seealso [cut_segments()], [gc_interpolate()]
#' @export
segment_midpoints <- function(chopped) {
  require_columns(
    chopped,
    c("DATE", "new_trackno", "seg_id", "seg_eff", "LATITUDE", "LONGITUDE",
      "pt2pt.effort")
  )

  # No segments: empty result.
  if (is_empty_df(chopped)) {
    return(tibble::tibble(
      seg_id = character(0), mid_lat = numeric(0), mid_lon = numeric(0)
    ))
  }

  # 1. Put records in survey order (DATE, track number, EVENTNO) and give each
  #    record the position of the next record in its track. The next record
  #    is taken from the track, not the segment: a segment's last record
  #    measures its effort to the first record of the next segment. The track
  #    number is sorted as a number, so track "10" follows "9". Without
  #    EVENTNO, the incoming row order is used.
  ev <- if ("EVENTNO" %in% names(chopped)) as.numeric(chopped$EVENTNO) else
    seq_len(nrow(chopped))
  ord <- order(chopped$DATE, as.numeric(chopped$new_trackno), ev)
  dat <- dplyr::mutate(
    dplyr::group_by(chopped[ord, , drop = FALSE], .data$DATE, .data$new_trackno),
    .next_lat = dplyr::lead(.data$LATITUDE),
    .next_lon = dplyr::lead(.data$LONGITUDE)
  )
  dat <- dplyr::ungroup(dat)

  # 2. For each segment, the cumulative effort at each record (`cum`) and half
  #    the segment's total effort (`half`). Done for all segments at once;
  #    `seg` keeps segments in their order of first appearance.
  seg <- factor(dat$seg_id, levels = unique(dat$seg_id))
  eff <- dat$pt2pt.effort
  eff[is.na(eff)] <- 0
  cum <- stats::ave(eff, seg, FUN = cumsum)
  half <- stats::ave(eff, seg, FUN = sum) / 2

  # 3. Find `j`, one row per segment: the first record whose cumulative effort
  #    reaches half. The half-way point lies on the step from that record to
  #    the next. A segment with no effort uses its first record instead.
  #    `walk` marks segments with effort to walk along.
  first <- !duplicated(seg)
  crosses <- half > 0 & cum >= half
  j <- ifelse(half[first] > 0, match(levels(seg), seg[crosses]), NA_integer_)
  j <- which(crosses)[j]
  j[is.na(j)] <- which(first)[is.na(j)]
  walk <- half[j] > 0

  # 4. Interpolate on the great circle from record j to the next record. `f`
  #    is the fraction of record j's step needed to reach half: the effort
  #    still needed when the step starts, over the step's length.
  f <- ifelse(walk & eff[j] > 0, (half[j] - (cum[j] - eff[j])) / eff[j], 0)
  pos <- gc_interpolate(
    dat$LATITUDE[j], dat$LONGITUDE[j],
    ifelse(walk, dat$.next_lat[j], dat$LATITUDE[j]),
    ifelse(walk, dat$.next_lon[j], dat$LONGITUDE[j]),
    f
  )

  # Segments with no effort take their first position.
  pos$lat[!walk] <- dat$LATITUDE[j][!walk]
  pos$lon[!walk] <- dat$LONGITUDE[j][!walk]
  tibble::tibble(seg_id = levels(seg), mid_lat = pos$lat, mid_lon = pos$lon)
}
