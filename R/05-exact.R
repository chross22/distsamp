# Largest plausible distance, in km, between an exact sighting position and
# the event position that logged it. Sightings are made from the aircraft, so
# a larger gap means a coordinate error. Used by validate_narwc().
EXACT_POSITION_MAX_KM <- 20

#' Perpendicular distance from a track to an exact sighting position
#'
#' Given a point on the track-line, the bearing the track runs on there, and the
#' position of a sighting, returns the perpendicular (cross-track) distance from
#' the track to the sighting, and how far along the track the foot of that
#' perpendicular lies.
#'
#' @section The geometry:
#' The track through `(lat, lon)` on `bearing` defines a great circle. For a
#' sighting at angular distance \eqn{\delta_{13}} and initial bearing
#' \eqn{\theta_{13}} from that point, and a track bearing \eqn{\theta_{12}}, the
#' cross-track angular distance is
#'
#' \deqn{\delta_{xt} = \arcsin(\sin \delta_{13} \sin(\theta_{13} - \theta_{12}))}
#'
#' and the along-track distance is
#' \eqn{\arccos(\cos \delta_{13} / \cos \delta_{xt})}, signed by
#' \eqn{\cos(\theta_{13} - \theta_{12})}. Multiplying by the Earth's radius gives
#' distances. The sign of \eqn{\delta_{xt}} gives the side.
#'
#' @section Why not just the distance between the two positions:
#' A sighting is not always logged at the moment it is abeam. If it is recorded
#' 300 m before the aircraft draws level, the straight distance from the event
#' position to the animal is \eqn{\sqrt{x^2 + 300^2}} where \eqn{x} is the
#' perpendicular distance the detection function needs. For a whale 130 m off
#' the track, that is 327 m rather than 130 m: a factor of two, always in the
#' same direction. Distance sampling assumes perpendicular distances. Inflating
#' them biases the detection function towards a wider effective strip, and so
#' biases density downwards.
#'
#' `along` is returned so that this can be checked rather than assumed. It is
#' the along-track offset between the logged position and the point where the
#' sighting was abeam. Values near zero mean the two measures agree.
#'
#' @param lat,lon Position on the track-line, in decimal degrees — normally the
#'   event position of the sighting record.
#' @param bearing Bearing of the track at that position, degrees clockwise from
#'   true north. See [track_bearing()].
#' @param target_lat,target_lon Position of the sighting, in decimal degrees.
#' @param units `"m"` (default), `"km"`, or `"nmi"`.
#'
#' @return A tibble with one row per input:
#'   \describe{
#'     \item{`distance`}{Unsigned perpendicular distance from the track.}
#'     \item{`along`}{Signed along-track distance from `(lat, lon)` to the point
#'       where the sighting is abeam; positive ahead, negative behind.}
#'     \item{`side`}{`"left"`, `"right"`, `"on-track"`, or `NA`.}
#'   }
#'
#' @references
#' Veness, C. (2019) *Calculating distance, bearing and more between
#' latitude/longitude points.* Movable Type Scripts. The cross-track and
#' along-track formulae are given there in the form used here.
#'
#' Buckland, S.T., Anderson, D.R., Burnham, K.P., Laake, J.L., Borchers, D.L.
#' and Thomas, L. (2001) *Introduction to Distance Sampling.* Oxford University
#' Press. Perpendicular distance is the quantity line-transect estimators are
#' defined on.
#'
#' @seealso [exact_distance()] to apply this across a survey data frame,
#'   [gc_bearing()], [perp_distance()]
#'
#' @examples
#' # A track running due north; a sighting a little to the east is on the right
#' cross_track_distance(43, -69, bearing = 0, target_lat = 43, target_lon = -68.99)
#'
#' # The same animal logged before it was abeam: the perpendicular distance is
#' # unchanged, and `along` records how far ahead it was
#' cross_track_distance(43, -69, bearing = 0, target_lat = 43.01, target_lon = -68.99)
#'
#' @export
cross_track_distance <- function(lat, lon, bearing, target_lat, target_lon,
                                 units = c("m", "km", "nmi")) {
  units <- match.arg(units)

  # Recycle all inputs to a common length, as numeric.
  n <- max(length(lat), length(lon), length(bearing),
           length(target_lat), length(target_lon))
  lat <- rep_len(as.numeric(lat), n)
  lon <- rep_len(as.numeric(lon), n)
  bearing <- rep_len(as.numeric(bearing), n)
  target_lat <- rep_len(as.numeric(target_lat), n)
  target_lon <- rep_len(as.numeric(target_lon), n)

  # Zero-length input gives a zero-row result.
  if (n == 0L) {
    return(tibble::tibble(
      distance = numeric(0), along = numeric(0), side = character(0)
    ))
  }

  # Point 1 is the track point, point 2 lies ahead on the track, point 3 is
  # the sighting. The radius is in km, so angles x radius gives km.
  d2r <- pi / 180
  radius <- gc_radius_km()

  # delta13: angular distance (radians) from the track point to the sighting.
  # theta13: initial bearing (radians) from the track point to the sighting.
  # theta12: track bearing (radians).
  delta13 <- gc_distance(lat, lon, target_lat, target_lon) / radius
  theta13 <- gc_bearing(lat, lon, target_lat, target_lon) * d2r
  theta12 <- bearing * d2r

  # rel is the angle between the track and the line of sight. Cross-track
  # angle: delta_xt = asin(sin(delta13) sin(rel)), positive to the right.
  # Along-track angle: acos(cos(delta13) / cos(delta_xt)), positive when the
  # sighting is ahead (cos(rel) > 0). Arguments are clamped to [-1, 1] so
  # rounding cannot produce NaN.
  rel <- theta13 - theta12
  delta_xt <- asin(pmin(1, pmax(-1, sin(delta13) * sin(rel))))
  ratio <- pmin(1, pmax(-1, cos(delta13) / cos(delta_xt)))
  delta_at <- acos(ratio) * sign(cos(rel))

  # Angles (radians) to distances (km).
  distance <- abs(delta_xt) * radius
  along <- delta_at * radius

  # A sighting logged at the track point itself has no bearing from it, but
  # its perpendicular distance is zero.
  coincident <- !is.na(delta13) & delta13 == 0
  distance[coincident] <- 0
  along[coincident] <- 0

  # Side of the track from the sign of the cross-track angle.
  side <- rep(NA_character_, n)
  known <- !is.na(delta_xt)
  side[known & delta_xt > 0] <- "right"
  side[known & delta_xt < 0] <- "left"
  side[known & delta_xt == 0] <- "on-track"
  side[coincident] <- "on-track"

  # A missing position or a missing track bearing gives NA throughout.
  unusable <- is.na(delta13) | is.na(bearing)
  distance[unusable] <- NA_real_
  along[unusable] <- NA_real_
  side[unusable] <- NA_character_

  # Convert from km to the requested units (1 nmi = 1.852 km).
  scale <- switch(units, km = 1, m = 1000, nmi = 1 / 1.852)
  tibble::tibble(
    distance = distance * scale,
    along = along * scale,
    side = side
  )
}


