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
#' Resolves a right-angle distance for each sighting from whichever of the
#' archive's sources is available, and records which one was used.
#'
#' @section Four sources, one column:
#' The NARWC archive records right-angle distance four different ways, because
#' the protocol changed and because some sightings are made off the track-line.
#' Each has its own function; this assembles them.
#'
#' | source | from | gives |
#' |---|---|---|
#' | `"angle"` | `ANGLEL`/`ANGLER` and `ALT` (8.A.2), 2022 onwards | a point distance |
#' | `"exact"` | `S_LAT`/`S_LONG` (8.A.33, 8.A.34) projected onto the track | a point distance |
#' | `"strip"` | `STRIP` code books (8.A.31), before 2022 | an **interval** |
#' | `"circling"` | the break-off record on the census line | a point distance, weakly |
#'
#' `sources` is a precedence order, not a set: the first one that yields a
#' distance for a record wins, and `distance_source` records which that was.
#'
#' @section Why the provenance column is not optional:
#' Mixing sources in one detection function is a decision, and it should be a
#' conscious one rather than something discovered afterwards. Point and interval
#' distances cannot share a likelihood — `STRIP` rows must be fitted binned —
#' and circling distances are estimated minutes after the detection they
#' describe. Without `distance_source` none of that is visible in the table a
#' model gets fitted to, and a reviewer will ask.
#'
#' Where a record carries both an angle and an exact position, the two are
#' independent measurements of the same quantity. The default order prefers the
#' angle, because it is taken at the moment the sighting is abeam and so measures
#' the perpendicular distance directly, with no projection and no position error.
#' Passing `sources = c("exact", "angle", "strip")` reverses that. Comparing the
#' two is a genuine check on both, and [exact_distance()] returns its own columns
#' for exactly that purpose.
#'
#' @section Circling is opt-in:
#' `"circling"` is not in the default order. Those sightings are usually real
#' on-effort detections and dropping them thins the near-zero end of the distance
#' distribution — but the position is fixed after the animal has moved, so they
#' are a weaker source. Ask for them deliberately, and see
#' [circling_distance()].
#'
#' @section Restricted to census records:
#' Handbook 8.A.31 restricts right-angle distance measurement to on-effort
#' sightings during census lines, and notes that some teams record angles during
#' transits and circling for practice. Those must not enter a detection function,
#' so by default distances are left `NA` elsewhere. `"circling"` is exempt, since
#' those records are off effort by definition.
#'
#' @param dat A data frame of NARWC survey data. Columns that are absent simply
#'   make their source unavailable; nothing errors.
#' @param sources Precedence order over `"angle"`, `"exact"`, `"strip"`, and
#'   `"circling"`. Defaults to `c("angle", "exact", "strip")`.
#' @param units `"m"` (default), `"km"`, or `"nmi"`.
#' @param on_effort_only Restrict to on-effort census records. Default `TRUE`.
#' @param strip_scheme,strip_platform,strip_left_truncation Passed to
#'   [strip_distance()]. The scheme defaults to `"auto"`, which chooses the code
#'   book from `DATE`.
#' @param by Grouping columns identifying one occupation of a survey line, for
#'   the sources that need a track bearing. See [track_bearing()].
#'
#' @return `dat` with five columns added:
#'   \describe{
#'     \item{`distance`}{Point distance from the track-line, or `NA` for a row
#'       whose source gives an interval.}
#'     \item{`distbegin`,`distend`}{Interval bounds, for `"strip"` rows.}
#'     \item{`side`}{`"left"`, `"right"`, `"both"`, `"on-track"`, or `NA`.}
#'     \item{`distance_source`}{Which source supplied the row.}
#'   }
#'
#' @seealso [perp_distance()], [exact_distance()], [strip_distance()],
#'   [circling_distance()], [detection_data()], [segment_survey()]
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' dat <- flag_effort(make_leg_id(read_narwc(path)))
#'
#' out <- sighting_distances(dat)
#' cols <- c("SPECCODE", "distance", "distbegin", "distend", "side",
#'           "distance_source")
#' subset(out, !is.na(distance_source), cols)
#'
#' # Counts by source - what a methods section has to state
#' table(out$distance_source, useNA = "no")
#'
#' # Prefer the exact position where both it and an angle exist
#' rev_out <- sighting_distances(dat, sources = c("exact", "angle", "strip"))
#' table(rev_out$distance_source, useNA = "no")
#'
#' @export
sighting_distances <- function(dat,
                               sources = c("angle", "exact", "strip"),
                               units = c("m", "km", "nmi"),
                               on_effort_only = TRUE,
                               strip_scheme = "auto",
                               strip_platform = "skymaster",
                               strip_left_truncation = FALSE,
                               by = NULL) {
  units <- match.arg(units)
  known <- c("angle", "exact", "strip", "circling")
  bad <- setdiff(sources, known)
  if (length(bad)) {
    cli_abort_bad_arg("sources", bad[1], known)
  }

  if (is_empty_df(dat)) {
    dat$distance <- numeric(0)
    dat$distbegin <- numeric(0)
    dat$distend <- numeric(0)
    dat$side <- character(0)
    dat$distance_source <- character(0)
    return(dat)
  }

  n <- nrow(dat)
  eligible <- if (on_effort_only) on_effort_census_rows(dat) else rep(TRUE, n)

  distance <- rep(NA_real_, n)
  distbegin <- rep(NA_real_, n)
  distend <- rep(NA_real_, n)
  side <- rep(NA_character_, n)
  source <- rep(NA_character_, n)

  # A row is claimed by the first source in `sources` that yields something for
  # it, so later sources only ever fill gaps.
  for (src in sources) {
    open <- is.na(source)
    if (!any(open)) break
    got <- distance_from_source(
      dat, src, units,
      strip_scheme = strip_scheme, strip_platform = strip_platform,
      strip_left_truncation = strip_left_truncation, by = by
    )
    if (is.null(got)) next

    # Circling records are off effort by definition, so the census restriction
    # cannot apply to them.
    allowed <- if (src == "circling") rep(TRUE, n) else eligible
    take <- open & allowed &
      (!is.na(got$distance) | !is.na(got$distbegin))

    distance[take] <- got$distance[take]
    distbegin[take] <- got$distbegin[take]
    distend[take] <- got$distend[take]
    side[take] <- got$side[take]
    source[take] <- src

    # A source can establish which side of the track a sighting was on without
    # yielding a distance - most importantly `side = "both"`, where both angle
    # columns are populated and the record is ambiguous. Record that, but leave
    # the row unclaimed so a later source can still supply a distance for it.
    side_only <- open & allowed & is.na(side) & !is.na(got$side)
    side[side_only] <- got$side[side_only]
  }

  dat$distance <- distance
  dat$distbegin <- distbegin
  dat$distend <- distend
  dat$side <- side
  dat$distance_source <- source
  dat
}

