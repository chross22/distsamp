#' Check survey data against the NARWC handbook
#'
#' Runs a series of structural and code-book checks against a standardised
#' NARWC data frame and reports every problem found. Validation never stops on
#' error and never modifies the data: the result is a report you read, so that
#' you can decide which problems matter for your analysis.
#'
#' @section Checks performed:
#' \describe{
#'   \item{`missing_required`}{A column in [narwc_schema()]`$required` is absent.
#'     Severity `error` — segmentation cannot proceed.}
#'   \item{`missing_values`}{`NA` in a required column.}
#'   \item{`unknown_code`}{A value of `LEGTYPE`, `LEGSTAGE`, `IDREL`, `TAXCODE`,
#'     or `STRATUM` that is not in the handbook's code book.}
#'   \item{`legstage_off_census`}{`LEGSTAGE` recorded on a record that is not a
#'     census line. Handbook 8.A.20: for dedicated aerial surveys `LEGSTAGE` is
#'     recorded only during census tracks (`LEGTYPE == 2`), except for code 7.}
#'   \item{`sighting_at_boundary`}{A sighting recorded at a `LEGSTAGE` of 1, 3,
#'     4, or 5. Handbook 8.A.20 and 4.2: sightings should not occur at
#'     begin-line, break-off, resume, or end-line events.}
#'   \item{`eventno_not_increasing`}{`EVENTNO` does not increase through a
#'     `FILEID`. Repeated values are allowed — the handbook (4.2) assigns one
#'     event several sightings — but decreases indicate mis-sorted records.}
#'   \item{`bad_time_format`}{`TIME` is not a 6-digit `hhmmss` in 24-hour form
#'     (handbook 8.A.37). Four-digit `hhmm` times are reported separately as a
#'     warning since they are still found in older data.}
#'   \item{`coordinates_out_of_range`}{Latitude outside \[-90, 90\] or longitude
#'     outside \[-180, 180\].}
#'   \item{`positive_west_longitude`}{Every longitude is positive. Handbook
#'     8.A.22 requires west longitudes to be negative; all-positive longitudes
#'     in a western North Atlantic dataset mean the sign convention was lost.}
#'   \item{`sighting_without_number`}{`SPECCODE` present but `NUMBER` missing.
#'     Handbook 8.A.24 requires `NUMBER` for all sightings.}
#'   \item{`angle_out_of_range`}{`ANGLEL` or `ANGLER` outside `(0, 90]`. Handbook
#'     8.A.2 defines these as declination angles below the horizon, so a value at
#'     or below zero is at or above the horizon and one above 90 is behind the
#'     aircraft. Neither yields a perpendicular distance.}
#'   \item{`angle_both_sides`}{Both `ANGLEL` and `ANGLER` recorded on one
#'     record. A sighting is on one side of the track, so the side is ambiguous
#'     and no distance can be computed.}
#'   \item{`angle_without_altitude`}{A declination angle with no `ALT`. Handbook
#'     8.A.2: the distance calculation must factor in altitude, so an angle
#'     without one is unusable.}
#' }
#'
#' @param dat A data frame of NARWC survey data, ideally from [read_narwc()].
#'
#' @return A tibble with one row per problem found, and columns:
#'   \describe{
#'     \item{`check`}{Name of the check, as listed above.}
#'     \item{`severity`}{`"error"`, `"warning"`, or `"note"`.}
#'     \item{`column`}{The column involved, or `NA`.}
#'     \item{`n`}{Number of records affected.}
#'     \item{`rows`}{List column of affected row indices (capped at 100).}
#'     \item{`message`}{Human-readable description.}
#'   }
#'   A zero-row tibble means every check passed.
#'
#' @references
#' Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database: A
#' Guide for Users and Contributors, Version 8*. NARWC Reference Document
#' 2023-01. University of Rhode Island, Graduate School of Oceanography. Every
#' check above cites the section it derives from.
#'
#' Kenney, R.D. (2002) *Quality-control Issues for Data Submissions to the North
#' Atlantic Right Whale Consortium Database.* NARWC Reference Document 2002-02.
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' issues <- validate_narwc(read_narwc(path))
#' issues[, c("check", "severity", "n")]
#'
#' @export
validate_narwc <- function(dat) {
  stopifnot(is.data.frame(dat))
  schema <- narwc_schema()
  out <- list()

  add <- function(check, severity, column, rows, message) {
    if (!length(rows)) {
      return(invisible(NULL))
    }
    out[[length(out) + 1L]] <<- tibble::tibble(
      check = check,
      severity = severity,
      column = column %|NA|% NA_character_,
      n = length(rows),
      rows = list(utils::head(rows, 100L)),
      message = message
    )
  }

  # --- required columns -----------------------------------------------------
  missing_req <- setdiff(schema$required, names(dat))
  for (nm in missing_req) {
    # A missing column has no affected rows, so `add()` (which skips empty
    # row sets) cannot express it; record it directly.
    out[[length(out) + 1L]] <- tibble::tibble(
      check = "missing_required", severity = "error", column = nm,
      n = NA_integer_, rows = list(integer(0)),
      message = paste0("Required column `", nm, "` is absent.")
    )
  }

  for (nm in intersect(schema$required, names(dat))) {
    add(
      "missing_values", "error", nm, which(is.na(dat[[nm]])),
      paste0("Required column `", nm, "` contains missing values.")
    )
  }

  # --- code books -----------------------------------------------------------
  for (nm in c("LEGTYPE", "LEGSTAGE", "IDREL", "TAXCODE", "STRATUM")) {
    if (!nm %in% names(dat)) next
    allowed <- names(narwc_codes(nm))
    observed <- as.character(dat[[nm]])
    bad <- which(!is.na(observed) & !observed %in% allowed)
    add(
      "unknown_code", "warning", nm, bad,
      paste0(
        "`", nm, "` contains values outside the handbook code book (permitted: ",
        paste(allowed, collapse = ", "), ")."
      )
    )
  }

  # --- LEGSTAGE only on census tracks ---------------------------------------
  if (all(c("LEGTYPE", "LEGSTAGE") %in% names(dat))) {
    bad <- which(
      !is.na(dat$LEGSTAGE) & dat$LEGSTAGE != 7 &
        !is.na(dat$LEGTYPE) & dat$LEGTYPE != 2
    )
    add(
      "legstage_off_census", "note", "LEGSTAGE", bad,
      paste0(
        "LEGSTAGE recorded on records that are not census lines. Handbook ",
        "8.A.20: for dedicated aerial surveys LEGSTAGE is recorded only ",
        "during LEGTYPE 2, except code 7."
      )
    )
  }

  # --- sightings at line-boundary events ------------------------------------
  if (all(c("LEGSTAGE", "SPECCODE") %in% names(dat))) {
    bad <- which(!is.na(dat$SPECCODE) & dat$LEGSTAGE %in% c(1, 3, 4, 5))
    add(
      "sighting_at_boundary", "warning", "LEGSTAGE", bad,
      paste0(
        "Sightings recorded at LEGSTAGE 1, 3, 4, or 5. Handbook 8.A.20: ",
        "sightings should not occur at begin-line, break-off, resume, or ",
        "end-line events."
      )
    )
  }

  # --- event ordering -------------------------------------------------------
  if (all(c("FILEID", "EVENTNO") %in% names(dat))) {
    bad <- integer(0)
    for (fid in unique(dat$FILEID)) {
      idx <- which(dat$FILEID == fid)
      ev <- dat$EVENTNO[idx]
      drops <- which(diff(ev) < 0)
      if (length(drops)) bad <- c(bad, idx[drops + 1L])
    }
    add(
      "eventno_not_increasing", "warning", "EVENTNO", sort(bad),
      "EVENTNO decreases within a FILEID; records may be mis-sorted."
    )
  }

  # --- time format ----------------------------------------------------------
  if ("TIME" %in% names(dat)) {
    tm <- dat$TIME
    ok <- is.na(tm) | (tm >= 0 & tm <= 235959)
    add(
      "bad_time_format", "warning", "TIME", which(!ok),
      "TIME outside the range of a valid hhmmss clock time (handbook 8.A.37)."
    )
    four_digit <- which(!is.na(tm) & tm > 0 & tm <= 2359 & tm %% 1 == 0)
    add(
      "bad_time_format", "note", "TIME", four_digit,
      paste0(
        "TIME values look like four-digit hhmm rather than six-digit hhmmss ",
        "(handbook 8.A.37). Ambiguous with early-morning hhmmss times."
      )
    )
  }

  # --- coordinates ----------------------------------------------------------
  if (all(c("LATITUDE", "LONGITUDE") %in% names(dat))) {
    bad <- which(
      (!is.na(dat$LATITUDE) & abs(dat$LATITUDE) > 90) |
        (!is.na(dat$LONGITUDE) & abs(dat$LONGITUDE) > 180)
    )
    add(
      "coordinates_out_of_range", "error", "LATITUDE/LONGITUDE", bad,
      "Latitude outside [-90, 90] or longitude outside [-180, 180]."
    )

    lon <- dat$LONGITUDE[!is.na(dat$LONGITUDE)]
    if (length(lon) && all(lon > 0)) {
      out[[length(out) + 1L]] <- tibble::tibble(
        check = "positive_west_longitude", severity = "warning",
        column = "LONGITUDE", n = length(lon), rows = list(integer(0)),
        message = paste0(
          "All longitudes are positive. Handbook 8.A.22 requires west ",
          "longitudes to be negative; the sign convention may have been lost."
        )
      )
    }
  }

  # --- sightings need a count ----------------------------------------------
  if (all(c("SPECCODE", "NUMBER") %in% names(dat))) {
    add(
      "sighting_without_number", "warning", "NUMBER",
      which(!is.na(dat$SPECCODE) & is.na(dat$NUMBER)),
      "SPECCODE present but NUMBER missing (handbook 8.A.24)."
    )
  }

  # --- declination angles ---------------------------------------------------
  angle_cols <- intersect(c("ANGLEL", "ANGLER"), names(dat))
  for (nm in angle_cols) {
    a <- suppressWarnings(as.numeric(dat[[nm]]))
    add(
      "angle_out_of_range", "warning", nm,
      which(!is.na(a) & (a <= 0 | a > 90)),
      paste0(
        "`", nm, "` outside (0, 90] degrees. Handbook 8.A.2 defines these as ",
        "declination angles below the horizon."
      )
    )
  }

  if (length(angle_cols) == 2L) {
    add(
      "angle_both_sides", "warning", "ANGLEL/ANGLER",
      which(!is.na(dat$ANGLEL) & !is.na(dat$ANGLER)),
      paste0(
        "Both ANGLEL and ANGLER recorded on the same record; a sighting is on ",
        "one side of the track, so no perpendicular distance can be computed."
      )
    )
  }

  if (length(angle_cols) && "ALT" %in% names(dat)) {
    has_angle <- Reduce(`|`, lapply(angle_cols, function(nm) !is.na(dat[[nm]])))
    add(
      "angle_without_altitude", "warning", "ALT",
      which(has_angle & (is.na(dat$ALT) | dat$ALT <= 0)),
      "Declination angle recorded without a usable ALT (handbook 8.A.2)."
    )
  }

  if (!length(out)) {
    return(tibble::tibble(
      check = character(), severity = character(), column = character(),
      n = integer(), rows = list(), message = character()
    ))
  }
  dplyr::bind_rows(out)
}
