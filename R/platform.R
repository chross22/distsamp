## What "aerial" and "vessel" mean, in one place.
##
## Every platform-dependent choice in this package resolves through here:
## which effort criteria apply, which right-angle distance sources exist, and
## which `PLATFORM_KIND` label a record must carry to be kept. Scattering those
## decisions across prepare, segment and diagnose is how they drift apart, and
## a survey segmented under one platform's effort rules and another's distance
## geometry produces numbers that look entirely reasonable.

#' The platforms this package can segment
#'
#' `distsamp` was aerial by construction and is now aerial by default. A
#' shipboard survey differs in three ways that matter, and this is where all
#' three are written down.
#'
#' @section What changes with the platform:
#' \describe{
#'   \item{Effort criteria}{The handbook's altitude ceiling (8.A.1) is an
#'     aircraft criterion. A vessel record carries no `ALT`, and a missing
#'     value fails a criterion, so the ceiling puts every vessel record off
#'     effort at any height — `max_alt_m = Inf` does not rescue them. The
#'     vessel defaults drop the criterion instead
#'     (`narwcr::flag_effort(max_alt_m = NULL)`). Sea state and visibility
#'     apply to both, and are left alone.}
#'   \item{Right-angle distance sources}{`"angle"` is \eqn{h/\tan\theta} from
#'     an aircraft altitude, and the `"strip"` code books are the Skymaster's
#'     and the AT-11's (8.A.31). Neither means anything on a vessel, so the
#'     vessel default is `"exact"` alone — a sighting position projected onto
#'     the track, which is geometry rather than platform. See
#'     [sighting_distances()].}
#'   \item{Which records are kept}{`narwcr::classify_platform()` labels each
#'     stretch from its median speed. The platform names the label to keep.}
#' }
#'
#' @section What does not change:
#' `LEGTYPE` 5 and 6 mark shipboard records (8.A.21), but they mark a *platform
#' of opportunity* — a ship that recorded what it saw while going somewhere.
#' That is not a designed line-transect, and counting it as effort would put
#' unsearched track into the denominator of a density estimate. So the vessel
#' defaults keep `legtype_on_effort = 2`, a designated census line, exactly as
#' the aerial ones do. A dedicated shipboard line-transect survey codes its
#' lines `LEGTYPE = 2` and needs nothing here; a POP file is not a distance
#' sampling dataset and no argument to this package makes it one.
#'
#' Segmentation itself is platform-free. Great-circle distance between
#' consecutive fixes, splitting at breaks in effort, and cutting a track into
#' lengths are all geometry, and a ship's track segments the same way a
#' plane's does.
#'
#' @section Naming:
#' `"vessel"` is the documented spelling, because it is the `PLATFORM_KIND`
#' level the filter actually compares against — nothing is translated on the
#' way through. `"ship"` is accepted everywhere `"vessel"` is, and resolves to
#' it.
#'
#' @param platform `"aerial"` (default), `"vessel"`, or `"ship"` as a synonym
#'   for `"vessel"`.
#'
#' @return A list with `platform`, `kind` (the `PLATFORM_KIND` level to keep),
#'   `effort_args` (for `narwcr::flag_effort()`), and `distance_sources` (for
#'   [sighting_distances()]).
#'
#' @seealso [prepare_survey()], [segment_survey()], [sighting_distances()],
#'   `narwcr::classify_platform()`
#'
#' @examples
#' platform_defaults("aerial")
#'
#' # A vessel drops the altitude ceiling and loses the aircraft distance
#' # sources
#' platform_defaults("vessel")
#'
#' # "ship" is the same thing
#' identical(platform_defaults("ship"), platform_defaults("vessel"))
#'
#' @export
platform_defaults <- function(platform = c("aerial", "vessel", "ship")) {
  platform <- resolve_platform(platform)
  if (platform == "aerial") {
    list(
      platform = "aerial",
      kind = "aerial",
      effort_args = list(),
      distance_sources = c("angle", "exact", "strip")
    )
  } else {
    list(
      platform = "vessel",
      kind = "vessel",
      # NULL, not Inf: a missing ALT fails any ceiling. See
      # `narwcr::flag_effort()`, "A criterion that does not apply".
      effort_args = list(max_alt_m = NULL),
      distance_sources = "exact"
    )
  }
}

