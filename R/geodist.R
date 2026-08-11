#' Great-circle distance between positions
#'
#' Vectorised great-circle distance in kilometres on a spherical Earth.
#'
#' @section Methods:
#' \describe{
#'   \item{`"becker"` (alias `"eab"`)}{The `fn.grcirclkm` routine from Elizabeth
#'     Becker's `segchopr` code. Spherical law of cosines: convert to radians,
#'     take the arc cosine, convert the resulting angle back to degrees, then
#'     scale by 60 nautical miles per degree and 1.852 km per nautical mile.}
#'   \item{`"kenney"` (alias `"rdk"`)}{Kenney and Winn (1986), p. 347, who give
#'     the formula as
#'     `D = 111.12 arccos[sin(X1) sin(X2) + cos(X1) cos(X2) cos(Y2 - Y1)]`
#'     for latitudes `X` and longitudes `Y`, with the arc cosine in degrees.}
#'   \item{`"haversine"`}{The haversine formula, on the same sphere. Default.}
#' }
#'
#' @section The Becker and Kenney methods are the same formula:
#' Both are the spherical law of cosines, and both scale by the same constant:
#' 60 x 1.852 = 111.12. They therefore return identical values, to the last bit.
#' Both names are kept so that existing scripts and configuration files keep
#' reading sensibly, and so you can record in an analysis which lineage you
#' meant to follow — but choosing between them will not change your results.
#'
#' Two caveats about the historical implementations:
#'
#' * The `dist.rdk` function in the original processing code passed decimal
#'   degrees straight into `sin()` and `cos()` with no conversion to radians, so
#'   it did not compute the Kenney and Winn distance at all. `"kenney"` here
#'   will not reproduce that function's output.
#' * The law of cosines loses precision at short range, because the arc cosine
#'   of a number very close to 1 is ill-conditioned. Consecutive positions in a
#'   computer-logged aerial survey are often only tens of metres apart, which is
#'   squarely in that regime. `"haversine"` is numerically stable there, agrees
#'   with the other two to well within survey accuracy at all ranges, and is the
#'   default for that reason.
#'
#' @param lat1,lon1 Numeric vectors of latitudes and longitudes, in decimal
#'   degrees, of the first positions. West longitudes are negative (handbook
#'   8.A.22).
#' @param lat2,lon2 Numeric vectors of the second positions. Recycled against
#'   `lat1`/`lon1` following the usual R rules.
#' @param method One of `"haversine"` (default), `"becker"`, or `"kenney"`; see
#'   Methods. `"eab"` and `"rdk"` are accepted as aliases for the latter two.
#'
#' @section Great circles versus rhumb lines:
#' A survey aircraft flies a rhumb line, not a great circle, so these distances
#' are formally the wrong ones. Kenney and Winn (1986, p. 347) addressed this
#' directly and dismissed it: "for two points around 10 km apart, typical of
#' track line segments in the data, great circle and rhumb line distance differ
#' by <1 m, an error of <0.01%." Consecutive positions in modern computer-logged
#' data are far closer together than 10 km, so the discrepancy is smaller still.
#'
#' @return A numeric vector of distances in kilometres. `NA` where any input
#'   coordinate is `NA`, and exactly `0` where the two positions coincide.
#'
#' @references
#' Kenney, R.D. and Winn, H.E. (1986) Cetacean high-use habitats of the
#' northeast United States continental shelf. *Fishery Bulletin* 84(2):345-357.
#' (The distance formula is on p. 347.)
#'
#' Sinnott, R.W. (1984) Virtues of the haversine. *Sky and Telescope* 68(2):159.
#'
#' @examples
#' # Roughly one degree of latitude, in km
#' gc_distance(43, -69, 44, -69)
#'
#' # Becker and Kenney are the same formula and agree exactly
#' gc_distance(43, -69, 44, -70, method = "becker") ==
#'   gc_distance(43, -69, 44, -70, method = "kenney")
#'
#' # Haversine agrees to within millimetres at survey scales
#' gc_distance(43, -69, 43.01, -69, method = "haversine")
#' gc_distance(43, -69, 43.01, -69, method = "becker")
#'
#' @export
gc_distance <- function(lat1, lon1, lat2, lon2,
                        method = c("haversine", "becker", "kenney", "eab", "rdk")) {
  method <- dist_method_canonical(match.arg(method))

  n <- max(length(lat1), length(lon1), length(lat2), length(lon2))
  lat1 <- rep_len(lat1, n)
  lon1 <- rep_len(lon1, n)
  lat2 <- rep_len(lat2, n)
  lon2 <- rep_len(lon2, n)

  deg2rad <- pi / 180
  phi1 <- lat1 * deg2rad
  phi2 <- lat2 * deg2rad

  # 60 nmi/degree * 1.852 km/nmi == 111.12 km/degree. Becker and Kenney reach
  # the same constant by different routes.
  km_per_degree <- if (method == "kenney") 111.12 else 60 * 1.852
  radius_km <- km_per_degree / deg2rad

  if (method == "haversine") {
    dphi <- phi2 - phi1
    dlam <- (lon2 - lon1) * deg2rad
    a <- sin(dphi / 2)^2 + cos(phi1) * cos(phi2) * sin(dlam / 2)^2
    a <- pmin(1, pmax(0, a))
    out <- 2 * radius_km * asin(sqrt(a))
  } else {
    dlam <- (lon1 - lon2) * deg2rad
    cos_angle <- sin(phi1) * sin(phi2) + cos(phi1) * cos(phi2) * cos(dlam)
    # Rounding can push the cosine a hair outside [-1, 1] for nearby or
    # antipodal points, which would make acos() return NaN.
    cos_angle <- pmin(1, pmax(-1, cos_angle))
    out <- (acos(cos_angle) / deg2rad) * km_per_degree
  }

  # Identical positions: force an exact zero rather than a rounding artefact.
  same <- !is.na(lat1) & !is.na(lon1) & !is.na(lat2) & !is.na(lon2) &
    lat1 == lat2 & lon1 == lon2
  out[same] <- 0

  out[is.na(lat1) | is.na(lon1) | is.na(lat2) | is.na(lon2)] <- NA_real_
  out
}

