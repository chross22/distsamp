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
#' @section Columns that are not in the handbook:
#' Survey programmes add their own derived columns, and a processed "ready for
#' model" file may carry a dozen. They are not handbook Table 1 variables, so by
#' default they are **dropped** — and this function says so rather than dropping
#' them silently, naming what went and pointing at [narwc_profiles()] when they
#' match a known survey programme.
#'
#' Three ways to keep them:
#'
#' \describe{
#'   \item{`profile = "ccs"`}{Keeps the columns that programme is known to add.
#'     See [narwc_profiles()] for what is registered.}
#'   \item{`extra_columns = c(...)`}{Keeps exactly what you name.}
#'   \item{`extra_columns = NULL`}{Keeps every column in the input.}
#' }
#'
#' Naming a profile keeps its columns; it does not interpret them. A column name
#' is not a contract between programmes — `Tr_SIGHTING` means one thing in a CCS
#' file and nothing in particular anywhere else — so this function will tell you
#' what a file looks like and leave the decision to you.
#'
#' @param x A path to a CSV file, or a data frame.
#' @param extra_columns Character vector of additional column names to keep
#'   beyond those in [narwc_schema()]. Use `NULL` to keep every column in the
#'   input.
#' @param profile Survey-programme profile whose extra columns should be kept,
#'   for example `"ccs"`. `NULL` (default) keeps only the handbook columns. See
#'   [narwc_profiles()].
#' @param quiet Suppress the message naming dropped columns. Default `FALSE`.
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
#'   [narwc_schema()] for the recognised columns, [narwc_profiles()] for the
#'   columns individual survey programmes add.
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' dat <- read_narwc(path)
#' head(dat[, c("FILEID", "EVENTNO", "LEGTYPE", "LEGSTAGE", "SPECCODE")])
#'
#' # Keep a survey programme's own columns
#' narwc_profiles("ccs")$column
#'
#' @export
read_narwc <- function(x, extra_columns = character(), profile = NULL,
                       quiet = FALSE, ...) {
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
  #    Dropping a column the caller may need is a real loss, so say what went.
  if (!is.null(profile)) {
    extra_columns <- unique(c(extra_columns, narwc_profiles(profile)$column))
  }
  if (!is.null(extra_columns)) {
    keep <- c(schema$required, schema$optional, extra_columns)
    dropped <- setdiff(names(dat), keep)
    dat <- dat[, intersect(keep, names(dat)), drop = FALSE]

    # An alias left behind because its canonical column was already present is
    # a duplicate, not a loss. Reporting it would send the caller looking for
    # information that is still there under the other name.
    redundant <- names(aliases)[aliases %in% names(dat)]
    dropped <- setdiff(dropped, redundant)

    if (length(dropped) && !quiet) {
      report_dropped_columns(dropped)
    }
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

# Tell the caller which columns were discarded, and whether they look like a
# known survey programme's. Information, not action: naming the profile is the
# caller's decision, because a column name means whatever the programme that
# wrote it says it means.
report_dropped_columns <- function(dropped) {
  lines <- paste0(
    "`read_narwc()` dropped ", length(dropped),
    " column", if (length(dropped) > 1) "s" else "",
    " not in the NARWC handbook schema:\n  ",
    paste(sort(dropped), collapse = ", ")
  )

  hits <- matching_profiles(dropped)
  if (length(hits)) {
    reg <- narwc_profiles(hits[1])
    n <- length(intersect(dropped, reg$column))
    lines <- c(lines, paste0(
      n, " of these are declared by the \"", hits[1], "\" profile (",
      reg$programme[1], ").\n",
      "Keep them with `profile = \"", hits[1], "\"`; see `narwc_profiles()`."
    ))
  } else {
    lines <- c(lines, paste0(
      "Keep them with `extra_columns = `, or all columns with ",
      "`extra_columns = NULL`.\nIf any of them carries position, effort, or ",
      "distance information, it must be mapped explicitly - `distsamp` will ",
      "not guess from a column name."
    ))
  }

  rlang::inform(paste(lines, collapse = "\n"))
}
