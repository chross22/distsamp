#' Read NARWC-format survey data
#'
#' Reads a NARWC sightings-database extract from a CSV file, or standardises an
#' already-loaded data frame, into the column names and types the rest of the
#' package expects.
#'
#' It resolves column names onto the handbook's, coerces the numeric NARWC
#' variables, turns the database's missing-value placeholders (`"."`, `""`) into
#' `NA`, and drops records with no position. Beyond that it does not filter,
#' repair, or reject anything — use [validate_narwc()] to find problems and
#' [flag_effort()] to decide what counts as effort.
#'
#' A `DATE` column of class `Date` is derived from `YEAR`, `MONTH`, and `DAY`
#' when all three are present.
#'
#' @section Column names do not have to match exactly:
#' Real extracts spell things their own way. Matching ignores case and
#' separators, so `Event`, `event_no`, and `EventNo` all reach `EVENTNO` without
#' anyone editing a spreadsheet first, and the alias table in
#' [narwc_schema()]`$aliases` covers the rest.
#'
#' **This is not fuzzy matching.** Nothing is guessed by edit distance —
#' `EVENTN0` with a zero stays `EVENTN0` — and nothing is ever renamed onto a
#' canonical column that is already present, so a correctly named column always
#' wins. Matches that took an inference are reported; exact entries in the alias
#' table are not, since announcing `LAT_DD` on every read would bury the ones
#' worth a second look.
#'
#' @section Where `TIME` comes from:
#' Programmes record the clock they record. `TIME` is taken from the first of
#' `TIME`, then a UTC column (`TIME_UTC`, `GMT`, `TIME_GMT`), then a local one
#' (`TIME_LOC`, `TIME_LOCAL`) — GMT and UTC being the same clock. A file
#' carrying both zones lands on UTC. If yours is consistent it does not much
#' matter which; if it is not, decide before segmenting, because effort is
#' accumulated in record order.
#'
#' @section Records with no position:
#' Dropped by default, and reported. A record with no `LATITUDE` or `LONGITUDE`
#' contributes no effort and cannot place a sighting — but left in, it does not
#' announce itself: [gc_distance()] returns `NA`, which
#' [point_to_point_effort()] turns into a zero. Losing it visibly is better than
#' counting it as zero distance flown. `drop_missing_position = FALSE` keeps
#' them.
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
#'   \item{`extra_columns = c(...)`}{Keeps exactly what you name. Glob patterns
#'     work, so `"Trk*"` keeps a family whose exact names differ between
#'     extracts.}
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
#' @param drop_missing_position Drop records with no `LATITUDE` or `LONGITUDE`.
#'   Default `TRUE`; see below.
#' @param quiet Suppress the messages naming matched columns, dropped columns,
#'   and dropped records. Default `FALSE`.
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
                       drop_missing_position = TRUE, quiet = FALSE, ...) {
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

  # 1. Resolve input columns onto the canonical names.
  aliases <- schema$aliases
  resolved <- resolve_columns(names(dat), schema)
  if (length(resolved$renames)) {
    names(dat)[match(names(resolved$renames), names(dat))] <-
      unname(resolved$renames)
    # Only the inferred matches are worth saying out loud. An exact entry in
    # the alias table is documented behaviour, and announcing `LAT_DD` every
    # time would bury the ones that deserve a second look.
    if (!quiet && any(resolved$inferred)) {
      report_renamed_columns(resolved$renames[resolved$inferred])
    }
  }

  # 2. Select the columns we recognise, plus anything explicitly requested.
  #    Dropping a column the caller may need is a real loss, so say what went.
  if (!is.null(profile)) {
    extra_columns <- unique(c(extra_columns, narwc_profiles(profile)$column))
  }
  if (!is.null(extra_columns)) {
    keep <- c(schema$required, schema$optional,
              expand_column_globs(extra_columns, names(dat)))
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

  # 6. A record with no position cannot contribute effort or place a sighting.
  #    Left in, it silently contributes zero distance, which is worse than
  #    losing it visibly.
  if (drop_missing_position && all(c("LATITUDE", "LONGITUDE") %in% names(dat))) {
    gone <- is.na(dat$LATITUDE) | is.na(dat$LONGITUDE)
    if (any(gone)) {
      dat <- dat[!gone, , drop = FALSE]
      if (!quiet) {
        rlang::inform(paste0(
          "Dropped ", sum(gone), " record", if (sum(gone) > 1) "s" else "",
          " with no LATITUDE or LONGITUDE. Such a record contributes no ",
          "effort and cannot place a sighting; left in, it would count as ",
          "zero distance rather than as missing. Keep them with ",
          "`drop_missing_position = FALSE`."
        ))
      }
    }
  }

  class(dat) <- unique(c("distsamp_narwc", class(dat)))
  dat
}

# Map the input's column names onto the canonical ones.
#
# Three passes, most confident first: an exact canonical name is left alone; a
# name that matches one after normalising case and separators is renamed; and
# an alias is applied, normalised the same way. `Event`, `event_no` and
# `EventNo` all reach `EVENTNO` without anyone editing a spreadsheet.
#
# Normalising is not fuzzy matching. Nothing is guessed by edit distance, and
# nothing is renamed onto a canonical column that is already present - the
# real one always wins. Every rename is reported, because a column name is the
# one piece of provenance a reader has.
resolve_columns <- function(nms, schema) {
  canonical <- c(schema$required, schema$optional)
  norm <- function(x) toupper(gsub("[^A-Za-z0-9]", "", x))

  input_norm <- norm(nms)
  taken <- nms[nms %in% canonical]
  renames <- character(0)

  # Target, and whether reaching it took an inference. An exact alias is a
  # documented mapping; anything found only after normalising case or
  # separators is a judgement about what the author meant.
  target_of <- function(i) {
    if (nms[i] %in% canonical) return(c(NA_character_, "FALSE"))

    exact_alias <- unname(schema$aliases[match(nms[i], names(schema$aliases))])
    if (!is.na(exact_alias)) return(c(exact_alias, "FALSE"))

    hit <- canonical[match(input_norm[i], norm(canonical))]
    if (!is.na(hit)) return(c(hit, "TRUE"))

    alias_hit <- unname(schema$aliases[match(input_norm[i],
                                             norm(names(schema$aliases)))])
    if (!is.na(alias_hit)) return(c(alias_hit, "TRUE"))
    c(NA_character_, "FALSE")
  }

  # Preferred order among several inputs claiming the same canonical name.
  priority <- function(nm, target) {
    order_for <- narwc_alias_priority[[target]]
    if (is.null(order_for)) return(1)
    m <- match(norm(nm), norm(order_for))
    if (is.na(m)) length(order_for) + 1L else m
  }

  found <- vapply(seq_along(nms), target_of, character(2))
  wants <- found[1, ]
  guessed <- found[2, ] == "TRUE"
  inferred <- logical(0)

  for (target in unique(stats::na.omit(wants))) {
    if (target %in% taken) next
    claimants <- which(wants == target)
    if (length(claimants) > 1L) {
      claimants <- claimants[order(vapply(
        claimants, function(i) priority(nms[i], target), numeric(1)
      ))]
    }
    pick <- claimants[1]
    renames[nms[pick]] <- target
    inferred <- c(inferred, guessed[pick])
    taken <- c(taken, target)
  }
  list(renames = renames, inferred = inferred)
}

report_renamed_columns <- function(renames) {
  rlang::inform(paste0(
    "`read_narwc()` matched ", length(renames), " column",
    if (length(renames) > 1) "s" else "", " onto handbook names:\n  ",
    paste(names(renames), "->", unname(renames), collapse = "\n  "),
    "\nMatching ignores case and separators. Check these are what you meant."
  ))
}

# Glob patterns in `extra_columns`, so `Trk*` keeps a family of columns whose
# exact names differ between extracts.
expand_column_globs <- function(cols, nms) {
  if (!length(cols)) return(cols)
  out <- unlist(lapply(cols, function(p) {
    if (!grepl("[*?]", p)) return(p)
    nms[grepl(utils::glob2rx(p), nms)]
  }))
  unique(out)
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
