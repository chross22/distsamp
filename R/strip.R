
#' Convert STRIP codes to distance intervals
#'
#' Resolves each `STRIP` code to the right-angle distance interval it stands
#' for, and the side of the track it was on.
#'
#' @section Choosing the scheme:
#' With `scheme = "auto"` (the default) the scheme is chosen from `date`: the
#' NLPSC / Mass CEC breakpoints for October 2011 onwards, the CETAP ones before.
#' That is a reasonable default but not a guarantee — a survey flown after 2011
#' under the older protocol would be misread — so pass `scheme` explicitly when
#' you know which applies. With no `date` and no `scheme`, this errors rather
#' than guess.
#'
#' @section The Skymaster blind spot:
#' Handbook 8.A.31 notes that the Skymaster's restricted downward visibility
#' means CETAP-era distances from that aircraft "are actually measured from
#' about 1/8 mile to either side of the survey line". The strip boundaries do
#' not record this, so distances near zero are not what they appear: the region
#' under the aircraft was never searched. Set `left_truncation = TRUE` to shift
#' the innermost bins accordingly, and see `detection_data()` (not yet implemented) for fitting with a
#' left truncation, which is the statistically correct treatment.
#'
#' @param strip Integer vector of `STRIP` codes.
#' @param platform `"skymaster"` (default) or `"at-11"`.
#' @param scheme `"auto"`, `"cetap"`, or `"nlpsc"`.
#' @param date Vector of survey dates, used when `scheme = "auto"`.
#' @param units `"m"` (default), `"km"`, or `"nmi"`.
#' @param left_truncation Apply the Skymaster blind-spot offset? Default `FALSE`.
#'
#' @return A tibble with one row per input: `distbegin`, `distend`, `side`,
#'   `scheme`.
#'
#' @seealso [narwc_strip_bins()], [sighting_distances()]
#'
#' @examples
#' strip_distance(c(5, 6, 13), scheme = "nlpsc")
#'
#' # Same codes, different era, different distances
#' strip_distance(c(5, 6, 13), scheme = "cetap")
#'
#' @export
strip_distance <- function(strip,
                           platform = c("skymaster", "at-11"),
                           scheme = c("auto", "cetap", "nlpsc"),
                           date = NULL,
                           units = c("m", "km", "nmi"),
                           left_truncation = FALSE) {
  platform <- match.arg(platform)
  scheme <- match.arg(scheme)
  units <- match.arg(units)

  strip <- as.integer(strip)
  n <- length(strip)

  if (scheme == "auto") {
    if (is.null(date)) {
      rlang::abort(paste0(
        "`scheme = \"auto\"` needs `date` to choose between the CETAP and ",
        "NLPSC code books. Pass `date`, or name the scheme explicitly."
      ))
    }
    date <- as.Date(rep_len(date, n))
    which_scheme <- ifelse(!is.na(date) & date >= as.Date("2011-10-01"),
                           "nlpsc", "cetap")
  } else {
    which_scheme <- rep(scheme, n)
  }

  out <- tibble::tibble(
    distbegin = rep(NA_real_, n), distend = rep(NA_real_, n),
    side = rep(NA_character_, n), scheme = which_scheme
  )

  for (sc in unique(stats::na.omit(which_scheme))) {
    bins <- narwc_strip_bins(sc, platform = platform, units = units)
    i <- which(which_scheme == sc)
    m <- match(strip[i], bins$code)
    out$distbegin[i] <- bins$distbegin[m]
    out$distend[i] <- bins$distend[m]
    out$side[i] <- bins$side[m]
  }

  if (left_truncation && platform == "skymaster") {
    # The inner 1/8 nmi was not searched, so a bin starting at zero really
    # starts there.
    offset <- (1 / 8) * switch(units, nmi = 1, m = 1852, km = 1.852)
    inner <- !is.na(out$distbegin) & out$distbegin < offset & out$distend > offset
    out$distbegin[inner] <- offset
    gone <- !is.na(out$distend) & out$distend <= offset & out$distend > 0
    out$distbegin[gone] <- NA_real_
    out$distend[gone] <- NA_real_
  }

  out
}
