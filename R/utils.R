#' @keywords internal
#'
#' @references
#' The segmentation method:
#'
#' Becker, E.A., Forney, K.A., Ferguson, M.C., Foley, D.G., Smith, R.C., Barlow,
#' J. and Redfern, J.V. (2010) Comparing California Current cetacean-habitat
#' models developed using in situ and remotely sensed sea surface temperature
#' data. *Marine Ecology Progress Series* 413:163-183.
#' \doi{10.3354/meps08696}
#'
#' The statistical framework it serves:
#'
#' Hedley, S.L. and Buckland, S.T. (2004) Spatial models for line transect
#' sampling. *Journal of Agricultural, Biological, and Environmental Statistics*
#' 9:181-199. \doi{10.1198/1085711043578}
#'
#' Miller, D.L., Burt, M.L., Rexstad, E.A. and Thomas, L. (2013) Spatial models
#' for distance sampling data: recent developments and future directions.
#' *Methods in Ecology and Evolution* 4:1001-1010.
#' \doi{10.1111/2041-210X.12105}
#'
#' Buckland, S.T., Anderson, D.R., Burnham, K.P., Laake, J.L., Borchers, D.L.
#' and Thomas, L. (2001) *Introduction to Distance Sampling: Estimating
#' Abundance of Biological Populations.* Oxford University Press, New York, NY.
#'
#' The data format and survey protocol:
#'
#' Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database: A
#' Guide for Users and Contributors, Version 8*. NARWC Reference Document
#' 2023-01. University of Rhode Island, Graduate School of Oceanography,
#' Narragansett, RI.
#'
#' CETAP (1982) *A Characterization of Marine Mammals and Turtles in the Mid- and
#' North-Atlantic Areas of the U.S. Outer Continental Shelf, Final Report.*
#' Cetacean and Turtle Assessment Program, University of Rhode Island. Bureau of
#' Land Management, Washington, DC.
#'
#' Kenney, R.D. and Winn, H.E. (1986) Cetacean high-use habitats of the northeast
#' United States continental shelf. *Fishery Bulletin* 84(2):345-357.
#'
#' A full list, with what each source is relied on for, is in `docs/06-references.md`
#' in the package repository.
#'
#' @importFrom rlang .data
#' @importFrom stats runif
"_PACKAGE"

# Abort on a bad enum-style argument, listing the permitted values.
cli_abort_bad_arg <- function(arg, value, allowed, call = rlang::caller_env()) {
  rlang::abort(
    paste0(
      "`", arg, "` must be one of ",
      paste0("\"", allowed, "\"", collapse = ", "),
      ", not \"", value, "\"."
    ),
    call = call
  )
}

# Abort when required columns are missing.
abort_missing_columns <- function(missing, what = "input", call = rlang::caller_env()) {
  rlang::abort(
    paste0(
      "`", what, "` is missing required column",
      if (length(missing) > 1) "s" else "", ": ",
      paste0("`", missing, "`", collapse = ", "), "."
    ),
    call = call
  )
}

# Stop unless every name in `cols` is present in `dat`.
require_columns <- function(dat, cols, what = "dat", call = rlang::caller_env()) {
  missing <- setdiff(cols, names(dat))
  if (length(missing)) {
    abort_missing_columns(missing, what = what, call = call)
  }
  invisible(dat)
}

# Treat the NARWC missing-value placeholder "." (and blanks) as NA.
blank_to_na <- function(x) {
  if (!is.character(x)) {
    return(x)
  }
  x[trimws(x) %in% c("", ".", "NA", "na")] <- NA_character_
  x
}

# Run `expr` under a fixed RNG seed when one is supplied, otherwise as-is.
# Isolates the caller's RNG stream either way, so segmenting never perturbs the
# global random state.
with_optional_seed <- function(seed, expr) {
  if (is.null(seed)) {
    withr::with_preserve_seed(expr)
  } else {
    withr::with_seed(seed, expr)
  }
}

# Run-length id: 1, 1, 2, 2, 2, 3, ... incrementing whenever `x` changes.
# Used to separate a survey line that was flown, abandoned, and later re-flown
# on the same day into distinct occupations.
rle_id <- function(x) {
  if (!length(x)) {
    return(integer(0))
  }
  key <- ifelse(is.na(x), "NA", as.character(x))
  cumsum(c(TRUE, key[-1] != key[-length(key)]))
}

# `%||%` without depending on a particular rlang export version.
`%|NA|%` <- function(x, y) ifelse(is.na(x), y, x)

is_empty_df <- function(x) is.null(x) || nrow(x) == 0L

# Records eligible for a right-angle distance: on effort, on a census line, and
# continuing it. Handbook 8.A.31 restricts the measurement to these. Shared by
# every distance source so that they cannot disagree about which sightings are
# fittable. Columns that are absent cannot disqualify a record.
on_effort_census_rows <- function(dat) {
  ok <- rep(TRUE, nrow(dat))
  if ("OnOff.Effort" %in% names(dat)) {
    ok <- ok & !is.na(dat$OnOff.Effort) & dat$OnOff.Effort == 1
  }
  if ("LEGTYPE" %in% names(dat)) {
    ok <- ok & !is.na(dat$LEGTYPE) & dat$LEGTYPE == 2
  }
  if ("LEGSTAGE" %in% names(dat)) {
    ok <- ok & !is.na(dat$LEGSTAGE) & dat$LEGSTAGE == 2
  }
  ok
}