#' Initial great-circle bearing between positions
#'
#' The bearing, in degrees clockwise from true north, along which a great circle
#' leaves the first position heading for the second.
#'
#' @section Initial, not constant:
#' A great circle changes bearing as it is followed, so this is the bearing *at
#' the first position*. Over the distances between consecutive survey positions
#' the change is negligible — a tenth of a degree over 10 km at these latitudes —
#' but it is the reason [cross_track_distance()] takes a bearing and a point
#' together rather than a bearing alone.
#'
#' @param lat1,lon1 Numeric vectors of latitudes and longitudes of the start
#'   positions, in decimal degrees. West longitudes are negative.
#' @param lat2,lon2 Numeric vectors of the positions bearing is taken to.
#'   Recycled against `lat1`/`lon1`.
#'
#' @return A numeric vector of bearings in `[0, 360)`. `NA` where any coordinate
#'   is `NA`, and `NA` where the two positions coincide, which has no bearing.
#'
#' @seealso [gc_distance()], [cross_track_distance()], [track_bearing()]
#'
#' @examples
#' # Due north along a meridian
#' gc_bearing(43, -69, 44, -69)
#'
#' # Due east, at the moment of departure
#' gc_bearing(43, -69, 43, -68)
#'
#' # A position has no bearing to itself
#' gc_bearing(43, -69, 43, -69)
#'
#' @export
gc_bearing <- function(lat1, lon1, lat2, lon2) {
  n <- max(length(lat1), length(lon1), length(lat2), length(lon2))
  lat1 <- rep_len(as.numeric(lat1), n)
  lon1 <- rep_len(as.numeric(lon1), n)
  lat2 <- rep_len(as.numeric(lat2), n)
  lon2 <- rep_len(as.numeric(lon2), n)

  d2r <- pi / 180
  phi1 <- lat1 * d2r
  phi2 <- lat2 * d2r
  dlam <- (lon2 - lon1) * d2r

  y <- sin(dlam) * cos(phi2)
  x <- cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dlam)
  out <- (atan2(y, x) / d2r) %% 360

  # atan2(0, 0) is 0, so coincident positions would otherwise report a bearing
  # of due north rather than admitting that they have none.
  missing <- is.na(lat1) | is.na(lon1) | is.na(lat2) | is.na(lon2)
  out[!missing & lat1 == lat2 & lon1 == lon2] <- NA_real_
  out[missing] <- NA_real_
  out
}

