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
#'   Defaults to `c("FILEID", "LEGNO3")`, the line-occupation identifier
#'   produced by [make_leg_id()].
#' @param method Distance method passed to [gc_distance()]: `"haversine"`
#'   (default), `"becker"`, or `"kenney"`.
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
                                  by = c("FILEID", "LEGNO3"),
                                  method = c("haversine", "becker", "kenney",
                                             "eab", "rdk")) {
  method <- dist_method_canonical(match.arg(method))
  require_columns(dat, c("LATITUDE", "LONGITUDE", "OnOff.Effort", by))

  if (is_empty_df(dat)) {
    dat$pt2pt.effort <- numeric(0)
    dat$Effort <- numeric(0)
    return(dat)
  }

  out <- dplyr::mutate(
    dplyr::group_by(dat, dplyr::across(dplyr::all_of(by))),
    .next_lat = dplyr::lead(.data$LATITUDE),
    .next_lon = dplyr::lead(.data$LONGITUDE),
    .next_on  = dplyr::lead(.data$OnOff.Effort),
    pt2pt.effort = ifelse(
      !is.na(.data$.next_on) & .data$OnOff.Effort == 1 & .data$.next_on == 1,
      gc_distance(
        .data$LATITUDE, .data$LONGITUDE,
        .data$.next_lat, .data$.next_lon,
        method = method
      ),
      0
    ),
    pt2pt.effort = ifelse(is.na(.data$pt2pt.effort), 0, .data$pt2pt.effort),
    Effort = sum(.data$pt2pt.effort),
    .keep = "all"
  )

  out <- dplyr::ungroup(out)
  out <- dplyr::select(out, -dplyr::all_of(c(".next_lat", ".next_lon", ".next_on")))
  class(out) <- unique(c(setdiff(class(dat), class(out)), class(out)))
  out
}
