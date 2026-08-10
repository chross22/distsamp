#' Check survey data against the handbook and against distance sampling
#'
#' [narwcr::validate_narwc()] with this package's checks added to the default,
#' so that `validate_narwc(dat)` reports everything it reported before the
#' reading layer was split into \pkg{narwcr}.
#'
#' @section Why this wrapper exists:
#' The handbook-general checks live in \pkg{narwcr}, and calling its
#' `validate_narwc()` directly runs only those. Silently dropping four checks
#' from a function people already call would be a regression, so this package
#' keeps its own default. To run only the handbook rules, call
#' `narwcr::validate_narwc()`.
#'
#' @param dat A data frame of NARWC survey data, ideally from
#'   [narwcr::read_narwc()].
#' @param checks A named list of check functions. Defaults to the
#'   handbook-general set plus [distsamp_checks()].
#'
#' @inherit narwcr::validate_narwc return
#'
#' @seealso [distsamp_checks()] for what this package adds,
#'   [narwcr::narwc_checks()] for the handbook-general set.
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' issues <- validate_narwc(read_narwc(path, quiet = TRUE))
#' issues[, c("check", "severity", "n")]
#'
#' # The handbook rules on their own
#' narwcr::validate_narwc(read_narwc(path, quiet = TRUE))
#'
#' @export
validate_narwc <- function(dat,
                           checks = c(narwcr::narwc_checks(),
                                      distsamp_checks())) {
  narwcr::validate_narwc(dat, checks = checks)
}


#' Checks that only matter for distance sampling
#'
#' The checks in this package, for use alongside the handbook-general set that
#' [narwcr::narwc_checks()] provides.
#'
#' @section Why these are separate:
#' Everything here is a problem *only if you are computing a right-angle
#' distance*. A declination angle above the horizon and an exact sighting
#' position 200 km from the aircraft that logged it are both perfectly ordinary
#' columns to carry around; they become defects at the point where a detection
#' function is fitted to them. So they live with the package that fits one,
#' rather than in the reader that every analysis shares.
#'
#' \describe{
#'   \item{`exact_position_far_from_event`}{An exact sighting position more than
#'     `r EXACT_POSITION_MAX_KM` km from the event position that recorded it. A
#'     sighting is made from the aircraft, so this is a coordinate problem —
#'     usually a dropped minus sign, or degrees and decimal minutes read as
#'     decimal degrees — rather than a distant animal.}
#'   \item{`angle_out_of_range`}{`ANGLEL` or `ANGLER` outside `(0, 90]`.
#'     Handbook 8.A.2 defines these as declination angles below the horizon, so
#'     a value at or below zero is at or above the horizon and one above 90 is
#'     behind the aircraft. Neither yields a perpendicular distance.}
#'   \item{`angle_both_sides`}{Both `ANGLEL` and `ANGLER` recorded on one
#'     record. A sighting is on one side of the track, so the side is ambiguous
#'     and no distance can be computed.}
#'   \item{`angle_without_altitude`}{A declination angle with no `ALT`. Handbook
#'     8.A.2: the distance calculation must factor in altitude, so an angle
#'     without one is unusable.}
#' }
#'
#' @return A named list of functions, in the shape [narwcr::narwc_checks()]
#'   uses.
#'
#' @references
#' Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database: A
#' Guide for Users and Contributors, Version 8*, section 8.A.2. NARWC Reference
#' Document 2023-01.
#'
#' @seealso [narwcr::validate_narwc()], [narwcr::narwc_checks()]
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' dat <- read_narwc(path, quiet = TRUE)
#'
#' # The handbook rules and the distance-sampling ones together
#' issues <- validate_narwc(dat, checks = c(narwc_checks(), distsamp_checks()))
#' issues[, c("check", "severity", "n")]
#'
#' @export
distsamp_checks <- function() {
  list(
    exact_position_plausible = check_exact_position_plausible,
    declination_angles       = check_declination_angles
  )
}

# A sighting is seen from the aircraft, so it cannot be far from the position
# that logged it. Anything beyond a few km is a coordinate problem, not a whale.
check_exact_position_plausible <- function(dat) {
  needed <- c("S_LAT", "S_LONG", "LATITUDE", "LONGITUDE")
  if (!all(needed %in% names(dat))) {
    return(NULL)
  }

  s_lat <- suppressWarnings(as.numeric(dat$S_LAT))
  s_lon <- suppressWarnings(as.numeric(dat$S_LONG))
  away <- gc_distance(dat$LATITUDE, dat$LONGITUDE, s_lat, s_lon)

  rows <- which(!is.na(away) & away > EXACT_POSITION_MAX_KM)
  if (!length(rows)) {
    return(NULL)
  }

  list(narwcr::narwc_finding(
    "exact_position_far_from_event", "warning", "S_LAT/S_LONG", rows,
    paste0(
      "Exact sighting position more than ", EXACT_POSITION_MAX_KM,
      " km from the event position that recorded it. The usual causes are a ",
      "dropped minus sign on S_LONG and coordinates in degrees and decimal ",
      "minutes rather than decimal degrees."
    )
  ))
}

check_declination_angles <- function(dat) {
  angle_cols <- intersect(c("ANGLEL", "ANGLER"), names(dat))
  if (!length(angle_cols)) {
    return(NULL)
  }

  out <- lapply(angle_cols, function(nm) {
    a <- suppressWarnings(as.numeric(dat[[nm]]))
    rows <- which(!is.na(a) & (a <= 0 | a > 90))
    if (!length(rows)) {
      return(NULL)
    }
    narwcr::narwc_finding(
      "angle_out_of_range", "warning", nm, rows,
      paste0(
        "`", nm, "` outside (0, 90] degrees. Handbook 8.A.2 defines these as ",
        "declination angles below the horizon."
      )
    )
  })

  if (length(angle_cols) == 2L) {
    rows <- which(!is.na(dat$ANGLEL) & !is.na(dat$ANGLER))
    if (length(rows)) {
      out[[length(out) + 1L]] <- narwcr::narwc_finding(
        "angle_both_sides", "warning", "ANGLEL/ANGLER", rows,
        paste0(
          "Both ANGLEL and ANGLER recorded on the same record; a sighting is ",
          "on one side of the track, so no perpendicular distance can be ",
          "computed."
        )
      )
    }
  }

  if ("ALT" %in% names(dat)) {
    has_angle <- Reduce(`|`, lapply(angle_cols, function(nm) !is.na(dat[[nm]])))
    rows <- which(has_angle & (is.na(dat$ALT) | dat$ALT <= 0))
    if (length(rows)) {
      out[[length(out) + 1L]] <- narwcr::narwc_finding(
        "angle_without_altitude", "warning", "ALT", rows,
        "Declination angle recorded without a usable ALT (handbook 8.A.2)."
      )
    }
  }

  out
}
