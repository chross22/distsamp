#' @keywords internal
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
