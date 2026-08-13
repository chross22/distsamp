#' Get a NARWC extract ready to segment
#'
#' Runs the steps between reading a file and segmenting it, in the order they
#' have to happen: line occupations, line state, platform, effort. Each is
#' exported and can be run by hand; this exists because the order is not
#' obvious and getting it wrong is quiet.
#'
#' @section The order, and why it is not obvious:
#' \describe{
#'   \item{`make_leg_id()` first}{Everything downstream groups by `LEGNO3`.}
#'   \item{`fill_legstage()` second}{It needs `LEGNO3` to know where an
#'     occupation ends, and it must run before effort, because a right-angle
#'     distance needs `LEGSTAGE == 2` (handbook 8.A.31). On a real archive
#'     1,928 of 2,280 on-effort census sightings were ineligible without it —
#'     for a code recorded only when it changed.}
#'   \item{`classify_platform()` third, and the filter *after* `make_leg_id()`}{
#'     Removing records before occupations are built makes two occupations of
#'     one line adjacent, so they merge and the ferry between them becomes
#'     survey effort. Measured at 224.5 km where 4.4 km was right.}
#'   \item{`flag_effort()` last}{It reads `LEGTYPE`, `LEGSTAGE`, `ALT`,
#'     `BEAUFORT` and `VISIBLTY`, so anything that corrects those has to have
#'     happened already.}
#' }
#'
#' @section What it deliberately does not do:
#' Anything that is an assertion about a particular file rather than a fact
#' about NARWC data. Mapping a declination angle out of a column the handbook
#' does not name, and correcting an altitude recorded in feet, are both claims
#' only you can make — do them on the frame before calling this:
#'
#' ```r
#' dat <- narwcr::angles_from_declination(dat, "Decl_Angle", "Left_or_Right")
#' air <- prepare_aerial(dat)
#' air$ALT[air$DATE >= as.Date("2024-01-01")] <-
#'   air$ALT[air$DATE >= as.Date("2024-01-01")] * 0.3048
#' ```
#'
#' The altitude correction goes *after* this call, not before: only the aerial
#' records are in feet, and applying it to a mixed frame scales ship altitudes
#' that were already metres.
#'
#' @param dat A NARWC data frame from `narwcr::read_narwc()`.
#' @param platform Which platform to keep: `"aerial"` (default), or `"all"` to
#'   classify without filtering. This package is aerial by construction — its
#'   effort criteria and `perp_distance()` both assume an aircraft.
#' @param fill_legstage Reconstruct the line state where no `LEGSTAGE` was
#'   written? Default `TRUE`. See `narwcr::fill_legstage()`.
#' @param effort_args Named list passed to `narwcr::flag_effort()`, for a
#'   programme whose criteria differ from the CETAP defaults.
#' @param quiet Suppress the running commentary. Default `FALSE`.
#'
#' @return `dat` with `LEGNO2`, `LEGNO3`, `LEGSTAGE_FILLED`, `PLATFORM_KIND`
#'   and `OnOff.Effort` added, filtered to `platform`.
#'
#' @seealso [diagnose_pipeline()] to check the result, [plot_survey()] to look
#'   at it, [segment_survey()] for what comes next.
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' dat <- narwcr::read_narwc(path, quiet = TRUE)
#' air <- prepare_aerial(dat, quiet = TRUE)
#' table(air$PLATFORM_KIND)
#'
#' @export
prepare_aerial <- function(dat, platform = c("aerial", "all"),
                           fill_legstage = TRUE, effort_args = list(),
                           quiet = FALSE) {
  platform <- match.arg(platform)
  stopifnot(is.data.frame(dat))
  n_in <- nrow(dat)

  dat <- narwcr::make_leg_id(dat, quiet = quiet)

  if (fill_legstage && "LEGSTAGE" %in% names(dat)) {
    dat <- narwcr::fill_legstage(dat, quiet = quiet)
  }

  if (all(c("LATITUDE", "LONGITUDE", "TIME") %in% names(dat))) {
    dat$PLATFORM_KIND <- narwcr::classify_platform(dat)
    if (!quiet) {
      counts <- table(dat$PLATFORM_KIND, useNA = "ifany")
      rlang::inform(paste0(
        "Platform, from the speed between fixes: ",
        paste(names(counts), unname(counts), sep = " ", collapse = ", "), "."
      ))
    }
    if (identical(platform, "aerial")) {
      keep <- !is.na(dat$PLATFORM_KIND) & dat$PLATFORM_KIND == "aerial"
      # After make_leg_id(), never before: filtering first makes two
      # occupations of one line adjacent and merges them.
      dat <- dat[keep, , drop = FALSE]
      if (!quiet) {
        rlang::inform(paste0(
          "Kept ", format(sum(keep), big.mark = ","), " of ",
          format(n_in, big.mark = ","), " records as aerial."
        ))
      }
    }
  } else if (identical(platform, "aerial")) {
    rlang::warn(paste0(
      "No platform check: it needs LATITUDE, LONGITUDE and TIME. Every record ",
      "has been kept, so a shipboard survey in this file will be segmented as ",
      "though it were flown."
    ))
  }

  if (!"OnOff.Effort" %in% names(dat)) {
    dat <- do.call(narwcr::flag_effort, c(list(dat), effort_args))
  }

  if (!quiet && "OnOff.Effort" %in% names(dat)) {
    rlang::inform(paste0(
      format(sum(dat$OnOff.Effort == 1, na.rm = TRUE), big.mark = ","), " of ",
      format(nrow(dat), big.mark = ","), " records on effort. ",
      "`diagnose_pipeline()` says which criterion excluded the rest."
    ))
  }
  dat
}
