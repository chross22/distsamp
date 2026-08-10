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
#'   \item{`legstage_sequence`}{`LEGSTAGE` does not follow a logical order
#'     within a line occupation. Handbook 8.A.20: a line begins (1), continues
#'     (2), may break off to circle (3) and resume (4), and ends (5). A line
#'     must begin with 1, nothing may follow an end-line, and a resume cannot
#'     appear without a break-off before it.}
#'   \item{`legstage_break_off_unresumed`}{A line ends at a break-off (3) with
#'     no resume and no end-line: the aircraft left the census line and the
#'     record never brings it back.}
#'   \item{`legstage_line_not_closed`}{A line has no end-line (5). A note
#'     rather than a warning, because a line abandoned for weather or re-flown
#'     later legitimately has none.}
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
#'   \item{`columns_outside_handbook`}{Columns present that are not NARWC
#'     handbook variables. Survey programmes add their own; they are carried
#'     through uninterpreted, and one that encodes position, effort, or distance
#'     must be mapped explicitly. See [narwc_profiles()].}
#'   \item{`exact_position_out_of_range`}{`S_LAT` or `S_LONG` outside the range
#'     a coordinate can take. Handbook 8.A.33 and 8.A.34 give the exact sighting
#'     position in decimal degrees.}
#'   \item{`exact_position_far_from_event`}{An exact sighting position more than
#'     20 km from the event position that recorded it. A sighting is made from
#'     the aircraft, so this is a coordinate problem — usually a dropped minus
#'     sign, or degrees and decimal minutes read as decimal degrees — rather
#'     than a distant animal.}
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

  # --- LEGSTAGE sequence ----------------------------------------------------
  seq_check <- legstage_sequence_check(dat)
  add(
    "legstage_sequence", "warning", "LEGSTAGE", seq_check$bad,
    paste0(
      "LEGSTAGE does not follow a logical sequence within a line occupation. ",
      "Handbook 8.A.20: a line begins (1), continues (2), may break off to ",
      "circle (3) and resume (4), and ends (5). A line must begin with 1, ",
      "nothing may follow an end-line, and a break-off must be resumed."
    )
  )
  add(
    "legstage_break_off_unresumed", "warning", "LEGSTAGE", seq_check$dangling,
    paste0(
      "A line occupation ends at LEGSTAGE 3, a break off to circle, with no ",
      "resume (4) and no end-line (5). The aircraft left the census line and ",
      "the record never brings it back."
    )
  )
  add(
    "legstage_line_not_closed", "note", "LEGSTAGE", seq_check$open,
    paste0(
      "A line occupation has no end-line (LEGSTAGE 5). This is normal for a ",
      "line abandoned mid-flight - for weather, or to re-fly it later - and a ",
      "problem only if the line was flown to completion."
    )
  )

  # --- columns from outside the handbook ------------------------------------
  unknown <- unrecognised_columns(names(dat))
  if (length(unknown)) {
    hits <- matching_profiles(unknown)
    msg <- paste0(
      "Columns present that are not NARWC handbook variables: ",
      paste0("`", sort(unknown), "`", collapse = ", "), ". "
    )
    msg <- paste0(msg, if (length(hits)) {
      paste0(
        "Some are declared by the \"", hits[1], "\" profile; see ",
        "`narwc_profiles()`. They are carried through uninterpreted."
      )
    } else {
      paste0(
        "They are carried through uninterpreted. If any encodes position, ",
        "effort, or distance, it must be mapped explicitly - `distsamp` will ",
        "not infer meaning from a column name."
      )
    })
    out[[length(out) + 1L]] <- tibble::tibble(
      check = "columns_outside_handbook", severity = "note",
      column = paste(sort(unknown), collapse = ", "),
      n = length(unknown), rows = list(integer(0)), message = msg
    )
  }

  # --- exact sighting positions ---------------------------------------------
  if (all(c("S_LAT", "S_LONG", "LATITUDE", "LONGITUDE") %in% names(dat))) {
    s_lat <- suppressWarnings(as.numeric(dat$S_LAT))
    s_lon <- suppressWarnings(as.numeric(dat$S_LONG))

    add(
      "exact_position_out_of_range", "error", "S_LAT/S_LONG",
      which((!is.na(s_lat) & abs(s_lat) > 90) |
              (!is.na(s_lon) & abs(s_lon) > 180)),
      paste0(
        "Exact sighting latitude outside [-90, 90] or longitude outside ",
        "[-180, 180]. Handbook 8.A.33 and 8.A.34 give these in decimal ",
        "degrees; degrees and decimal minutes will fail this check."
      )
    )

    # A sighting is seen from the aircraft, so it cannot be far from the
    # position that logged it. Anything beyond a few km is a coordinate
    # problem, not a whale.
    away <- gc_distance(dat$LATITUDE, dat$LONGITUDE, s_lat, s_lon)
    add(
      "exact_position_far_from_event", "warning", "S_LAT/S_LONG",
      which(!is.na(away) & away > EXACT_POSITION_MAX_KM),
      paste0(
        "Exact sighting position more than ", EXACT_POSITION_MAX_KM,
        " km from the event position that recorded it. The usual causes are a ",
        "dropped minus sign on S_LONG and coordinates in degrees and decimal ",
        "minutes rather than decimal degrees."
      )
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


# --- LEGSTAGE sequence ------------------------------------------------------
#
# Handbook 8.A.20 gives LEGSTAGE as the stage of a survey line, and the stages
# describe a progression rather than a set of independent labels: a line begins
# (1), continues (2), may break off to circle (3) and resume (4), and ends (5).
# Codes 6 and 7 mark a kind of sighting rather than a stage of the line, so they
# take no part in the sequence.
#
# The permitted transitions, [from, to]:
#
#        to:  1   2   3   4   5
#   from 1        x   x       x
#   from 2        x   x       x
#   from 3                x
#   from 4        x   x       x
#   from 5
#
# Nothing may follow an end-line, a break-off must be resumed, and a resume
# cannot appear without a break-off before it - each falls out of the table
# rather than being special-cased.
legstage_allowed <- local({
  m <- matrix(FALSE, nrow = 5, ncol = 5)
  m[1, c(2, 3, 5)] <- TRUE
  m[2, c(2, 3, 5)] <- TRUE
  m[3, 4] <- TRUE
  m[4, c(2, 3, 5)] <- TRUE
  m
})

# Rows whose LEGSTAGE cannot follow the one before it within the same line
# occupation, plus lines that never close.
#
# Occupations come from LEGNO3 where it exists. Without it they are derived the
# way make_leg_id() does, because grouping on LEGNO alone would merge a line
# flown, abandoned, and re-flown the same day into one sequence - and its second
# "begin line" would then look like a violation when it is the correct record of
# a second occupation.
#
# Assumes survey order, as the rest of the package does. Records out of order
# are reported separately by `eventno_not_increasing`.
legstage_sequence_check <- function(dat) {
  empty <- list(bad = integer(0), open = integer(0), dangling = integer(0))
  if (!all(c("LEGSTAGE", "LEGNO") %in% names(dat)) || is_empty_df(dat)) {
    return(empty)
  }

  stage <- suppressWarnings(as.integer(dat$LEGSTAGE))
  on_census <- if ("LEGTYPE" %in% names(dat)) {
    is.na(dat$LEGTYPE) | dat$LEGTYPE == 2
  } else {
    rep(TRUE, nrow(dat))
  }

  # Structural stages only, on the census line. A circling record carries no
  # LEGSTAGE and so drops out here, which is what lets 3 -> 4 stay adjacent
  # across the excursion between them.
  keep <- which(!is.na(stage) & stage >= 1L & stage <= 5L & on_census)
  if (length(keep) < 1L) {
    return(empty)
  }

  occupation <- if ("LEGNO3" %in% names(dat)) {
    as.character(dat$LEGNO3)
  } else {
    legno <- as.character(dat$LEGNO)
    paste(legno, rle_id(legno), sep = "_")
  }
  day <- if ("DATE" %in% names(dat)) as.character(dat$DATE) else ""
  key <- paste(day, occupation)[keep]
  stage <- stage[keep]

  n <- length(stage)
  first <- c(TRUE, key[-1] != key[-n])
  last <- c(key[-1] != key[-n], TRUE)

  prev <- c(1L, stage[-n])
  prev[first] <- 1L # never used, but must index the matrix
  ok <- legstage_allowed[cbind(prev, stage)]

  list(
    bad = keep[(!first & !ok) | (first & stage != 1L)],
    open = keep[last & stage != 5L & stage != 3L],
    dangling = keep[last & stage == 3L]
  )
}
