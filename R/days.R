#' Keep the survey days you want to look at
#'
#' Subsets a survey to particular days, years, or months. The plotting functions
#' take the same three arguments and pass them straight here, so this is mostly
#' useful on its own when the subset is wanted for something other than a plot.
#'
#' @section Why this exists:
#' A NARWC extract is decades long, and nothing useful is drawn from it whole.
#' The question that sends you to a plot is almost always about a stretch of it:
#' the day an occupation looked wrong, the August the survey pattern changed,
#' the year an era boundary falls in. Naming that stretch is the difference
#' between a figure you can read and 187 you will not open.
#'
#' @section How the three combine:
#' Given together they narrow, they do not accumulate: `years = 2019, months = 8`
#' keeps August 2019 — not all of 2019 and every August of every year. `dates`
#' names days outright and is checked the same way, so `dates` plus a `years`
#' that excludes them keeps nothing, and says so rather than drawing an empty
#' map.
#'
#' Records with no `DATE` are dropped whenever any of the three is given: a
#' record with no date is in no month. With all three `NULL` the data comes back
#' untouched, undated records included.
#'
#' @param dat A survey data frame with a `DATE` column.
#' @param dates Days to keep: `Date` objects, or strings `as.Date()` accepts —
#'   `"2019-08-14"`. `NULL` (default) keeps every day.
#' @param years Years to keep, as numbers: `2019`, or `2015:2019`.
#' @param months Months to keep, as numbers (`8`), full names (`"August"`), or
#'   abbreviations (`"Aug"`). Names are matched without regard to case.
#'
#' @return `dat` with the unwanted rows removed.
#'
#' @seealso [plot_survey()] and [plot_survey_panel()], which take these
#'   arguments directly.
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' dat <- read_narwc(path, quiet = TRUE)
#'
#' # One day, by name
#' nrow(filter_days(dat, dates = "2024-04-01"))
#'
#' # A whole month, and a month within a year
#' nrow(filter_days(dat, months = "April"))
#' nrow(filter_days(dat, years = 2024, months = 4))
#'
#' @export
filter_days <- function(dat, dates = NULL, years = NULL, months = NULL) {
  stopifnot(is.data.frame(dat))
  if (is.null(dates) && is.null(years) && is.null(months)) {
    return(dat)
  }
  require_columns(dat, "DATE")

  keep <- day_mask(dat$DATE, dates, years, months)
  if (!any(keep)) {
    rlang::abort(paste0(
      "No records fall in the requested days. ", covers(dat$DATE)
    ))
  }
  dat[keep, , drop = FALSE]
}

# The mask on its own, for callers holding several tables that have to be cut
# the same way. A `distsamp_segments` has points, segments and detections; the
# detections of one day can legitimately be none, so the "nothing matched"
# error belongs to the caller that knows which table must not end up empty.
day_mask <- function(x, dates = NULL, years = NULL, months = NULL) {
  day <- as.Date(x)
  keep <- !is.na(day)
  if (!is.null(dates)) {
    keep <- keep & day %in% resolve_dates(dates)
  }
  if (!is.null(years)) {
    keep <- keep & as.integer(format(day, "%Y")) %in% resolve_years(years)
  }
  if (!is.null(months)) {
    keep <- keep & as.integer(format(day, "%m")) %in% resolve_months(months)
  }
  keep
}

# Every table in a segmentation cut to the same days.
filter_segments_days <- function(x, dates = NULL, years = NULL, months = NULL) {
  if (is.null(dates) && is.null(years) && is.null(months)) {
    return(x)
  }
  if (!any(day_mask(x$points$DATE, dates, years, months))) {
    rlang::abort(paste0(
      "No survey positions fall in the requested days. ", covers(x$points$DATE)
    ))
  }
  for (tab in c("points", "segments", "detections", "sightings", "tracks")) {
    d <- x[[tab]]
    if (is.data.frame(d) && "DATE" %in% names(d)) {
      x[[tab]] <- d[day_mask(d$DATE, dates, years, months), , drop = FALSE]
    }
  }
  x
}

# What the data actually holds, for an error message that ends the guessing.
covers <- function(dates) {
  d <- stats::na.omit(as.Date(dates))
  if (!length(d)) {
    return("No record in this data carries a `DATE`.")
  }
  yrs <- sort(unique(as.integer(format(d, "%Y"))))
  paste0(
    "The data covers ", format(min(d)), " to ", format(max(d)), " - ",
    length(unique(d)), " survey day", if (length(unique(d)) != 1L) "s" else "",
    " in ", if (length(yrs) <= 6L) {
      paste(yrs, collapse = ", ")
    } else {
      paste0(length(yrs), " years, ", min(yrs), " to ", max(yrs))
    }, "."
  )
}

resolve_dates <- function(dates) {
  if (inherits(dates, "Date")) {
    return(dates)
  }
  if (inherits(dates, "POSIXt")) {
    return(as.Date(dates))
  }
  out <- suppressWarnings(try(as.Date(as.character(dates)), silent = TRUE))
  if (inherits(out, "try-error") || anyNA(out)) {
    bad <- if (inherits(out, "try-error")) dates else dates[is.na(out)]
    rlang::abort(paste0(
      "`dates` must be `Date` objects or strings like \"2019-08-14\". ",
      "Could not read: ", paste0("\"", bad, "\"", collapse = ", "), "."
    ))
  }
  out
}

resolve_years <- function(years) {
  y <- suppressWarnings(as.integer(years))
  if (anyNA(y)) {
    rlang::abort(paste0(
      "`years` must be whole numbers like 2019. Could not read: ",
      paste0("\"", years[is.na(y)], "\"", collapse = ", "), "."
    ))
  }
  y
}

# Numbers, full names, or abbreviations - whichever the caller had to hand.
# "Aug" and "august" are the same month, and so is 8.
resolve_months <- function(months) {
  if (is.numeric(months)) {
    return(check_month_numbers(months, months))
  }
  m <- tolower(trimws(as.character(months)))
  out <- match(m, tolower(month.name))
  out[is.na(out)] <- match(m[is.na(out)], tolower(month.abb))

  numeric_like <- is.na(out) & grepl("^[0-9]+$", m)
  out[numeric_like] <- as.integer(m[numeric_like])

  if (anyNA(out)) {
    rlang::abort(paste0(
      "`months` must be numbers 1-12, names like \"August\", or abbreviations ",
      "like \"Aug\". Could not read: ",
      paste0("\"", months[is.na(out)], "\"", collapse = ", "), "."
    ))
  }
  check_month_numbers(out, months)
}

check_month_numbers <- function(x, original) {
  bad <- is.na(x) | x < 1 | x > 12 | x != round(x)
  if (any(bad)) {
    rlang::abort(paste0(
      "`months` must be between 1 and 12. Out of range: ",
      paste(original[bad], collapse = ", "), "."
    ))
  }
  as.integer(x)
}
