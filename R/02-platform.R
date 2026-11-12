## What "aerial" and "vessel" mean, in one place.
##
## Every platform-dependent choice in this package is made here: which effort
## criteria apply, which right-angle distance sources exist, and which
## `PLATFORM_KIND` label a record must carry to be kept. Keeping them together
## stops prepare, segment and diagnose from disagreeing. A survey segmented
## under one platform's effort rules and another's distance sources gives
## numbers that look reasonable and are wrong.

#' The platforms this package can segment
#'
#' `distsamp` is aerial by default. A shipboard survey differs in three ways
#' that matter, and this is where all three are set.
#'
#' @section What changes with the platform:
#' \describe{
#'   \item{Effort criteria}{The handbook's altitude ceiling (8.A.1) is an
#'     aircraft criterion. It cannot be widened to suit a ship: a missing value
#'     fails a criterion, so a record with no `ALT` fails at any ceiling, and
#'     `max_alt_m = Inf` does not help. The vessel defaults drop the criterion
#'     instead (`narwcr::flag_effort(max_alt_m = NULL)`). Sea state and
#'     visibility apply to both platforms and are unchanged.
#'
#'   The effect depends on the file, so measure it. Some programmes leave
#'   `ALT` empty on vessel records, and every such record is excluded. Others
#'   write the observer's eye height there, which passes an aircraft's ceiling
#'   and hides the problem until the empty records go missing. On one real
#'   extract of 1,037,180 vessel records, 338,562 had no `ALT` — 32% of the
#'   vessel effort, and 277 of 741 eligible sightings.}
#'   \item{Right-angle distance sources}{`"angle"` is \eqn{h/\tan\theta} from
#'     an aircraft altitude, and the `"strip"` code books are the Skymaster's
#'     and the AT-11's (8.A.31). Neither exists on a vessel, so the vessel
#'     default is `"exact"` alone: a sighting position projected onto the
#'     track, which does not depend on the platform. See
#'     [sighting_distances()].}
#'   \item{Which records are kept}{`narwcr::classify_platform()` labels each
#'     stretch from its median speed. The platform names the label to keep.}
#' }
#'
#' @section What does not change:
#' `LEGTYPE` 5 and 6 mark shipboard records (8.A.21), but they mark a *platform
#' of opportunity* (POP): a ship that recorded what it saw while going
#' somewhere. That is not a designed line-transect. Counting it as effort would
#' put unsearched track into the denominator of a density estimate. The vessel
#' defaults therefore keep `legtype_on_effort = 2`, a designated census line,
#' as the aerial ones do. A dedicated shipboard line-transect survey codes its
#' lines `LEGTYPE = 2` and needs nothing here. A POP file is not a distance
#' sampling dataset.
#'
#' Segmentation itself does not depend on the platform. Great-circle distance
#' between consecutive fixes, splitting at breaks in effort, and cutting a
#' track into lengths work the same for a ship as for a plane.
#'
#' @section Naming:
#' `"vessel"` is the documented spelling, because it is the `PLATFORM_KIND`
#' level the filter compares against. `"ship"` is accepted everywhere `"vessel"` is, and resolves to
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
  # Aerial: the narwcr effort defaults and all three aircraft-era sources.
  # Vessel: no altitude criterion, and only the exact-position source.
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

# Return the canonical platform name: "aerial" or "vessel" (or "all" when
# allowed). "ship" becomes "vessel". match.arg() alone would accept "ship" but
# return it unchanged, giving two names for one platform.
resolve_platform <- function(platform, allow_all = FALSE,
                             call = rlang::caller_env()) {
  allowed <- c("aerial", "vessel", "ship", if (allow_all) "all")
  # An unchanged default argument is the full vector of choices; take the
  # first, as match.arg() does.
  if (length(platform) > 1L) platform <- platform[[1L]]
  platform <- as.character(platform)
  # Reject anything that is not a single allowed name.
  if (length(platform) != 1L || is.na(platform)) {
    cli_abort_bad_arg("platform", paste(platform, collapse = ", "),
                      allowed, call = call)
  }
  if (!platform %in% allowed) {
    cli_abort_bad_arg("platform", platform, allowed, call = call)
  }
  if (platform == "ship") "vessel" else platform
}

# Stop when an aircraft-only distance source ("angle", "strip") is requested
# for a vessel. Those measurements do not exist on a vessel; without this
# check sighting_distances() would leave the column NA with no reason given.
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

# Call narwcr::flag_effort() with `effort_args`. A criterion is dropped by
# passing it as NULL (e.g. `max_alt_m = NULL`). Older narwcr versions do not
# support this and fail with an unhelpful internal error, so check first and
# stop with an explanation. Callers pin narwcr by commit, so an older version
# may well be installed.
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

# TRUE if the installed narwcr accepts NULL to drop an effort criterion.
# Tested by behaviour on a two-row frame, not by the function's formals: the
# argument exists in all versions; only the handling of NULL differs. The
# answer is cached for the session.
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


# The speed band (knots) a platform is expected to move in, for checks that
# the data are from the stated platform. The bounds match the thresholds of
# narwcr::classify_platform().
platform_speed_band <- function(platform) {
  switch(platform,
    aerial = list(min = 40, max = Inf,
                  what = "a survey aircraft", several = "airframes"),
    vessel = list(min = 2, max = 40,
                  what = "a surveying vessel", several = "hulls")
  )
}
