# How far an exact sighting position may plausibly sit from the event position
# that logged it. A sighting is made from the aircraft; anything beyond this is
# a coordinate problem. Used by validate_narwc().
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
#' perpendicular distance the detection function needs — for a whale 130 m off
#' the track, that is 327 m rather than 130 m, an error of a factor of two and
#' always in the same direction. Distance sampling assumes perpendicular
#' distances, and inflating them biases the detection function towards a wider
#' effective strip and so density downwards.
#'
#' `along` is returned so that this can be checked rather than assumed: it is
#' the along-track offset between the logged position and the point where the
#' sighting was abeam. Values near zero mean the two measures would have agreed.
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

  n <- max(length(lat), length(lon), length(bearing),
           length(target_lat), length(target_lon))
  lat <- rep_len(as.numeric(lat), n)
  lon <- rep_len(as.numeric(lon), n)
  bearing <- rep_len(as.numeric(bearing), n)
  target_lat <- rep_len(as.numeric(target_lat), n)
  target_lon <- rep_len(as.numeric(target_lon), n)

  if (n == 0L) {
    return(tibble::tibble(
      distance = numeric(0), along = numeric(0), side = character(0)
    ))
  }

  d2r <- pi / 180
  radius <- gc_radius_km()

  # Angular distance and bearing from the track point to the sighting.
  delta13 <- gc_distance(lat, lon, target_lat, target_lon) / radius
  theta13 <- gc_bearing(lat, lon, target_lat, target_lon) * d2r
  theta12 <- bearing * d2r

  rel <- theta13 - theta12
  delta_xt <- asin(pmin(1, pmax(-1, sin(delta13) * sin(rel))))
  ratio <- pmin(1, pmax(-1, cos(delta13) / cos(delta_xt)))
  delta_at <- acos(ratio) * sign(cos(rel))

  distance <- abs(delta_xt) * radius
  along <- delta_at * radius

  # A sighting logged at the event position itself has no bearing from it, but
  # its perpendicular distance is unambiguously zero.
  coincident <- !is.na(delta13) & delta13 == 0
  distance[coincident] <- 0
  along[coincident] <- 0

  side <- rep(NA_character_, n)
  known <- !is.na(delta_xt)
  side[known & delta_xt > 0] <- "right"
  side[known & delta_xt < 0] <- "left"
  side[known & delta_xt == 0] <- "on-track"
  side[coincident] <- "on-track"

  unusable <- is.na(delta13) | is.na(bearing)
  distance[unusable] <- NA_real_
  along[unusable] <- NA_real_
  side[unusable] <- NA_character_

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
#' Consecutive records often share a position — a sighting is logged at the same
#' latitude and longitude as the routine position it follows (handbook 4.2) — and
#' a bearing between two identical points is undefined. Records are therefore
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
#'   produces a bearing that belongs to neither — which is why `DATE` is
#'   included: two days sharing a `LEGNO` are separated by `FILEID` alone, and
#'   some extracts carry a constant `FILEID`.
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

  n <- nrow(dat)
  if (is.null(by)) by <- default_track_grouping(dat)
  require_columns(dat, by)

  if (is.null(track_rows)) {
    track_rows <- if ("LEGTYPE" %in% names(dat)) {
      !is.na(dat$LEGTYPE) & dat$LEGTYPE == 2
    } else {
      rep(TRUE, n)
    }
  }
  track_rows <- rep_len(as.logical(track_rows), n)
  track_rows <- track_rows & !is.na(dat$LATITUDE) & !is.na(dat$LONGITUDE)

  key <- do.call(
    paste,
    c(lapply(by, function(nm) as.character(dat[[nm]])), sep = "\r")
  )

  out <- rep(NA_real_, n)
  for (g in unique(key[track_rows])) {
    i <- which(key == g & track_rows)
    out[i] <- bearing_along_line(dat$LATITUDE[i], dat$LONGITUDE[i])
  }
  out
}

