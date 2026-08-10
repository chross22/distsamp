#' Perpendicular distance from a declination angle
#'
#' Converts a declination angle and an aircraft altitude into the perpendicular
#' (right-angle) distance from the track-line to a sighting.
#'
#' @section The geometry:
#' `ANGLEL` and `ANGLER` are, per handbook 8.A.2, "the declination angles, in
#' degrees, below the horizon of a sighting (to the left or right, respectively)
#' **when it is perpendicular to the track-line**". Because the angle is taken at
#' the moment the sighting is abeam, the aircraft, the point on the sea surface
#' directly below it, and the animal form a right triangle in the vertical plane
#' perpendicular to the track. The perpendicular distance is therefore
#'
#' \deqn{x = h / \tan(\theta)}
#'
#' for altitude \eqn{h} and declination \eqn{\theta}. An angle of 90 degrees is
#' straight down and gives a distance of zero; as the angle approaches the
#' horizon the distance grows without bound.
#'
#' These replaced `STRIP` in 2022. Handbook 8.A.2 gives the reason: survey
#' altitudes had to rise once offshore wind turbines were in place, and the fixed
#' distance intervals `STRIP` encodes shift with altitude, whereas an angle
#' carries the altitude dependence explicitly.
#'
#' @section Units:
#' `ALT` is in metres (8.A.1), so distances are returned in metres by default.
#' Note that segment effort in this package is in **kilometres** — if you pass
#' both to `Distance::ds()` you must either use `units = "km"` here or supply
#' `convert_units`. Getting this wrong scales density estimates by 1000.
#'
#' @param angle Declination angle below the horizon, in degrees. Values outside
#'   `(0, 90]` cannot describe a sighting below the horizon and return `NA`.
#' @param altitude Aircraft altitude in metres, typically the `ALT` column.
#'   Non-positive or missing altitudes return `NA`.
#' @param units `"m"` (default) or `"km"`.
#'
#' @return A numeric vector of perpendicular distances.
#'
#' @references
#' Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database: A
#' Guide for Users and Contributors, Version 8*, section 8.A.2. NARWC Reference
#' Document 2023-01.
#'
#' Buckland, S.T., Anderson, D.R., Burnham, K.P., Laake, J.L., Borchers, D.L.
#' and Thomas, L. (2001) *Introduction to Distance Sampling.* Oxford University
#' Press.
#'
#' @examples
#' # Straight down
#' perp_distance(90, altitude = 229)
#'
#' # 45 degrees below the horizon: distance equals altitude
#' perp_distance(45, altitude = 229)
#'
#' # Shallow angles put the animal a long way off the track
#' perp_distance(c(60, 30, 10), altitude = 229)
#'
#' perp_distance(30, altitude = 229, units = "km")
#'
#' @seealso [sighting_distances()] to apply this across a survey data frame.
#' @export
perp_distance <- function(angle, altitude, units = c("m", "km")) {
  units <- match.arg(units)

  angle <- as.numeric(angle)
  altitude <- as.numeric(altitude)
  n <- max(length(angle), length(altitude))
  angle <- rep_len(angle, n)
  altitude <- rep_len(altitude, n)

  out <- rep(NA_real_, n)

  usable <- !is.na(angle) & !is.na(altitude) &
    angle > 0 & angle <= 90 & altitude > 0
  out[usable] <- altitude[usable] / tan(angle[usable] * pi / 180)

  # tan(90 degrees) is not exactly infinite in floating point, so pin the
  # straight-down case to an exact zero.
  out[usable & angle == 90] <- 0

  if (units == "km") out <- out / 1000
  out
}


#' Perpendicular distances for a survey data frame
#'
#' Computes the perpendicular distance to each sighting from the `ANGLEL` and
#' `ANGLER` declination angles and the aircraft altitude, and records which side
#' of the track-line the sighting was on.
#'
#' A sighting is on one side of the track, so exactly one of `ANGLEL` and
#' `ANGLER` should be populated on a given record. Records with both populated
#' are ambiguous: they get `NA` distance and a `side` of `"both"`, and are
#' reported by [validate_narwc()].
#'
#' Handbook 8.A.31 restricts right-angle distance measurements to on-effort
#' sightings during census lines. By default this function honours that, leaving
#' distances `NA` elsewhere — some teams record angles during transits and
#' circling for practice, and those must not enter a detection function.
#'
#' @param dat A data frame of NARWC survey data with `ANGLEL`, `ANGLER`, and
#'   `ALT`. Data without any angle column is returned unchanged apart from the
#'   new columns, which will be all `NA`.
#' @param units `"m"` (default) or `"km"`; see [perp_distance()].
#' @param on_effort_only Restrict distances to records that are on effort, on a
#'   census line, and at `LEGSTAGE == 2`. Default `TRUE`.
#'
#' @return `dat` with two columns added:
#'   \describe{
#'     \item{`distance`}{Perpendicular distance from the track-line.}
#'     \item{`side`}{`"left"`, `"right"`, `"both"`, or `NA`.}
#'   }
#'
#' @seealso [perp_distance()], [segment_survey()]
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' dat <- sighting_distances(read_narwc(path))
#' subset(dat, !is.na(distance), c("SPECCODE", "ANGLEL", "ANGLER", "side", "distance"))
#'
#' @export
sighting_distances <- function(dat, units = c("m", "km"),
                               on_effort_only = TRUE) {
  units <- match.arg(units)

  if (is_empty_df(dat)) {
    dat$distance <- numeric(0)
    dat$side <- character(0)
    return(dat)
  }

  n <- nrow(dat)
  left <- if ("ANGLEL" %in% names(dat)) as.numeric(dat$ANGLEL) else rep(NA_real_, n)
  right <- if ("ANGLER" %in% names(dat)) as.numeric(dat$ANGLER) else rep(NA_real_, n)
  alt <- if ("ALT" %in% names(dat)) as.numeric(dat$ALT) else rep(NA_real_, n)

  has_l <- !is.na(left)
  has_r <- !is.na(right)

  side <- rep(NA_character_, n)
  side[has_l & !has_r] <- "left"
  side[has_r & !has_l] <- "right"
  side[has_l & has_r] <- "both"

  angle <- rep(NA_real_, n)
  angle[has_l & !has_r] <- left[has_l & !has_r]
  angle[has_r & !has_l] <- right[has_r & !has_l]

  distance <- perp_distance(angle, alt, units = units)

  if (on_effort_only) {
    distance[!on_effort_census_rows(dat)] <- NA_real_
  }

  dat$distance <- distance
  dat$side <- side
  dat
}