#' Local bearing of the track-line at each record
#'
#' Estimates the direction the aircraft was flying at each record, from the
#' positions logged either side of it on the same survey line.
#'
#' @section How the bearing is taken:
#' Consecutive records often share a position: a sighting is logged at the same
#' latitude and longitude as the routine position it follows (handbook 4.2). A
#' bearing between two identical points is undefined. Records are therefore
#' collapsed into runs of distinct positions first, and the bearing for a run is
#' taken from the previous distinct position to the next one. That centred
#' difference is less sensitive to a single jittery fix than a forward
#' difference. At the first and last position of a line, where there is only one
#' neighbour, the one-sided difference is used.
#'
#' A line with only one distinct position has no direction, and gets `NA`.
#'
#' @param dat A data frame with `LATITUDE` and `LONGITUDE`, in survey order.
#' @param by Character vector of columns identifying one continuous occupation
#'   of a survey line. `NULL` (default) picks `c("FILEID", "LEGNO3")` if
#'   [make_leg_id()] has been run, then `c("FILEID", "LEGNO")`, then `"FILEID"`,
#'   and prepends `DATE` to whichever it picks when that column is present.
#'   Getting this wrong joins the end of one line to the start of the next and
#'   produces a bearing that belongs to neither. `DATE` is included because two
#'   days sharing a `LEGNO` are separated by `FILEID` alone, and some extracts
#'   carry a constant `FILEID`.
#' @param track_rows Logical vector marking the records that define the track.
#'   `NULL` (default) uses the census records, `LEGTYPE == 2`, when `LEGTYPE` is
#'   present. Circling and transit positions must be excluded: an aircraft
#'   orbiting a whale has a bearing, but it is not the track-line's.
#'
#' @return A numeric vector of bearings in degrees, one per row of `dat`, `NA`
#'   for records that do not define a track.
#'
#' @seealso [gc_bearing()], [exact_distance()]
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' dat <- make_leg_id(read_narwc(path))
#' # The fixture's lines all run due north
#' unique(round(track_bearing(dat)))
#'
#' @export
track_bearing <- function(dat, by = NULL, track_rows = NULL) {
  require_columns(dat, c("LATITUDE", "LONGITUDE"))
  if (is_empty_df(dat)) {
    return(numeric(0))
  }

  # Choose the line-occupation grouping if none was given.
  n <- nrow(dat)
  if (is.null(by)) by <- default_track_grouping(dat)
  require_columns(dat, by)

  # Track rows default to census records (LEGTYPE 2). Rows without a position
  # cannot define the track and are always excluded.
  if (is.null(track_rows)) {
    track_rows <- if ("LEGTYPE" %in% names(dat)) {
      !is.na(dat$LEGTYPE) & dat$LEGTYPE == 2
    } else {
      rep(TRUE, n)
    }
  }
  track_rows <- rep_len(as.logical(track_rows), n)
  track_rows <- track_rows & !is.na(dat$LATITUDE) & !is.na(dat$LONGITUDE)

  # Compute bearings one line occupation at a time, from its track rows only.
  # Rows that are not track rows keep NA.
  key <- group_key(dat, by)

  out <- rep(NA_real_, n)
  for (g in unique(key[track_rows])) {
    i <- which(key == g & track_rows)
    out[i] <- bearing_along_line(dat$LATITUDE[i], dat$LONGITUDE[i])
  }
  out
}

