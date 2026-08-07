#' Read NARWC-format survey data
#'
#' Reads a NARWC sightings-database extract from a CSV file, or standardises an
#' already-loaded data frame, into the column names and types the rest of the
#' package expects.
#'
#' The function does three things and nothing else: it renames known alternative
#' spellings onto the internal names ([narwc_schema()]`$aliases`), coerces the
#' numeric NARWC variables to numeric, and turns the database's missing-value
#' placeholders (`"."`, `""`) into `NA`. It deliberately does not filter, repair,
#' or reject records — use [validate_narwc()] to find problems and
#' [flag_effort()] to decide what counts as effort.
#'
#' A `DATE` column of class `Date` is derived from `YEAR`, `MONTH`, and `DAY`
#' when all three are present.
#'
#' @param x A path to a CSV file, or a data frame.
#' @param extra_columns Character vector of additional column names to keep
#'   beyond those in [narwc_schema()]. Upstream processing pipelines often add
#'   derived columns (for example `Effort_Type`, `Tr_SIGHTING`, `OBSSIGHT`,
#'   `IS_LAT`); name them here to carry them through. Use `NULL` to keep every
#'   column in the input.
#' @param ... Passed to [utils::read.csv()] when `x` is a path.
#'
#' @return A tibble with the recognised NARWC columns, standardised names and
#'   types, and a derived `DATE` column. Carries the class
#'   `"distsamp_narwc"` so downstream functions can tell standardised input
#'   from a raw data frame.
#'
#' @references
#' Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database: A
#' Guide for Users and Contributors, Version 8*. NARWC Reference Document
#' 2023-01.
#'
#' @seealso [validate_narwc()] to check the result against the handbook,
#'   [narwc_schema()] for the recognised columns.
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' dat <- read_narwc(path)
#' head(dat[, c("FILEID", "EVENTNO", "LEGTYPE", "LEGSTAGE", "SPECCODE")])
#'
#' @export
read_narwc <- function(x, extra_columns = character(), ...) {
  dat <- if (is.data.frame(x)) {
    x
  } else if (is.character(x) && length(x) == 1L) {
    if (!file.exists(x)) {
      rlang::abort(paste0("File not found: ", x))
    }
    utils::read.csv(x, stringsAsFactors = FALSE, colClasses = "character", ...)
  } else {
    rlang::abort("`x` must be a data frame or a path to a single CSV file.")
  }

  dat <- tibble::as_tibble(dat)
  schema <- narwc_schema()

  # 1. Rename known aliases onto internal names, but never clobber a column
  #    that is already correctly named.
  aliases <- schema$aliases
  present <- intersect(names(aliases), names(dat))
  for (from in present) {
    to <- aliases[[from]]
    if (!to %in% names(dat)) {
      names(dat)[names(dat) == from] <- to
    }
  }

  # 2. Select the columns we recognise, plus anything explicitly requested.
  if (!is.null(extra_columns)) {
    keep <- c(schema$required, schema$optional, extra_columns)
    dat <- dat[, intersect(keep, names(dat)), drop = FALSE]
  }

  # 3. NARWC writes "." for missing. Blank those before coercion so that a
  #    single "." does not turn a whole column into NA-with-warning.
  dat[] <- lapply(dat, blank_to_na)

  # 4. Coerce the numeric NARWC variables.
  for (nm in intersect(narwc_numeric_columns, names(dat))) {
    if (!is.numeric(dat[[nm]])) {
      dat[[nm]] <- suppressWarnings(as.numeric(dat[[nm]]))
    }
  }

  # 5. Derive DATE when the date parts are all present.
  if (all(c("YEAR", "MONTH", "DAY") %in% names(dat)) && !"DATE" %in% names(dat)) {
    dat$DATE <- as.Date(sprintf("%04d-%02d-%02d", dat$YEAR, dat$MONTH, dat$DAY))
  } else if ("DATE" %in% names(dat) && !inherits(dat$DATE, "Date")) {
    dat$DATE <- as.Date(dat$DATE)
  }

  class(dat) <- unique(c("distsamp_narwc", class(dat)))
  dat
}
