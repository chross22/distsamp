#' Get a NARWC extract ready to segment
#'
#' Runs the steps between reading a file and segmenting it, in the order they
#' have to happen: line occupations, line state, platform, effort. Each is
#' exported and can be run by hand; this exists because the order is not
#' obvious and getting it wrong is quiet.
#'
#' `prepare_aerial()` is the same function with `platform = "aerial"` in its
#' name rather than its arguments. It takes the platform argument too, so
#' existing code keeps working.
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
#' @section Aerial or vessel:
#' The platform decides which records survive the filter *and* which effort
#' criteria apply. Those two have to move together: the handbook's altitude
#' ceiling is an aircraft criterion, and a vessel record carries no `ALT`, so
#' a survey filtered to its vessel records and then judged on the aerial
#' criteria is a survey with no effort at all. `platform = "vessel"` sets both,
#' from [platform_defaults()], and anything you name in `effort_args` still
#' wins over what it chose.
#'
#' `"ship"` is accepted as a synonym for `"vessel"`. `"all"` classifies without
#' filtering and leaves the effort criteria at the aerial defaults, because on
#' a mixed file there is no one right answer — it is for looking at what the
#' filter would do, not for feeding a model.
#'
#' @section What it deliberately does not do:
#' Anything that is an assertion about a particular file rather than a fact
#' about NARWC data. Mapping a declination angle out of a column the handbook
#' does not name, and correcting an altitude recorded in feet, are claims only
#' you can make. The first goes before this call; the second goes in `correct`,
#' because where it happens changes what it does:
#'
#' ```r
#' dat <- narwcr::angles_from_declination(dat, "Decl_Angle", "Left_or_Right")
#'
#' air <- prepare_survey(dat, correct = function(x) {
#'   feet <- !is.na(x$ALT) & x$DATE >= as.Date("2024-01-01")
#'   x$ALT[feet] <- x$ALT[feet] * 0.3048
#'   x
#' })
#' ```
#'
#' `correct` runs after the platform filter and before effort is flagged, which
#' is the only place it can go: applying it earlier scales ship altitudes that
#' were already metres, and applying it later leaves every record failing the
#' altitude ceiling that `flag_effort()` has already tested.
#'
#' @param dat A NARWC data frame from `narwcr::read_narwc()`.
#' @param platform Which platform to keep: `"aerial"` (default), `"vessel"`
#'   (or `"ship"`, the same thing), or `"all"` to classify without filtering.
#'   See [platform_defaults()] for what each one changes.
#' @param fill_legstage Reconstruct the line state where no `LEGSTAGE` was
#'   written? Default `TRUE`. See `narwcr::fill_legstage()`.
#' @param correct A function applied to the filtered frame *before* effort is
#'   flagged, or `NULL`. This is where a correction that only applies to the
#'   records being kept goes — an altitude recorded in feet, most often. It has
#'   to happen here: `flag_effort()` reads `ALT`, so correcting afterwards
#'   leaves every record failing the altitude ceiling, and correcting before
#'   the platform filter scales ship altitudes that were already metres.
#' @param effort_args Named list passed to `narwcr::flag_effort()`, for a
#'   programme whose criteria differ from the defaults. Merged over the
#'   platform's own defaults, so naming an argument here overrides it.
#' @param quiet Suppress the running commentary. Default `FALSE`.
#'
#' @return `dat` with `LEGNO2`, `LEGNO3`, `LEGSTAGE_FILLED`, `PLATFORM_KIND`
#'   and `OnOff.Effort` added, filtered to `platform`.
#'
#' @seealso [platform_defaults()] for what a platform decides,
#'   [diagnose_pipeline()] to check the result, [plot_survey()] to look
#'   at it, [segment_survey()] for what comes next.
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' dat <- narwcr::read_narwc(path, quiet = TRUE)
#' air <- prepare_survey(dat, quiet = TRUE)
#' table(air$PLATFORM_KIND)
#'
#' # The shipboard records of the same file, judged on criteria an aircraft
#' # altitude plays no part in
#' sea <- prepare_survey(dat, platform = "vessel", quiet = TRUE)
#' table(sea$PLATFORM_KIND)
#'
#' @export
prepare_survey <- function(dat, platform = c("aerial", "vessel", "ship", "all"),
                           fill_legstage = TRUE, correct = NULL,
                           effort_args = list(), quiet = FALSE) {
  platform <- resolve_platform(platform, allow_all = TRUE)
  stopifnot(is.data.frame(dat))
  stopifnot(is.list(effort_args))
  n_in <- nrow(dat)

  # "all" keeps both kinds, so no platform's criteria are the right ones and
  # the aerial defaults stand. Filtering is what licenses changing them.
  if (platform != "all") {
    defaults <- platform_defaults(platform)
    # The caller's arguments win, name by name. `modifyList()` would drop a
    # `max_alt_m = NULL` the caller passed explicitly, which is the one value
    # a vessel most needs to be able to set.
    keep_names <- setdiff(names(defaults$effort_args), names(effort_args))
    effort_args <- c(effort_args, defaults$effort_args[keep_names])
  }

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
    if (platform != "all") {
      keep <- !is.na(dat$PLATFORM_KIND) &
        dat$PLATFORM_KIND == defaults$kind
      # After make_leg_id(), never before: filtering first makes two
      # occupations of one line adjacent and merges them.
      dat <- dat[keep, , drop = FALSE]
      if (!quiet) {
        rlang::inform(paste0(
          "Kept ", format(sum(keep), big.mark = ","), " of ",
          format(n_in, big.mark = ","), " records as ", defaults$kind, "."
        ))
      }
    }
  } else if (platform != "all") {
    rlang::warn(paste0(
      "No platform check: it needs LATITUDE, LONGITUDE and TIME. Every record ",
      "has been kept, so anything in this file that is not ", defaults$kind,
      " will be segmented as though it were."
    ))
  }

  # Between the filter and the effort flags, because that is the only place a
  # correction to a criterion column can go and be seen by the criteria.
  if (!is.null(correct)) {
    stopifnot(is.function(correct))
    n_before <- nrow(dat)
    dat <- correct(dat)
    stopifnot(is.data.frame(dat), nrow(dat) == n_before)
    if (!quiet) rlang::inform("Applied `correct()` to the filtered records.")
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


#' @rdname prepare_survey
#' @export
prepare_aerial <- function(dat, platform = c("aerial", "vessel", "ship", "all"),
                           fill_legstage = TRUE, correct = NULL,
                           effort_args = list(), quiet = FALSE) {
  prepare_survey(dat, platform = platform, fill_legstage = fill_legstage,
                 correct = correct, effort_args = effort_args, quiet = quiet)
}
