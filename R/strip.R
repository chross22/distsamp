#' NARWC STRIP right-angle distance code books
#'
#' `STRIP` encodes the right-angle distance of a sighting from the track-line as
#' an *interval*, not a point. Two different code books are in use, and which
#' applies depends on the survey programme, the date, and the aircraft.
#'
#' @section The two schemes:
#' \describe{
#'   \item{`"cetap"`}{The original scheme (handbook 8.A.31). Codes `1,2` cover
#'     0-1/4 nmi; that closest interval was subsequently split at 1/8 nmi, giving
#'     `3,4` and `5,6`. Both forms occur in the archive, so `1,2` is kept as the
#'     wider unsplit bin rather than being silently merged. Intervals beyond
#'     1 nmi differ by aircraft: the AT-11 has a single open bin above 1 nmi,
#'     the Skymaster splits at 2 nmi.}
#'   \item{`"nlpsc"`}{Defined for the NLPSC / Massachusetts CEC surveys that
#'     began in October 2011, flown with a Skymaster. Different breakpoints
#'     entirely, running out to 4 nmi.}
#' }
#'
#' Odd codes are the left (port) side of the track, even codes the right
#' (starboard). Code `0` means directly on the track-line and applies only to
#' the AT-11, because of the Skymaster's restricted downward visibility.
#'
#' @section Open-ended bins:
#' The top bin of every scheme is open (`>1`, `>2`, `>4` nmi), so `distend` is
#' `Inf`. A detection function cannot be fitted to an unbounded bin: you must
#' truncate. `detection_data()` (not yet implemented) does this for you when it lands; until then, truncate before fitting.
#'
#' @param scheme `"cetap"` or `"nlpsc"`.
#' @param platform `"skymaster"` or `"at-11"`. Only affects the `"cetap"`
#'   scheme, where the bins above 1 nmi differ by aircraft.
#' @param units `"m"` (default), `"km"`, or `"nmi"`.
#'
#' @return A tibble with `code`, `side`, `distbegin`, `distend`.
#'
#' @references
#' Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database: A
#' Guide for Users and Contributors, Version 8*, section 8.A.31. NARWC Reference
#' Document 2023-01.
#'
#' Kenney, R.D. and Scott, G.P. (1981) Calibration of the Beechcraft AT-11
#' forward observation bubble for population estimation purposes. In CETAP,
#' *A Characterization of Marine Mammals and Turtles in the Mid- and
#' North-Atlantic Areas of the U.S. Outer Continental Shelf, Annual Report for
#' 1979.* Bureau of Land Management, Washington, DC.
#'
#' @examples
#' narwc_strip_bins("nlpsc")
#' narwc_strip_bins("cetap", platform = "at-11", units = "nmi")
#'
#' @export
narwc_strip_bins <- function(scheme = c("cetap", "nlpsc"),
                             platform = c("skymaster", "at-11"),
                             units = c("m", "km", "nmi")) {
  scheme <- match.arg(scheme)
  platform <- match.arg(platform)
  units <- match.arg(units)

  # Handbook 8.A.31, in nautical miles.
  if (scheme == "cetap") {
    pairs <- list(
      c(0, 0, 0),          # on the track-line; AT-11 only
      c(1, 0, 1 / 4),      # the original unsplit closest interval
      c(3, 0, 1 / 8),      # ... subsequently split here
      c(5, 1 / 8, 1 / 4),
      c(7, 1 / 4, 1 / 2),
      c(9, 1 / 2, 3 / 4),
      c(11, 3 / 4, 1)
    )
    pairs <- c(pairs, if (platform == "at-11") {
      list(c(13, 1, Inf))
    } else {
      list(c(13, 1, 2), c(15, 2, Inf))
    })
  } else {
    pairs <- list(
      c(1, 0, 1 / 8),
      c(3, 1 / 8, 1 / 4),
      c(5, 1 / 4, 1 / 2),
      c(7, 1 / 2, 1),
      c(9, 1, 2),
      c(11, 2, 4),
      c(13, 4, Inf)
    )
  }

  out <- do.call(rbind, lapply(pairs, function(p) {
    odd <- p[1]
    if (odd == 0) {
      return(data.frame(code = 0, side = "on-track", distbegin = 0, distend = 0))
    }
    data.frame(
      code = c(odd, odd + 1),
      side = c("left", "right"),
      distbegin = p[2], distend = p[3]
    )
  }))

  scale <- switch(units, nmi = 1, m = 1852, km = 1.852)
  out$distbegin <- out$distbegin * scale
  out$distend <- out$distend * scale

  tibble::as_tibble(out[order(out$code), ])
}


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