# The canonical platform name. `match.arg()` cannot do this on its own, because
# "ship" and "vessel" must both be accepted and must not be two answers.
resolve_platform <- function(platform, allow_all = FALSE,
                             call = rlang::caller_env()) {
  allowed <- c("aerial", "vessel", "ship", if (allow_all) "all")
  # The default is the full formals vector, as `match.arg()` expects.
  if (length(platform) > 1L) platform <- platform[[1L]]
  platform <- as.character(platform)
  if (length(platform) != 1L || is.na(platform)) {
    cli_abort_bad_arg("platform", paste(platform, collapse = ", "),
                      allowed, call = call)
  }
  if (!platform %in% allowed) {
    cli_abort_bad_arg("platform", platform, allowed, call = call)
  }
  if (platform == "ship") "vessel" else platform
}

# The distance sources this platform can supply, as an error rather than a
# silent drop. Asking for a declination angle on a vessel is not a preference
# that can be honoured partway - it is a measurement that does not exist, and
# `sighting_distances()` would leave the column NA and report nothing.
check_distance_sources <- function(sources, platform,
                                   call = rlang::caller_env()) {
  if (platform != "vessel") return(invisible(sources))
  aerial_only <- intersect(sources, c("angle", "strip"))
  if (!length(aerial_only)) return(invisible(sources))
  rlang::abort(
    paste0(
      "`sources` asks for ", paste0("\"", aerial_only, "\"", collapse = " and "),
      " on a vessel. ",
      if ("angle" %in% aerial_only) {
        paste0(
          "A declination angle is an altitude divided by a tangent, and a ",
          "vessel has no altitude. "
        )
      } else "",
      if ("strip" %in% aerial_only) {
        paste0(
          "The STRIP code books are the Skymaster's and the AT-11's ",
          "(handbook 8.A.31), both aircraft. "
        )
      } else "",
      "Use \"exact\", which projects a recorded sighting position onto the ",
      "track and is geometry rather than platform. See `platform_defaults()`."
    ),
    call = call
  )
}

# Effort flags, with a readable failure when the installed narwcr predates
# skippable criteria.
#
# Dropping a criterion is `narwcr::flag_effort(max_alt_m = NULL)`, and an older
# narwcr computes `dat$ALT < NULL` instead - a zero-length logical, which the
# internal `stopifnot(length(ok) == n)` reports as `length(ok) == n is not
# TRUE`. That is a true statement about narwcr's internals and no help at all
# about the pin that caused it. This package's callers pin by commit, so a
# narwcr from before this feature is an ordinary thing to be running.
flag_effort_for_platform <- function(dat, effort_args,
                                     call = rlang::caller_env()) {
  drops <- vapply(effort_args, is.null, logical(1))
  if (any(drops) && !narwcr_can_drop_criteria()) {
    rlang::abort(
      paste0(
        "The installed narwcr cannot drop an effort criterion, which this ",
        "platform needs: it passes ",
        paste0("`", names(effort_args)[drops], " = NULL`", collapse = ", "),
        ". Upgrade narwcr, or pass an explicit threshold in `effort_args` - ",
        "noting that a missing value fails a criterion, so no ceiling lets a ",
        "record with no ALT through."
      ),
      call = call
    )
  }
  do.call(narwcr::flag_effort, c(list(dat), effort_args))
}

# Asked once per session, against a two-row frame rather than the formals: the
# argument has always been there, and it is only what narwcr does with a NULL
# that changed.
narwcr_can_drop_criteria <- local({
  answer <- NULL
  function() {
    if (!is.null(answer)) return(answer)
    probe <- data.frame(LEGTYPE = c(2, 2), ALT = NA_real_)
    ok <- tryCatch({
      out <- suppressMessages(narwcr::flag_effort(probe, max_alt_m = NULL))
      identical(as.integer(out$OnOff.Effort), c(1L, 1L))
    }, error = function(e) FALSE)
    answer <<- isTRUE(ok)
    answer
  }
})


# The speed band a platform is expected to be moving in, for the checks that
# ask "is this the platform you said it was?". Bounds are knots, and match
# `narwcr::classify_platform()`'s thresholds so the two never disagree.
platform_speed_band <- function(platform) {
  switch(platform,
    aerial = list(min = 40, max = Inf,
                  what = "a survey aircraft", several = "airframes"),
    vessel = list(min = 2, max = 40,
                  what = "a surveying vessel", several = "hulls")
  )
}