# Bearings (degrees) for one line occupation, already subset to its track
# records and in survey order. Returns one bearing per input record.
bearing_along_line <- function(lat, lon) {
  # Collapse consecutive repeats of a position into runs. `run` is the run
  # number of each record; plat/plon hold one position per run.
  run <- rle_id(paste(lat, lon, sep = "/"))
  first <- !duplicated(run)
  plat <- lat[first]
  plon <- lon[first]
  k <- length(plat)

  # One distinct position has no direction.
  if (k < 2L) {
    return(rep(NA_real_, length(lat)))
  }

  # Bearing from the previous distinct position to the next one (centred
  # difference), one-sided at the first and last positions.
  from <- pmax(seq_len(k) - 1L, 1L)
  to <- pmin(seq_len(k) + 1L, k)
  b <- gc_bearing(plat[from], plon[from], plat[to], plon[to])

  # Give every record the bearing of its run.
  b[run]
}

# Columns that identify one continuous occupation of a survey line. The first
# available set is used, most specific first. `DATE` is prepended when present:
# `LEGNO3` alone does not separate two days that share a `LEGNO`, and a
# constant `FILEID` does not either.
default_track_grouping <- function(dat) {
  prefix <- if ("DATE" %in% names(dat)) "DATE" else character(0)
  for (cols in list(c("FILEID", "LEGNO3"), c("FILEID", "LEGNO"), "FILEID")) {
    if (all(cols %in% names(dat))) {
      return(c(prefix, cols))
    }
  }
  rlang::abort(paste0(
    "No grouping column found. `by` needs at least `FILEID`; run ",
    "`make_leg_id()` first to get `LEGNO3`, or name the columns explicitly."
  ))
}