# One source's contribution, in a common shape: distance / distbegin / distend /
# side, one row per row of `dat`. NULL when the source cannot apply at all.
distance_from_source <- function(dat, src, units, strip_scheme, strip_platform,
                                 strip_left_truncation, by) {
  n <- nrow(dat)
  blank <- function() {
    list(distance = rep(NA_real_, n), distbegin = rep(NA_real_, n),
         distend = rep(NA_real_, n), side = rep(NA_character_, n))
  }

  if (src == "angle") {
    if (!any(c("ANGLEL", "ANGLER") %in% names(dat))) return(NULL)
    left <- if ("ANGLEL" %in% names(dat)) as.numeric(dat$ANGLEL) else rep(NA_real_, n)
    right <- if ("ANGLER" %in% names(dat)) as.numeric(dat$ANGLER) else rep(NA_real_, n)
    alt <- if ("ALT" %in% names(dat)) as.numeric(dat$ALT) else rep(NA_real_, n)

    has_l <- !is.na(left)
    has_r <- !is.na(right)
    out <- blank()
    out$side[has_l & !has_r] <- "left"
    out$side[has_r & !has_l] <- "right"
    # A sighting is on one side of the track, so both is ambiguous and yields
    # no distance - reported by validate_narwc() as `angle_both_sides`.
    out$side[has_l & has_r] <- "both"

    angle <- rep(NA_real_, n)
    angle[has_l & !has_r] <- left[has_l & !has_r]
    angle[has_r & !has_l] <- right[has_r & !has_l]
    out$distance <- perp_distance(
      angle, alt, units = if (units == "nmi") "m" else units
    )
    if (units == "nmi") out$distance <- out$distance / 1852
    return(out)
  }

  if (src == "exact") {
    if (!all(c("S_LAT", "S_LONG") %in% names(dat))) return(NULL)
    ex <- exact_distance(dat, by = by, units = units, on_effort_only = FALSE)
    out <- blank()
    out$distance <- ex$distance
    out$side <- ex$side
    return(out)
  }

  if (src == "strip") {
    if (!"STRIP" %in% names(dat)) return(NULL)
    date <- if ("DATE" %in% names(dat)) dat$DATE else NULL
    if (strip_scheme == "auto" && is.null(date)) return(NULL)
    st <- strip_distance(
      dat$STRIP, platform = strip_platform, scheme = strip_scheme,
      date = date, units = units, left_truncation = strip_left_truncation
    )
    out <- blank()
    out$distbegin <- st$distbegin
    out$distend <- st$distend
    out$side <- st$side
    return(out)
  }

  if (src == "circling") {
    circ <- circling_distance(dat, by = by, units = units)
    out <- blank()
    out$distance <- circ$distance
    out$side <- circ$side
    return(out)
  }

  NULL
}
