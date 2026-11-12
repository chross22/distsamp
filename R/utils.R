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

# Error for an argument whose value is not one of `allowed`, listing the
# permitted values.
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

# Error naming the missing columns. `what` names the argument they are
# missing from.
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

# Error unless every name in `cols` is a column of `dat`. Returns `dat`
# invisibly.
require_columns <- function(dat, cols, what = "dat", call = rlang::caller_env()) {
  missing <- setdiff(cols, names(dat))
  if (length(missing)) {
    abort_missing_columns(missing, what = what, call = call)
  }
  invisible(dat)
}

# Convert the NARWC missing-value placeholder "." and blank, "NA" or "na"
# strings to NA. Non-character input is returned unchanged.
blank_to_na <- function(x) {
  if (!is.character(x)) {
    return(x)
  }
  x[trimws(x) %in% c("", ".", "NA", "na")] <- NA_character_
  x
}

# Evaluate `expr` with seed `seed` if given. Either way the caller's random
# number state is restored afterwards, so segmenting never changes it.
with_optional_seed <- function(seed, expr) {
  if (is.null(seed)) {
    withr::with_preserve_seed(expr)
  } else {
    withr::with_seed(seed, expr)
  }
}

# Run-length id: 1, 1, 2, 2, 2, 3, ... incrementing whenever `x` changes.
# Used, for example, to separate runs of identical positions, or a line flown,
# abandoned, and re-flown on the same day.
rle_id <- function(x) {
  if (!length(x)) {
    return(integer(0))
  }
  # NA is treated as a value of its own, so consecutive NAs form one run.
  key <- ifelse(is.na(x), "NA", as.character(x))
  cumsum(c(TRUE, key[-1] != key[-length(key)]))
}

# Sort key that puts segment ids ("DATE_track_segno") in survey order: by
# date, then track and segment as numbers, so segment 2 comes before 19.
# Sorting the ids as text does not.
seg_sort_key <- function(seg_id) {
  seg_id <- as.character(seg_id)
  date <- sub("_.*$", "", seg_id)
  track <- suppressWarnings(as.numeric(sub("^[^_]*_([^_]*)_.*$", "\\1", seg_id)))
  segno <- suppressWarnings(as.numeric(sub("^.*_", "", seg_id)))
  u <- unique(seg_id)
  ord <- u[order(date[match(u, seg_id)], track[match(u, seg_id)],
                 segno[match(u, seg_id)], u)]
  match(seg_id, ord)
}

# TRUE for NULL or a data frame with no rows.
is_empty_df <- function(x) is.null(x) || nrow(x) == 0L

# Format numbers for display: rounded to whole numbers, with thousands
# separators, never in scientific notation (`format(6e6, big.mark = ",")`
# alone gives "6e+06").
fmt_count <- function(x) {
  format(round(x), big.mark = ",", scientific = FALSE, trim = TRUE)
}

# One string per row identifying its group: the values of the columns in `by`
# joined by "\r", a character that does not occur in the data.
group_key <- function(dat, by) {
  do.call(paste, c(lapply(by, function(nm) as.character(dat[[nm]])), sep = "\r"))
}

# Rows on effort. Without an `OnOff.Effort` column, every row counts.
on_effort <- function(dat) {
  if (!"OnOff.Effort" %in% names(dat)) return(rep(TRUE, nrow(dat)))
  !is.na(dat$OnOff.Effort) & dat$OnOff.Effort == 1
}