#' Perpendicular distances from exact sighting positions
#'
#' Computes the perpendicular distance from the track-line to each sighting that
#' carries an exact position in `S_LAT`/`S_LONG` (handbook 8.A.33, 8.A.34).
#'
#' @section Where this fits:
#' This is the most direct of the three right-angle distance sources this package
#' supports. It measures the quantity a detection function is defined on rather
#' than inferring it. It needs a sighting position fixed independently (from a
#' GPS mark, a photograph, or a circling pass), so it exists only where the
#' survey recorded one. In the NARWC archive that is mostly the NLPSC-era and
#' later data. Where `S_LAT`/`S_LONG` and a declination angle both exist, they
#' are independent measurements of the same thing and check each other.
#'
#' @section How it differs from the original scripts:
#' The processing scripts this package was rewritten from computed the
#' great-circle distance from the *event position* straight to the sighting
#' position. That is a radial distance, not a perpendicular one, and it exceeds
#' the perpendicular distance by however far the aircraft was from being abeam
#' when the sighting was logged. This function projects onto the track instead,
#' and returns the along-track offset in `along` so the size of that difference
#' is visible rather than silently folded into the distance.
#'
#' @section Restricted to census records:
#' Like [sighting_distances()], and for the same reason, distances are computed
#' only for on-effort records on a census line at `LEGSTAGE == 2` by default.
#' Off the census line there is no track-line to be perpendicular to. A position
#' logged while circling has a defined distance to the animal but no useful
#' perpendicular distance. `on_effort_only = FALSE` computes them anyway; this
#' is useful for diagnostics and not appropriate for fitting.
#'
#' @param dat A data frame of NARWC survey data with `LATITUDE`, `LONGITUDE`,
#'   and ideally `S_LAT`/`S_LONG`. Data without the sighting-position columns
#'   comes back with the columns present and all `NA`.
#' @param by Grouping columns identifying one occupation of a survey line, passed
#'   to [track_bearing()].
#' @param units `"m"` (default), `"km"`, or `"nmi"`.
#' @param on_effort_only Restrict to on-effort census records. Default `TRUE`.
#'
#' @return A tibble with one row per row of `dat`:
#'   \describe{
#'     \item{`distance`}{Perpendicular distance from the track-line.}
#'     \item{`along`}{Signed along-track offset between the logged position and
#'       the point where the sighting was abeam.}
#'     \item{`side`}{`"left"`, `"right"`, `"on-track"`, or `NA`.}
#'     \item{`bearing`}{The track bearing used, for diagnosis.}
#'   }
#'
#' @references
#' Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database: A
#' Guide for Users and Contributors, Version 8*, sections 8.A.33 and 8.A.34.
#' NARWC Reference Document 2023-01.
#'
#' @seealso [cross_track_distance()], [track_bearing()], [sighting_distances()],
#'   [strip_distance()]
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' dat <- flag_effort(make_leg_id(read_narwc(path)))
#' d <- exact_distance(dat)
#' cbind(dat[!is.na(d$distance), c("SPECCODE", "S_LAT", "S_LONG")],
#'       d[!is.na(d$distance), c("distance", "along", "side")])
#'
#' @export
exact_distance <- function(dat, by = NULL, units = c("m", "km", "nmi"),
                           on_effort_only = TRUE) {
  units <- match.arg(units)

  if (is_empty_df(dat)) {
    return(tibble::tibble(
      distance = numeric(0), along = numeric(0),
      side = character(0), bearing = numeric(0)
    ))
  }

  # Sighting positions, or all NA when the columns are absent.
  n <- nrow(dat)
  s_lat <- if ("S_LAT" %in% names(dat)) as.numeric(dat$S_LAT) else rep(NA_real_, n)
  s_lon <- if ("S_LONG" %in% names(dat)) as.numeric(dat$S_LONG) else rep(NA_real_, n)

  # Track bearing at each record, then project each sighting onto the track
  # through the record's own position.
  bearing <- track_bearing(dat, by = by)
  out <- cross_track_distance(
    dat$LATITUDE, dat$LONGITUDE, bearing, s_lat, s_lon, units = units
  )

  # Blank the results for records that are not on-effort census records.
  if (on_effort_only) {
    drop <- !on_effort_census_rows(dat)
    out$distance[drop] <- NA_real_
    out$along[drop] <- NA_real_
    out$side[drop] <- NA_character_
  }

  out$bearing <- bearing
  out
}