# The sphere every routine here works on. All three methods in `gc_distance()`
# scale by 111.12 km per degree (60 nmi x 1.852 km/nmi is exactly that), so
# there is only one radius to agree on.
gc_radius_km <- function() 111.12 / (pi / 180)

# Position reached by travelling `distance_km` from (lat, lon) on `bearing`.
# Not exported: it exists so that test geometry can be constructed exactly
# rather than by inverting `cross_track_distance()` numerically.
gc_destination <- function(lat, lon, bearing, distance_km) {
  d2r <- pi / 180
  phi1 <- lat * d2r
  lam1 <- lon * d2r
  theta <- bearing * d2r
  delta <- distance_km / gc_radius_km()

  phi2 <- asin(sin(phi1) * cos(delta) + cos(phi1) * sin(delta) * cos(theta))
  lam2 <- lam1 + atan2(
    sin(theta) * sin(delta) * cos(phi1),
    cos(delta) - sin(phi1) * sin(phi2)
  )

  tibble::tibble(lat = phi2 / d2r, lon = ((lam2 / d2r + 540) %% 360) - 180)
}

#' Distance methods available
#'
#' The method names [gc_distance()] and [segment_survey()] accept, and what each
#' one means.
#'
#' @return A tibble with columns `method`, `aliases`, and `description`.
#'
#' @references
#' Kenney, R.D. and Winn, H.E. (1986) Cetacean high-use habitats of the
#' northeast United States continental shelf. *Fishery Bulletin* 84(2):345-357.
#'
#' Sinnott, R.W. (1984) Virtues of the haversine. *Sky and Telescope* 68(2):159.
#'
#' @examples
#' dist_methods()
#'
#' @export
dist_methods <- function() {
  tibble::tibble(
    method = c("haversine", "becker", "kenney"),
    aliases = c("", "eab", "rdk"),
    description = c(
      "Haversine on a 111.12 km/degree sphere; stable at short range. Default.",
      "Becker's segchopr fn.grcirclkm: spherical law of cosines, 60 nmi/degree x 1.852 km/nmi.",
      "Kenney and Winn (1986): spherical law of cosines, 111.12 km/degree. Identical to Becker."
    )
  )
}

# Fold the historical short names onto the canonical ones.
dist_method_canonical <- function(method) {
  switch(method,
    eab = "becker",
    rdk = "kenney",
    method
  )
}


