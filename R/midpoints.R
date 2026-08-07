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
#' @examples
#' # Halfway along a degree of latitude
#' gc_interpolate(43, -69, 44, -69, 0.5)
#'
#' @export
gc_interpolate <- function(lat1, lon1, lat2, lon2, fraction) {
  n <- max(length(lat1), length(lon1), length(lat2), length(lon2), length(fraction))
  lat1 <- rep_len(lat1, n); lon1 <- rep_len(lon1, n)
  lat2 <- rep_len(lat2, n); lon2 <- rep_len(lon2, n)
  f <- rep_len(fraction, n)

  d2r <- pi / 180
  phi1 <- lat1 * d2r; lam1 <- lon1 * d2r
  phi2 <- lat2 * d2r; lam2 <- lon2 * d2r

  cos_d <- sin(phi1) * sin(phi2) + cos(phi1) * cos(phi2) * cos(lam2 - lam1)
  cos_d <- pmin(1, pmax(-1, cos_d))
  d <- acos(cos_d)

  # Coincident (or effectively coincident) endpoints: no arc to walk along.
  degenerate <- is.na(d) | d < 1e-12
  sin_d <- sin(d)
  a <- ifelse(degenerate, 1 - f, sin((1 - f) * d) / sin_d)
  b <- ifelse(degenerate, f,     sin(f * d) / sin_d)

  x <- a * cos(phi1) * cos(lam1) + b * cos(phi2) * cos(lam2)
  y <- a * cos(phi1) * sin(lam1) + b * cos(phi2) * sin(lam2)
  z <- a * sin(phi1) + b * sin(phi2)

  lat <- atan2(z, sqrt(x^2 + y^2)) / d2r
  lon <- atan2(y, x) / d2r

  # Where the endpoints coincide, hand back the start position unchanged
  # rather than an atan2 artefact.
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
#' @seealso [cut_segments()], [gc_interpolate()]
#' @export
segment_midpoints <- function(chopped) {
  require_columns(
    chopped,
    c("DATE", "new_trackno", "seg_id", "seg_eff", "LATITUDE", "LONGITUDE",
      "pt2pt.effort")
  )

  if (is_empty_df(chopped)) {
    return(tibble::tibble(
      seg_id = character(0), mid_lat = numeric(0), mid_lon = numeric(0)
    ))
  }

  # The last record of a segment measures its effort to the first record of the
  # *next* segment, so the bracketing position may lie outside the segment.
  # Take the successor within the track, which spans segment boundaries.
  dat <- dplyr::mutate(
    dplyr::group_by(chopped, .data$DATE, .data$new_trackno),
    .next_lat = dplyr::lead(.data$LATITUDE),
    .next_lon = dplyr::lead(.data$LONGITUDE)
  )
  dat <- dplyr::ungroup(dat)

  parts <- split(dat, factor(dat$seg_id, levels = unique(dat$seg_id)))
  mids <- lapply(parts, midpoint_one_segment)
  dplyr::bind_rows(mids)
}

midpoint_one_segment <- function(seg) {
  eff <- seg$pt2pt.effort
  eff[is.na(eff)] <- 0
  cum <- cumsum(eff)
  total <- cum[length(cum)]

  if (total <= 0) {
    # No distance to walk: fall back to the first recorded position.
    return(tibble::tibble(
      seg_id = seg$seg_id[1],
      mid_lat = seg$LATITUDE[1],
      mid_lon = seg$LONGITUDE[1]
    ))
  }

  half <- total / 2
  j <- which(cum >= half)[1]
  before <- if (j == 1L) 0 else cum[j - 1L]
  step <- eff[j]
  f <- if (step > 0) (half - before) / step else 0

  pos <- gc_interpolate(
    seg$LATITUDE[j], seg$LONGITUDE[j],
    seg$.next_lat[j], seg$.next_lon[j],
    f
  )

  tibble::tibble(
    seg_id = seg$seg_id[1],
    mid_lat = pos$lat,
    mid_lon = pos$lon
  )
}