# Bearings for one line occupation, already subset to its track records.
bearing_along_line <- function(lat, lon) {
  run <- rle_id(paste(lat, lon, sep = "/"))
  first <- !duplicated(run)
  plat <- lat[first]
  plon <- lon[first]
  k <- length(plat)

  if (k < 2L) {
    return(rep(NA_real_, length(lat)))
  }

  # Centred difference in the interior, one-sided at the ends.
  from <- pmax(seq_len(k) - 1L, 1L)
  to <- pmin(seq_len(k) + 1L, k)
  b <- gc_bearing(plat[from], plon[from], plat[to], plon[to])

  b[run]
}

# Columns that identify one continuous occupation of a survey line, most
# specific first. `DATE` is prepended whenever it is available: `LEGNO3` alone
# does not separate two days that share a `LEGNO`, and a constant `FILEID`
# leaves nothing that does.
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
#' supports, because it measures the quantity a detection function is defined on
#' rather than inferring it. It needs the sighting position to have been fixed
#' independently — from a GPS mark, a photograph, or a circling pass — so it is
#' available only where the survey recorded one, which in the NARWC archive is
#' mostly the NLPSC-era and later data. Where `S_LAT`/`S_LONG` and a declination
#' angle both exist, comparing the two is a useful check on both; they are
#' independent measurements of the same thing.
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
#' Off the census line there is no track-line to be perpendicular to: a position
#' logged while circling has a well-defined distance to the animal and no useful
#' perpendicular distance at all. Setting `on_effort_only = FALSE` computes them
#' anyway, which is occasionally useful for diagnostics and never appropriate for
#' fitting.
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

  n <- nrow(dat)
  s_lat <- if ("S_LAT" %in% names(dat)) as.numeric(dat$S_LAT) else rep(NA_real_, n)
  s_lon <- if ("S_LONG" %in% names(dat)) as.numeric(dat$S_LONG) else rep(NA_real_, n)

  bearing <- track_bearing(dat, by = by)
  out <- cross_track_distance(
    dat$LATITUDE, dat$LONGITUDE, bearing, s_lat, s_lon, units = units
  )

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
#' distance drops it from the detection function altogether, and the dropped
#' detections are not a random sample — they are disproportionately the close,
#' conspicuous, or high-priority groups that were worth breaking off for. Losing
#' those thins the near-zero end of the distance distribution, exactly where a
#' detection function is most sensitive.
#'
#' @section The anchor:
#' The reference point is the last census record before the circling began — the
#' `LEGSTAGE == 3` break-off record where one exists (handbook 8.A.20), and
#' otherwise the last record still on the line. `anchor_event` reports which
#' record was used so the choice can be checked.
#'
#' The bearing is the *inbound* heading: from the previous distinct census
#' position to the anchor, which is the direction the aircraft was flying when
#' the animal was detected. It is deliberately not the centred difference
#' [track_bearing()] uses, because the record after a break-off is the resume
#' record, and a resume point offset from the break-off would swing the bearing
#' by an amount that has nothing to do with the track being flown.
#'
#' @section Break-off point, or the line through it:
#' The aircraft usually flies past a group before turning, so the break-off point
#' is beyond the animal rather than abeam of it. `radial` is the straight-line
#' distance from the break-off point to the animal; `distance` is that position
#' projected perpendicularly onto the census line, and `along` is how far back
#' along the line the animal was abeam. **`distance` is the one a detection
#' function needs** — `radial` will generally be larger, by exactly the margin
#' `along` records.
#'
#' @section What this cannot fix:
#' The position is recorded some minutes after detection, so the animal has
#' moved, and the distance is an estimate of where it was when detected rather
#' than a measurement of it. That error is not quantified here. Treat circling
#' distances as a distinct and less reliable source — which is why
#' `distance_source` marks them, and why they should be excluded from a detection
#' function unless their inclusion is a deliberate, stated choice.
#'
#' @param dat A data frame of NARWC survey data in survey order, with `LATITUDE`,
#'   `LONGITUDE`, `LEGTYPE`, and ideally `CIRCLE` from [flag_circling()] and
#'   `S_LAT`/`S_LONG`. Without `CIRCLE`, `LEGTYPE == 4` is used.
#' @param by Grouping columns identifying one occupation of a survey line, as in
#'   [track_bearing()].
#' @param units `"m"` (default), `"km"`, or `"nmi"`.
#' @param position Which position to treat as the animal's. `"exact"` (default)
#'   uses `S_LAT`/`S_LONG` only. `"logged"` falls back to the record's own
#'   `LATITUDE`/`LONGITUDE` where no exact position exists — but that is the
#'   *aircraft* orbiting the animal, offset by the radius of the circle, which at
#'   a few hundred metres is the same size as the distances being measured. Use
#'   it knowing that, and read `position_source` to see which applied.
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

  empty <- tibble::tibble(
    distance = numeric(0), along = numeric(0), side = character(0),
    radial = numeric(0), bearing = numeric(0), anchor_event = numeric(0),
    position_source = character(0)
  )
  if (is_empty_df(dat)) {
    return(empty)
  }

  require_columns(dat, c("LATITUDE", "LONGITUDE"))
  n <- nrow(dat)
  if (is.null(by)) by <- default_track_grouping(dat)
  require_columns(dat, by)

  circling <- if ("CIRCLE" %in% names(dat)) {
    !is.na(dat$CIRCLE) & dat$CIRCLE == 1
  } else if ("LEGTYPE" %in% names(dat)) {
    !is.na(dat$LEGTYPE) & dat$LEGTYPE == 4
  } else {
    rep(FALSE, n)
  }

  # This is about sightings, not about every position logged during the circle.
  if ("SPECCODE" %in% names(dat)) {
    circling <- circling & !is.na(dat$SPECCODE) & dat$SPECCODE != ""
  }

  census <- if ("LEGTYPE" %in% names(dat)) {
    !is.na(dat$LEGTYPE) & dat$LEGTYPE == 2 & !circling
  } else {
    !circling
  }
  census <- census & !is.na(dat$LATITUDE) & !is.na(dat$LONGITUDE)

  key <- do.call(
    paste,
    c(lapply(by, function(nm) as.character(dat[[nm]])), sep = "\r")
  )

  anchor <- rep(NA_integer_, n)
  bearing <- rep(NA_real_, n)
  for (g in unique(key[circling])) {
    rows <- which(key == g)
    found <- anchor_along_line(rows, dat$LATITUDE, dat$LONGITUDE, census, circling)
    anchor[rows] <- found$anchor
    bearing[rows] <- found$bearing
  }

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

  usable <- circling & !is.na(anchor) & !is.na(source)
  a <- anchor
  a[!usable] <- NA_integer_

  out <- cross_track_distance(
    dat$LATITUDE[a], dat$LONGITUDE[a], bearing,
    ifelse(usable, s_lat, NA_real_), ifelse(usable, s_lon, NA_real_),
    units = units
  )

  scale <- switch(units, km = 1, m = 1000, nmi = 1 / 1.852)
  out$radial <- gc_distance(
    dat$LATITUDE[a], dat$LONGITUDE[a],
    ifelse(usable, s_lat, NA_real_), ifelse(usable, s_lon, NA_real_)
  ) * scale
  out$bearing <- bearing
  out$anchor_event <- if ("EVENTNO" %in% names(dat)) {
    as.numeric(dat$EVENTNO)[a]
  } else {
    as.numeric(a)
  }
  out$position_source <- ifelse(usable, source, NA_character_)

  out[, names(empty)]
}

# Anchor record and inbound bearing for each circling row of one line
# occupation. The anchor is the last census record before the circle began; the
# bearing is from the previous distinct census position to it, which is the
# heading the aircraft was on when the animal was detected.
anchor_along_line <- function(rows, lat, lon, census, circling) {
  anchor <- rep(NA_integer_, length(rows))
  bearing <- rep(NA_real_, length(rows))

  last_census <- NA_integer_
  last_bearing <- NA_real_
  prev_lat <- NA_real_
  prev_lon <- NA_real_

  for (k in seq_along(rows)) {
    i <- rows[k]
    if (census[i]) {
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
      anchor[k] <- last_census
      bearing[k] <- last_bearing
    }
  }

  list(anchor = anchor, bearing = bearing)
}