#' Accumulate point-to-point survey effort
#'
#' Computes the along-track distance from each record to the next within a
#' survey line, counting only the intervals where the aircraft was on effort at
#' both ends.
#'
#' Effort is attributed to the *first* record of each pair, so the last record
#' of a line has `pt2pt.effort` of `0`. Intervals with an off-effort endpoint
#' are `0` rather than `NA`, so that segment effort sums are well defined
#' without needing `na.rm`.
#'
#' @param dat A data frame with `LATITUDE`, `LONGITUDE`, `OnOff.Effort`, and the
#'   grouping columns named in `by`. Records must already be in survey order;
#'   [read_narwc()] does not sort, so sort by `DATE`/`FILEID`/`EVENTNO`
#'   beforehand if you are unsure.
#' @param by Character vector of columns identifying a continuous survey line.
#'   Defaults to `c("DATE", "FILEID", "LEGNO3")`, the line-occupation identifier
#'   produced by [make_leg_id()], qualified by the survey day.
#'
#'   `DATE` is in the default because `LEGNO3` only increments when `LEGNO`
#'   *changes*. If the last line of one day and the first line of the next share
#'   a `LEGNO`, the two occupations differ in nothing but `FILEID` — and some
#'   extracts carry a constant `FILEID`, in which case the days merge and the
#'   ferry between them is counted as on-effort track. That failure is silent:
#'   no warning, no `NA`, just an effort total that can be many times too large,
#'   and since effort is the denominator of density, a density proportionally
#'   too low. Drop `DATE` only for a frame you know occupies a single day.
#' @param method Distance method passed to [gc_distance()]: `"haversine"`
#'   (default), `"becker"`, or `"kenney"`. Ignored when `source = "recorded"`.
#' @param source Where the distance for each interval comes from.
#'   `"computed"` (default) is the great circle between consecutive positions.
#'   `"recorded"` uses `TRKDIST`, the distance the receiver itself measured
#'   since the previous fix, in metres.
#'
#'   `"recorded"` is the better measure where it exists. The handbook makes the
#'   point itself (8.A.10): the farther apart the fixes, the less a straight
#'   line between them reconstructs the track that was actually flown. A
#'   computed distance is a chord; the recorded one followed the aircraft.
#'   The two agree closely on a straight line and diverge on a turn, so a large
#'   gap between them is a sign of coarse fixes rather than of an error.
#'
#'   `TRKDIST` measures *back* to the previous fix, and effort is attributed
#'   forward to the first record of a pair, so the interval takes the next
#'   record's reading. Off-effort endpoints and line boundaries are handled
#'   exactly as for `"computed"`, which means a reading that spans the ferry
#'   between two lines is discarded rather than counted.
#'
#' @return `dat` with two columns added or replaced:
#'   \describe{
#'     \item{`pt2pt.effort`}{Distance in km from this record to the next
#'       on-effort record within the same line; `0` at line ends and across
#'       off-effort gaps.}
#'     \item{`Effort`}{Total on-effort distance of the line this record belongs
#'       to, repeated on every record of the line.}
#'   }
#'
#' @references
#' Kenney, R.D. and Winn, H.E. (1986) Cetacean high-use habitats of the
#' northeast United States continental shelf. *Fishery Bulletin* 84(2):345-357.
#' Effort is accumulated here as they describe it: "for any pair of successive
#' positions, the length of track line between the points" summed over the
#' qualifying records.
#'
#' @seealso [gc_distance()], [make_leg_id()]
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' dat <- flag_effort(make_leg_id(read_narwc(path)))
#' dat <- point_to_point_effort(dat)
#' sum(dat$pt2pt.effort)
#'
#' @export
point_to_point_effort <- function(dat,
                                  by = c("DATE", "FILEID", "LEGNO3"),
                                  method = c("haversine", "becker", "kenney",
                                             "eab", "rdk"),
                                  source = c("computed", "recorded")) {
  method <- dist_method_canonical(match.arg(method))
  source <- match.arg(source)
  require_columns(dat, c("LATITUDE", "LONGITUDE", "OnOff.Effort", by))
  if (source == "recorded") {
    require_columns(dat, "TRKDIST")
  }

  if (is_empty_df(dat)) {
    dat$pt2pt.effort <- numeric(0)
    dat$Effort <- numeric(0)
    return(dat)
  }

  out <- dplyr::group_by(dat, dplyr::across(dplyr::all_of(by)))
  out <- dplyr::mutate(
    out,
    .next_lat = dplyr::lead(.data$LATITUDE),
    .next_lon = dplyr::lead(.data$LONGITUDE),
    .next_on  = dplyr::lead(.data$OnOff.Effort),
    # `TRKDIST` measures back to the previous fix, while effort is attributed
    # forward to the first record of each pair, so the interval from this
    # record to the next carries the *next* record's reading.
    .step = if (source == "recorded") {
      dplyr::lead(.data$TRKDIST) / 1000
    } else {
      gc_distance(
        .data$LATITUDE, .data$LONGITUDE,
        dplyr::lead(.data$LATITUDE), dplyr::lead(.data$LONGITUDE),
        method = method
      )
    },
    pt2pt.effort = ifelse(
      !is.na(.data$.next_on) & .data$OnOff.Effort == 1 & .data$.next_on == 1,
      .data$.step,
      0
    ),
    pt2pt.effort = ifelse(is.na(.data$pt2pt.effort), 0, .data$pt2pt.effort),
    Effort = sum(.data$pt2pt.effort),
    .keep = "all"
  )

  out <- dplyr::ungroup(out)
  out <- dplyr::select(
    out, -dplyr::all_of(c(".next_lat", ".next_lon", ".next_on", ".step"))
  )
  class(out) <- unique(c(setdiff(class(dat), class(out)), class(out)))
  out
}
