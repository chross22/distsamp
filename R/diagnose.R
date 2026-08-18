#' Diagnose common reasons a segmentation might be wrong before you trust it
#'
#' Runs the reading and segmentation pipeline — `read_narwc()`,
#' [validate_narwc()], `make_leg_id()`, `flag_effort()`,
#' [point_to_point_effort()] and [segment_survey()] — and reports on the ways a
#' real extract goes wrong quietly. Meant to be run once against a new dataset,
#' before any of its numbers are used.
#'
#' The failure this exists for is not the one that errors. It is the one that
#' returns a plausible number: effort that silently includes the ferry between
#' two survey days, an altitude read as metres when the column was named in
#' feet, a position taken from the vessel when the aircraft's GPS track was
#' sitting in the file. Each of those produces a density estimate that is wrong
#' by a factor and looks entirely reasonable.
#'
#' Every check reports rather than fixes. This function never modifies the data
#' or the arguments it was given.
#'
#' @param x A path to a NARWC CSV, or a data frame. A path is read with
#'   `read_narwc()`; a data frame is taken as already read.
#' @param days Which survey days to diagnose, so a large extract can be checked
#'   in seconds before it is run in full. `"auto"` picks the day with the most
#'   census records carrying every criterion `flag_effort()` needs; a number
#'   takes that many days from the start; a `Date` or date string takes exactly
#'   those days. `NULL` (default) uses everything.
#'
#'   `"auto"` is the one to reach for. The start of a season is often atypical
#'   — a day may not record the altitude or sea state the rest of the file
#'   does — and every criterion fails on a missing value, so an
#'   unrepresentative day reports no effort at all while the file is fine.
#'
#'   Whole days are kept, never a sample of records. Effort and segmentation
#'   are computed from consecutive positions along a line, so a random subset
#'   of records would report distances across gaps that are an artefact of the
#'   sampling — a diagnosis of the subset rather than of the data. Every total
#'   printed is then for the subset, and the header says so.
#' @param seg_length Segment length in km, passed to [segment_survey()].
#'   Default `10`.
#' @param species Passed to [segment_survey()]. Default `NULL`.
#' @param ... Passed to `read_narwc()` when `x` is a path — `profile`,
#'   `extra_columns`, `prefer_source` and so on.
#'
#' @return Invisibly, a list with whichever of `dat`, `findings` and `segments`
#'   the checks reached before a fatal problem stopped them, so investigating
#'   can carry on from there.
#'
#' @seealso [validate_narwc()] for the per-record checks this summarises,
#'   [line_effort()] and [reflight_summary()] for the per-line detail behind
#'   the effort totals, and `plot()` on the result of [segment_survey()].
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' invisible(diagnose_pipeline(path, seg_length = 5))
#'
#' @export
diagnose_pipeline <- function(x, days = NULL, seg_length = 10, species = NULL,
                              ...) {
  ok <- TRUE
  header <- function(s) cat("\n== ", s, " ==\n", sep = "")
  pass <- function(...) cat("  ok    ", ..., "\n", sep = "")
  warn <- function(...) {
    cat("  WARN  ", ..., "\n", sep = "")
    ok <<- FALSE
  }
  fail <- function(...) {
    cat("  FAIL  ", ..., "\n", sep = "")
    ok <<- FALSE
  }
  verdict <- function(res) {
    cat(if (ok) "\nNothing above needs attention.\n" else
      "\nAddress the WARN and FAIL lines before using these numbers.\n")
    invisible(res)
  }

  subset_of <- NULL
  cat("distsamp pipeline diagnosis\n")

  # --- Reading --------------------------------------------------------------
  header("Reading")
  dat <- tryCatch(
    if (is.character(x)) narwcr::read_narwc(x, quiet = TRUE, ...) else x,
    error = function(e) {
      fail("read_narwc() failed: ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(dat) || !is.data.frame(dat)) {
    return(verdict(list(dat = NULL)))
  }
  if (!nrow(dat)) {
    fail("0 records. Nothing downstream can say anything about an empty file.")
    return(verdict(list(dat = dat)))
  }
  pass(nrow(dat), " records, ", ncol(dat), " columns")

  map <- narwcr::narwc_column_mapping(dat)
  if (nrow(map)) {
    inferred <- sum(map$match == "inferred")
    if (inferred) {
      pass(inferred, " of ", nrow(map),
           " renames matched only after ignoring case and separators",
           " - `narwc_column_mapping()` lists them")
    }
    converted <- map[!is.na(map$factor), , drop = FALSE]
    for (i in seq_len(nrow(converted))) {
      pass(converted$original[i], " was rescaled by ", converted$factor[i],
           " to reach the unit `", converted$standardized[i], "` uses")
    }
  }

  displaced <- grep("_ORIGINAL$", names(dat), value = TRUE)
  for (nm in displaced) {
    pass(sub("_ORIGINAL$", "", nm), " was taken from the GPS track log; the",
         " file's own column is kept as `", nm, "`")
  }

  # Subsetting last in this section: `[` on a tibble drops the column mapping
  # attribute, and the reporting above reads it.
  if (!is.null(days)) {
    if (!"DATE" %in% names(dat)) {
      warn("`days` needs a DATE column to subset by, and there is none.",
           " Diagnosing the whole file")
    } else {
      all_days <- sort(unique(dat$DATE))
      keep <- if (identical(days, "auto")) {
        # The most survey-like day in the file: the one with the most census
        # records that also carry the criteria `flag_effort()` needs. Taking
        # the first day instead can land on one that records no altitude, and
        # a missing criterion fails every record — so the report says nothing
        # was on effort when the file is fine.
        usable <- rep(TRUE, nrow(dat))
        for (nm in c("ALT", "BEAUFORT", "VISIBLTY")) {
          if (nm %in% names(dat)) usable <- usable & !is.na(dat[[nm]])
        }
        if ("LEGTYPE" %in% names(dat)) {
          usable <- usable & !is.na(dat$LEGTYPE) & dat$LEGTYPE == 2
        }
        score <- tapply(usable, dat$DATE, sum)
        if (!any(score > 0)) {
          warn("no day has census records with every effort criterion",
               " recorded. Falling back to the first day")
          all_days[1]
        } else {
          as.Date(names(score)[which.max(score)])
        }
      } else if (is.numeric(days)) {
        utils::head(all_days, days)
      } else {
        asked <- as.Date(days)
        missing_days <- setdiff(as.character(asked), as.character(all_days))
        if (length(missing_days)) {
          warn("not in the data: ", paste(missing_days, collapse = ", "))
        }
        all_days[all_days %in% asked]
      }
      if (!length(keep)) {
        fail("`days` selected no survey day")
        return(verdict(list(dat = dat)))
      }
      if (length(keep) < length(all_days)) {
        dat <- dat[dat$DATE %in% keep, , drop = FALSE]
        subset_of <- length(all_days)
        how <- if (identical(days, "auto")) {
          paste0(keep, ", the day with the most census records carrying every",
                 " effort criterion")
        } else if (is.numeric(days)) {
          paste0("the first ", length(keep), " of ", length(all_days),
                 " survey days")
        } else {
          paste0(length(keep), " named day",
                 if (length(keep) > 1) "s" else "", ": ",
                 paste(keep, collapse = ", "))
        }
        pass("diagnosing ", how, " (", nrow(dat), " records). Every total and",
             " every finding below is for that subset",
             if (is.numeric(days)) {
               ", and the first days of a season are not always typical of it"
             } else "")
      }
    }
  }

  # --- Validation -----------------------------------------------------------
  header("Handbook validation")
  findings <- tryCatch(validate_narwc(dat), error = function(e) {
    fail("validate_narwc() failed: ", conditionMessage(e))
    NULL
  })
  if (is.null(findings)) {
    return(verdict(list(dat = dat)))
  }
  if (!nrow(findings)) {
    pass("no findings")
  } else {
    for (sev in c("error", "warning", "note")) {
      hit <- findings[findings$severity == sev, , drop = FALSE]
      for (i in seq_len(nrow(hit))) {
        msg <- paste0(hit$check[i], " (", hit$n[i], " records): ",
                      hit$message[i])
        if (sev == "error") fail(msg) else if (sev == "warning") warn(msg) else
          pass(msg)
      }
    }
  }

  # --- Platform -------------------------------------------------------------
  # distsamp is aerial by construction. A vessel record cannot meet an
  # altitude criterion, so it is excluded from effort rather than reported as
  # a different kind of survey.
  header("Platform")
  if (!"PLATFORM" %in% names(dat)) {
    pass("no PLATFORM column; every record is treated as one platform")
  } else {
    tab <- table(dat$PLATFORM, useNA = "ifany")
    pass(length(tab), " distinct PLATFORM value(s): ",
         paste(names(tab), unname(tab), sep = " x ", collapse = ", "))
    # Several PLATFORM values is not by itself a problem. The handbook gives
    # PLATFORM no code book, so the values identify particular platforms -
    # three aircraft over a multi-decade programme is ordinary. What matters
    # is whether they differ in *kind*, and speed answers that where the
    # column cannot.
    if (length(tab) > 1) {
      kinds <- tryCatch(narwcr::classify_platform(dat), error = function(e) NULL)
      other <- if (is.null(kinds)) NULL else kinds[!is.na(kinds) &
                                                     kinds != "aerial"]
      if (is.null(kinds)) {
        pass(length(tab), " platforms. PLATFORM has no code book, so these may",
             " be several aircraft or several kinds of platform; too little",
             " position and time data here to tell which")
      } else if (!length(other)) {
        pass("all of them moving at aerial survey speed - several airframes,",
             " not several kinds of platform")
      } else {
        warn(length(other), " records are on a platform not moving at aerial",
             " speed. `flag_effort()` cannot tell \"criterion failed\" from",
             " \"criterion does not apply\", so those are dropped from effort",
             " rather than handled. `prepare_aerial()` splits them after",
             " `make_leg_id()`, which is the only order that does not merge",
             " two occupations of one line into one")
      }
    }
  }

  # --- Line identity --------------------------------------------------------
  header("Line identity")
  dat <- tryCatch(narwcr::make_leg_id(dat), error = function(e) {
    fail("make_leg_id() failed: ", conditionMessage(e))
    NULL
  })
  if (is.null(dat)) {
    return(verdict(list(dat = dat, findings = findings)))
  }
  # `NA` is not an occupation — it is every record that belongs to no line,
  # the transit out and the ferry between lines.
  occs <- unique(stats::na.omit(dat$LEGNO3))
  pass(length(occs), " line occupation(s) over ",
       length(unique(dat$DATE)), " survey day(s), ",
       sum(is.na(dat$LEGNO3)), " record(s) on no line")

  kind <- table(sub("_[0-9]+$", "", occs))
  inferred <- unname(kind["derived"])
  if (!is.na(inferred)) {
    warn(inferred, " of those were inferred from runs of census track,",
         " on days recording neither a LEGNO nor a begin-line record.",
         " That is a guess about where lines start and stop")
  }

  if ("FILEID" %in% names(dat) && "DATE" %in% names(dat)) {
    n_days <- length(unique(dat$DATE))
    if (length(unique(dat$FILEID)) == 1L && n_days > 1L) {
      warn("FILEID is the same value on every record but the file covers ",
           n_days, " days. FILEID is only ever a grouping key, so nothing",
           " but DATE separates the days - see the effort check below")
    }
  }

  # --- Altitude -------------------------------------------------------------
  # Before effort, not after: ALT is one of the criteria `flag_effort()` uses,
  # so an altitude in the wrong unit presents as "nothing was on effort", and
  # the explanation is no use printed below the failure it caused.
  header("Altitude")
  if (!"ALT" %in% names(dat)) {
    warn("no ALT column. `perp_distance()` needs it, so declination-angle",
         " distances are unavailable")
  } else {
    med <- stats::median(dat$ALT, na.rm = TRUE)
    if (is.na(med)) {
      warn("ALT is missing on all ", nrow(dat), " records diagnosed",
           if (!is.null(subset_of)) {
             paste0(" - which is this subset, not necessarily the file. Run",
                    " without `days` before concluding the column is empty")
           } else "",
           ". `flag_effort()` fails a record on a missing criterion, so",
           " nothing here can be on effort")
    } else if (med > 366) {
      # 366 m is `flag_effort()`'s default ceiling, so a median above it means
      # nothing will survive to effort. The likeliest cause is a column that
      # was recorded in feet: `ALT` is metres throughout (handbook 8.A.1).
      warn("median ALT is ", round(med), " m, above the 366 m ceiling",
           " `flag_effort()` applies, so every record will be off effort.",
           if (med * 0.3048 <= 366) {
             paste0(" Read as feet it would be ", round(med * 0.3048),
                    " m, which is plausible - check the source column's unit.")
           } else "")
    } else {
      pass("median ALT ", round(med), " m")
    }
  }

  # --- Effort ---------------------------------------------------------------
  header("Effort")
  dat <- tryCatch(narwcr::flag_effort(dat), error = function(e) {
    fail("flag_effort() failed: ", conditionMessage(e))
    NULL
  })
  if (is.null(dat)) {
    return(verdict(list(dat = dat, findings = findings)))
  }
  n_on <- sum(dat$OnOff.Effort == 1, na.rm = TRUE)

  # Which criterion excluded the records, on `flag_effort()`'s own defaults.
  # Counted here rather than read back out of the result, because the result
  # records only that a record is off effort, not what put it there.
  if (n_on < nrow(dat)) {
    off <- dat$OnOff.Effort != 1 | is.na(dat$OnOff.Effort)
    # Missing counts as failing, because `flag_effort()` defaults to
    # `na_action = "fail"`. Reporting only the violations would name the wrong
    # culprit whenever a criterion column is empty — an absent ALT excludes
    # every record while showing nothing at all in this breakdown.
    absent <- function(nm) {
      if (!nm %in% names(dat)) nrow(dat) else sum(off & is.na(dat[[nm]]))
    }
    culprits <- list(
      c("BEAUFORT above 3", sum(off & !is.na(dat$BEAUFORT) & dat$BEAUFORT > 3)),
      c("BEAUFORT missing", absent("BEAUFORT")),
      c("ALT above 366 m", sum(off & !is.na(dat$ALT) & dat$ALT > 366)),
      c("ALT missing", absent("ALT")),
      c("VISIBLTY below 2", sum(off & !is.na(dat$VISIBLTY) & dat$VISIBLTY < 2)),
      c("VISIBLTY missing", absent("VISIBLTY")),
      c("LEGTYPE not 2", sum(off & !is.na(dat$LEGTYPE) & dat$LEGTYPE != 2)),
      c("LEGTYPE missing", absent("LEGTYPE"))
    )
    culprits <- Filter(function(p) as.integer(p[2]) > 0, culprits)
    if (length(culprits)) {
      cat("        off effort by criterion (defaults; a record can fail more",
          " than one):\n", sep = "")
      for (p in culprits) cat("          ", p[1], ": ", p[2], "\n", sep = "")
    }
  }

  if (!n_on) {
    fail("0 on-effort records. Every record failed at least one criterion -",
         " see the breakdown above")
    return(verdict(list(dat = dat, findings = findings)))
  }
  pass(n_on, " of ", nrow(dat), " records on effort")

  # A file with no DATE cannot have its days separated at all, which is worth
  # saying rather than erroring on — diagnosing that file is the point.
  has_date <- "DATE" %in% names(dat)
  by_now <- intersect(c("DATE", "FILEID", "LEGNO3"), names(dat))
  dat <- point_to_point_effort(dat, by = by_now)
  total <- sum(dat$pt2pt.effort)
  pass(round(total, 1), " km of on-effort track")

  if (!has_date) {
    warn("no DATE column, so effort is grouped by ",
         paste(by_now, collapse = " + "), " alone. If any LEGNO repeats",
         " across days, those days are merged and the distance between them",
         " is counted as on-effort track")
  } else {
    # The grouping hazard, quantified rather than described: if dropping DATE
    # changes the total, the difference is ferry distance being counted as
    # survey effort, and effort is the denominator of density.
    merged <- sum(
      point_to_point_effort(dat, by = c("FILEID", "LEGNO3"))$pt2pt.effort
    )
    if (!isTRUE(all.equal(merged, total))) {
      warn("grouping without DATE gives ", round(merged, 1), " km, ",
           round(merged / total, 1), "x this. That difference is the distance",
           " between survey days being counted as on-effort track")
    } else {
      pass("grouping without DATE gives the same total; no days are merging")
    }
  }

  # The receiver's own measurement against the reconstruction, where both
  # exist. A straight line between fixes is a chord, so the recorded total
  # should be a little larger; a lot larger means the fixes are far enough
  # apart to be cutting the corners of the track that was flown.
  if ("TRKDIST" %in% names(dat)) {
    rec <- sum(point_to_point_effort(dat, by = by_now,
                                     source = "recorded")$pt2pt.effort)
    ratio <- if (total > 0) rec / total else NA_real_
    if (!is.na(ratio) && ratio > 1.25) {
      warn("the receiver recorded ", round(rec, 1), " km, ", round(ratio, 2),
           "x the computed total. That gap means the fixes are far enough",
           " apart to be cutting the corners of the real track.",
           " `point_to_point_effort(source = \"recorded\")` uses TRKDIST")
    } else {
      pass("TRKDIST gives ", round(rec, 1), " km against ", round(total, 1),
           " km computed",
           if (!is.na(ratio)) paste0(" (", round(ratio, 2), "x)") else "",
           "; `source = \"recorded\"` uses it")
    }
  }

  # Is this an aerial survey at all? distsamp is aerial by construction - the
  # effort criteria are the handbook's aerial ones and `perp_distance()` is a
  # declination from an aircraft - but nothing in the data announces the
  # platform, and a vessel track runs through the whole pipeline returning
  # numbers that look entirely reasonable. Speed is the one thing that cannot
  # be mistaken.
  if (all(c("TIME", "LATITUDE", "LONGITUDE") %in% names(dat)) && nrow(dat) > 2) {
    tt <- sprintf("%06d", ifelse(is.na(dat$TIME), 0, round(dat$TIME)))
    tsec <- as.numeric(substr(tt, 1, 2)) * 3600 +
      as.numeric(substr(tt, 3, 4)) * 60 + as.numeric(substr(tt, 5, 6))
    gap <- diff(tsec)
    step <- gc_distance(utils::head(dat$LATITUDE, -1),
                        utils::head(dat$LONGITUDE, -1),
                        utils::tail(dat$LATITUDE, -1),
                        utils::tail(dat$LONGITUDE, -1)) * 1000
    use <- !is.na(gap) & gap > 0 & gap < 300 & !is.na(step)
    if (sum(use) > 20) {
      kn <- stats::median(step[use] / gap[use]) * 1.94384
      if (kn < 40) {
        warn("the platform is moving at a median ", round(kn),
             " knots. That is a vessel, not a survey aircraft - and distsamp",
             " is aerial by construction: the effort criteria are the",
             " handbook's aerial ones and `perp_distance()` is a declination",
             " angle from an aircraft. These numbers will look reasonable and",
             " mean something else")
      } else {
        pass("median speed ", round(kn), " knots, consistent with a survey",
             " aircraft")
      }
    }
  }

  # --- Distance sources -----------------------------------------------------
  header("Right-angle distance sources")
  is_sighting <- !is.na(dat$SPECCODE)
  n_sight <- sum(is_sighting)
  if (!n_sight) {
    pass("no sightings in this file; effort-only")
  } else {
    pass(n_sight, " sighting record(s)")
    have <- function(cols) {
      if (!all(cols %in% names(dat))) return(0L)
      sum(is_sighting & Reduce(`|`, lapply(cols, function(c) !is.na(dat[[c]]))))
    }
    for (src in list(
      list(n = have(c("ANGLEL", "ANGLER")), what = "a declination angle"),
      list(n = have(c("S_LAT", "S_LONG")), what = "an exact position"),
      list(n = have("STRIP"), what = "a strip code")
    )) {
      if (src$n) pass(src$n, " with ", src$what) else
        pass("none with ", src$what)
    }
    if (!have(c("ANGLEL", "ANGLER")) && !have(c("S_LAT", "S_LONG")) &&
        !have("STRIP")) {
      warn("no sighting carries any of the three distance sources, so no",
           " detection function can be fitted from this file")
    }
  }

  # --- Segments -------------------------------------------------------------
  header("Segments")
  seg <- tryCatch(
    segment_survey(dat, seg_length = seg_length, species = species),
    error = function(e) {
      fail("segment_survey() failed: ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(seg)) {
    return(verdict(list(dat = dat, findings = findings)))
  }
  n_seg <- nrow(seg$segments)
  if (!n_seg) {
    fail("0 segments. Every track was shorter than `min_track_km`")
    return(verdict(list(dat = dat, findings = findings, segments = seg)))
  }
  pass(n_seg, " segment(s) at seg_length = ", seg_length, " km")
  if ("seg_eff" %in% names(seg$segments)) {
    empty <- sum(seg$segments$seg_eff == 0, na.rm = TRUE)
    if (empty) {
      warn(empty, " segment(s) carry zero effort")
    } else {
      pass("every segment carries effort")
    }
  }

  verdict(list(dat = dat, findings = findings, segments = seg))
}