#' Perpendicular distances for sightings made while circling
#'
#' A group spotted from the census track is often circled for photographs,
#' identification, and a proper count, and the sighting is logged during that
#' circle rather than at the moment of detection. This ties each such sighting
#' back to the point on the track-line where the aircraft broke off, and measures
#' the distance from there.
#'
#' @section Why these detections matter:
#' A circling sighting is usually a genuine on-effort detection: the animal was
#' seen from the track-line, which is why the aircraft left it. Giving it no
#' distance drops it from the detection function. The dropped detections are not
#' a random sample: they are mostly the close, conspicuous, or high-priority
#' groups that were worth breaking off for. Losing them thins the near-zero end
#' of the distance distribution, where a detection function is most sensitive.
#'
#' @section The anchor:
#' The reference point is the last census record before the circling began: the
#' `LEGSTAGE == 3` break-off record where one exists (handbook 8.A.20), and
#' otherwise the last record still on the line. `anchor_event` reports which
#' record was used so the choice can be checked.
#'
#' The bearing is the *inbound* heading: from the previous distinct census
#' position to the anchor, which is the direction the aircraft was flying when
#' the animal was detected. It is not the centred difference [track_bearing()]
#' uses. The record after a break-off is the resume record, and a resume point
#' offset from the break-off would swing the bearing by an amount unrelated to
#' the track being flown.
#'
#' @section Break-off point, or the line through it:
#' The aircraft usually flies past a group before turning, so the break-off point
#' is beyond the animal rather than abeam of it. `radial` is the straight-line
#' distance from the break-off point to the animal; `distance` is that position
#' projected perpendicularly onto the census line, and `along` is how far back
#' along the line the animal was abeam. **`distance` is the one a detection
#' function needs.** `radial` is generally larger, by the margin `along`
#' records.
#'
#' @section What this cannot fix:
#' The position is recorded some minutes after detection, so the animal has
#' moved, and the distance is an estimate of where it was when detected rather
#' than a measurement of it. That error is not quantified here. Circling
#' distances are a distinct and less reliable source. `distance_source` marks
#' them, and they should be excluded from a detection function unless their
#' inclusion is a deliberate, stated choice.
#'
#' @param dat A data frame of NARWC survey data in survey order, with `LATITUDE`,
#'   `LONGITUDE`, `LEGTYPE`, and ideally `CIRCLE` from [flag_circling()] and
#'   `S_LAT`/`S_LONG`. Without `CIRCLE`, `LEGTYPE == 4` is used.
#' @param by Grouping columns identifying one occupation of a survey line, as in
#'   [track_bearing()].
#' @param units `"m"` (default), `"km"`, or `"nmi"`.
#' @param position Which position to treat as the animal's. `"exact"` (default)
#'   uses `S_LAT`/`S_LONG` only. `"logged"` falls back to the record's own
#'   `LATITUDE`/`LONGITUDE` where no exact position exists. That position is the
#'   *aircraft* orbiting the animal, offset by the radius of the circle (a few
#'   hundred metres, the same size as the distances being measured).
#'   `position_source` records which position was used.
#'
#' @return A tibble with one row per row of `dat`, populated only for circling
#'   sightings:
#'   \describe{
#'     \item{`distance`}{Perpendicular distance from the census line.}
#'     \item{`along`}{Signed along-track distance from the break-off point to
#'       where the animal was abeam; negative means back down the line.}
#'     \item{`side`}{`"left"`, `"right"`, `"on-track"`, or `NA`.}
#'     \item{`radial`}{Straight-line distance from the break-off point.}
#'     \item{`bearing`}{Inbound track bearing at the anchor.}
#'     \item{`anchor_event`}{`EVENTNO` of the anchor record, or its row number
#'       when `EVENTNO` is absent.}
#'     \item{`position_source`}{`"exact"` or `"logged"`.}
#'   }
#'
#' @references
#' Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database: A
#' Guide for Users and Contributors, Version 8*, sections 4.2 (event 12), 8.A.20,
#' and 8.A.21. NARWC Reference Document 2023-01.
#'
#' @seealso [flag_circling()], [attach_circling_sightings()],
#'   [cross_track_distance()], [exact_distance()]
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' dat <- flag_circling(make_leg_id(read_narwc(path)))
#' d <- circling_distance(dat)
#' d[!is.na(d$distance), ]
#'
#' @export
circling_distance <- function(dat, by = NULL, units = c("m", "km", "nmi"),
                              position = c("exact", "logged")) {
  units <- match.arg(units)
  position <- match.arg(position)

  # Template for the result; also returned for empty input.
  empty <- tibble::tibble(
    distance = numeric(0), along = numeric(0), side = character(0),
    radial = numeric(0), bearing = numeric(0), anchor_event = numeric(0),
    position_source = character(0)
  )
  if (is_empty_df(dat)) {
    return(empty)
  }

  # Choose the line-occupation grouping if none was given.
  require_columns(dat, c("LATITUDE", "LONGITUDE"))
  n <- nrow(dat)
  if (is.null(by)) by <- default_track_grouping(dat)
  require_columns(dat, by)

  # Circling rows: CIRCLE == 1 from flag_circling(), else LEGTYPE 4.
  circling <- if ("CIRCLE" %in% names(dat)) {
    !is.na(dat$CIRCLE) & dat$CIRCLE == 1
  } else if ("LEGTYPE" %in% names(dat)) {
    !is.na(dat$LEGTYPE) & dat$LEGTYPE == 4
  } else {
    rep(FALSE, n)
  }

  # Keep only circling rows that carry a sighting (a species code), not every
  # position logged during the circle.
  if ("SPECCODE" %in% names(dat)) {
    circling <- circling & !is.na(dat$SPECCODE) & dat$SPECCODE != ""
  }

  # Census rows that can serve as anchors: LEGTYPE 2, not circling, with a
  # position.
  census <- if ("LEGTYPE" %in% names(dat)) {
    !is.na(dat$LEGTYPE) & dat$LEGTYPE == 2 & !circling
  } else {
    !circling
  }
  census <- census & !is.na(dat$LATITUDE) & !is.na(dat$LONGITUDE)

  # For each line occupation with a circling sighting, find each sighting's
  # anchor row and the inbound track bearing (degrees) at that anchor.
  key <- group_key(dat, by)

  anchor <- rep(NA_integer_, n)
  bearing <- rep(NA_real_, n)
  for (g in unique(key[circling])) {
    rows <- which(key == g)
    found <- anchor_along_line(rows, dat$LATITUDE, dat$LONGITUDE, census, circling)
    anchor[rows] <- found$anchor
    bearing[rows] <- found$bearing
  }

  # Animal position: the exact sighting position where present. With
  # position = "logged", fall back to the record's own (aircraft) position.
  # `source` records which was used.
  s_lat <- if ("S_LAT" %in% names(dat)) as.numeric(dat$S_LAT) else rep(NA_real_, n)
  s_lon <- if ("S_LONG" %in% names(dat)) as.numeric(dat$S_LONG) else rep(NA_real_, n)

  source <- rep(NA_character_, n)
  source[circling & !is.na(s_lat) & !is.na(s_lon)] <- "exact"
  if (position == "logged") {
    fallback <- circling & is.na(source) &
      !is.na(dat$LATITUDE) & !is.na(dat$LONGITUDE)
    s_lat[fallback] <- dat$LATITUDE[fallback]
    s_lon[fallback] <- dat$LONGITUDE[fallback]
    source[fallback] <- "logged"
  }

  # A row is usable when it is a circling sighting with an anchor and an
  # animal position. `a` indexes the anchor row; NA for unusable rows makes
  # their anchor coordinates NA, and so their results NA.
  usable <- circling & !is.na(anchor) & !is.na(source)
  a <- anchor
  a[!usable] <- NA_integer_

  # Perpendicular distance from the census line through the anchor.
  out <- cross_track_distance(
    dat$LATITUDE[a], dat$LONGITUDE[a], bearing,
    ifelse(usable, s_lat, NA_real_), ifelse(usable, s_lon, NA_real_),
    units = units
  )

  # Straight-line distance from the anchor to the animal, km converted to the
  # requested units.
  scale <- switch(units, km = 1, m = 1000, nmi = 1 / 1.852)
  out$radial <- gc_distance(
    dat$LATITUDE[a], dat$LONGITUDE[a],
    ifelse(usable, s_lat, NA_real_), ifelse(usable, s_lon, NA_real_)
  ) * scale
  # Diagnostics: the bearing used, which record anchored the sighting, and
  # which position was used for the animal.
  out$bearing <- bearing
  out$anchor_event <- if ("EVENTNO" %in% names(dat)) {
    as.numeric(dat$EVENTNO)[a]
  } else {
    as.numeric(a)
  }
  out$position_source <- ifelse(usable, source, NA_character_)

  out[, names(empty)]
}

# Anchor row and inbound bearing for each circling row of one line
# occupation. `rows` are the occupation's row numbers in survey order; the
# other arguments are full-length vectors over the whole frame. The anchor is
# the last census record before the circle began. The bearing (degrees) runs
# from the previous distinct census position to the anchor's position: the
# heading when the animal was detected. Non-circling rows get NA.
anchor_along_line <- function(rows, lat, lon, census, circling) {
  anchor <- rep(NA_integer_, length(rows))
  bearing <- rep(NA_real_, length(rows))

  # State carried along the line: the latest census row, the bearing into
  # it, and the latest distinct census position.
  last_census <- NA_integer_
  last_bearing <- NA_real_
  prev_lat <- NA_real_
  prev_lon <- NA_real_

  # Walk the line in order.
  for (k in seq_along(rows)) {
    i <- rows[k]
    if (census[i]) {
      # Census row: update the bearing only when the position has changed,
      # because two identical positions have no bearing.
      moved <- is.na(prev_lat) || lat[i] != prev_lat || lon[i] != prev_lon
      if (moved) {
        if (!is.na(prev_lat)) {
          last_bearing <- gc_bearing(prev_lat, prev_lon, lat[i], lon[i])
        }
        prev_lat <- lat[i]
        prev_lon <- lon[i]
      }
      last_census <- i
    } else if (circling[i]) {
      # Circling sighting: tie it to the latest census row seen so far.
      anchor[k] <- last_census
      bearing[k] <- last_bearing
    }
  }

  list(anchor = anchor, bearing = bearing)
}
