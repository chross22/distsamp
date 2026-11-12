#' Diagnose common reasons a segmentation might be wrong before you trust it
#'
#' Runs the reading and segmentation pipeline (`read_narwc()`,
#' [validate_narwc()], `make_leg_id()`, `flag_effort()`,
#' [point_to_point_effort()] and [segment_survey()]) and reports the ways a
#' real extract goes wrong quietly. Run it once against a new dataset, before
#' any of its numbers are used.
#'
#' The target is not the failure that errors. It is the failure that returns a
#' plausible number: effort that silently includes the ferry between two survey
#' days, an altitude read as metres when the column was in feet, a position
#' taken from the vessel when the aircraft's GPS track was in the file. Each
#' gives a density estimate that is wrong by a factor and looks reasonable.
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
#'   `"auto"` is the recommended choice. The start of a season is often
#'   atypical: a day may lack the altitude or sea state the rest of the file
#'   records. Every criterion fails on a missing value, so an unrepresentative
#'   day reports no effort at all while the file is fine.
#'
#'   Whole days are kept, never a sample of records. Effort and segmentation
#'   are computed from consecutive positions along a line, so a random subset
#'   of records would report distances across gaps created by the sampling.
#'   Every total printed is for the subset, and the header says so.
#' @param platform `"aerial"` (default), `"vessel"`, or `"ship"` as a synonym
#'   for `"vessel"`. The platform the file is believed to hold. Every check
#'   that depends on it (the altitude ceiling, the expected speed, which
#'   distance sources can exist) uses this, and it is passed on to
#'   [segment_survey()]. See [platform_defaults()].
#' @param seg_length Segment length in km, passed to [segment_survey()].
#'   Default `10`.
#' @param species Passed to [segment_survey()]. Default `NULL`.
#' @param ... Passed to `read_narwc()` when `x` is a path: `profile`,
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
                              platform = c("aerial", "vessel", "ship"), ...) {
  # Platform settings: effort criteria and distance sources (`defaults`) and
  # the expected speed range in knots (`band`).
  platform <- resolve_platform(platform)
  defaults <- platform_defaults(platform)
  band <- platform_speed_band(platform)

  # Report helpers. `ok` turns FALSE on the first WARN or FAIL; `verdict()`
  # prints the closing line and returns what has been computed so far.
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

  # Number of survey days in the full file when `days` subsets it, else NULL.
  subset_of <- NULL
  cat("distsamp pipeline diagnosis, as a ", defaults$kind, " survey\n",
      sep = "")

  # --- Reading --------------------------------------------------------------
  # Read the file (or take the data frame as given). Stop on failure or on an
  # empty result.
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

  # Report column renames matched loosely, and columns rescaled to the
  # standard unit.
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

  # Report columns replaced from the GPS track log; the reader keeps the
  # file's own values as <NAME>_ORIGINAL.
  displaced <- grep("_ORIGINAL$", names(dat), value = TRUE)
  for (nm in displaced) {
    pass(sub("_ORIGINAL$", "", nm), " was taken from the GPS track log; the",
         " file's own column is kept as `", nm, "`")
  }

  # Restrict to the requested survey days. This comes last in the section
  # because `[` on a tibble drops the column-mapping attribute read above.
  if (!is.null(days)) {
    if (!"DATE" %in% names(dat)) {
      warn("`days` needs a DATE column to subset by, and there is none.",
           " Diagnosing the whole file")
    } else {
      all_days <- sort(unique(dat$DATE))
      keep <- if (identical(days, "auto")) {
        # Pick the day with the most census records (LEGTYPE 2) that carry
        # every criterion `flag_effort()` needs. The first day may record no
        # altitude, and a missing criterion fails every record, so it would
        # report no effort for a file that is fine.
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
        # A number: the first `days` survey days.
        utils::head(all_days, days)
      } else {
        # Dates: exactly those days, warning about any not in the data.
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
      # Subset only when it removes something, and say which days were kept.
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
  # Run the per-record checks. Errors print as FAIL, warnings as WARN, and
  # notes as ok.
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
  # Checked against the platform the caller named. Under the aerial criteria
  # a vessel record cannot meet the altitude ceiling, so it leaves effort
  # silently. This section catches that.
  header("Platform")
  if (!"PLATFORM" %in% names(dat)) {
    pass("no PLATFORM column; every record is treated as one platform")
  } else {
    tab <- table(dat$PLATFORM, useNA = "ifany")
    pass(length(tab), " distinct PLATFORM value(s): ",
         paste(names(tab), unname(tab), sep = " x ", collapse = ", "))
    # Several PLATFORM values are not a problem in themselves. PLATFORM has no
    # code book, so the values name particular platforms; three aircraft over
    # several decades is ordinary. What matters is whether they differ in
    # *kind*. classify_platform() decides that from speed, which the column
    # cannot tell.
    if (length(tab) > 1) {
      kinds <- tryCatch(narwcr::classify_platform(dat), error = function(e) NULL)
      other <- if (is.null(kinds)) NULL else kinds[!is.na(kinds) &
                                                     kinds != defaults$kind]
      if (is.null(kinds)) {
        pass(length(tab), " platforms. PLATFORM has no code book, so these may",
             " be several ", band$several, " or several kinds of platform;",
             " too little position and time data here to tell which")
      } else if (!length(other)) {
        pass("all of them moving at ", defaults$kind, " survey speed -",
             " several ", band$several, ", not several kinds of platform")
      } else {
        warn(length(other), " records are on a platform not moving at ",
             defaults$kind, " speed. `flag_effort()` cannot tell \"criterion",
             " failed\" from \"criterion does not apply\", so those are",
             " dropped from effort rather than handled.",
             " `prepare_survey(platform = \"", defaults$kind, "\")` splits",
             " them after `make_leg_id()`, which is the only order that does",
             " not merge two occupations of one line into one")
      }
    }
  }

  # --- Line identity --------------------------------------------------------
  # Assign line-occupation IDs (LEGNO3).
  header("Line identity")
  # On failure, return the last data that worked, as documented in @return.
  next_dat <- tryCatch(narwcr::make_leg_id(dat), error = function(e) {
    fail("make_leg_id() failed: ", conditionMessage(e))
    NULL
  })
  if (is.null(next_dat)) {
    return(verdict(list(dat = dat, findings = findings)))
  }
  dat <- next_dat
  # Count occupations. An NA LEGNO3 is not an occupation: it marks records on
  # no line (the transit out and the ferry between lines).
  occs <- unique(stats::na.omit(dat$LEGNO3))
  pass(length(occs), " line occupation(s) over ",
       if ("DATE" %in% names(dat)) length(unique(dat$DATE)) else "an unknown number of",
       " survey day(s), ",
       sum(is.na(dat$LEGNO3)), " record(s) on no line")

  # IDs prefixed "derived" were inferred from runs of census track rather
  # than read from LEGNO or a begin-line record.
  kind <- table(sub("_[0-9]+$", "", occs))
  inferred <- unname(kind["derived"])
  if (!is.na(inferred)) {
    warn(inferred, " of those were inferred from runs of census track,",
         " on days recording neither a LEGNO nor a begin-line record.",
         " That is a guess about where lines start and stop")
  }

  # A constant FILEID across several days leaves DATE as the only separator.
  if ("FILEID" %in% names(dat) && "DATE" %in% names(dat)) {
    n_days <- length(unique(dat$DATE))
    if (length(unique(dat$FILEID)) == 1L && n_days > 1L) {
      warn("FILEID is the same value on every record but the file covers ",
           n_days, " days. FILEID is only ever a grouping key, so nothing",
           " but DATE separates the days - see the effort check below")
    }
  }

  # --- Altitude -------------------------------------------------------------
  # Checked before effort. ALT is an effort criterion, so an altitude in the
  # wrong unit shows up as "nothing was on effort". The cause should print
  # above that symptom.
  header("Altitude")
  if (platform == "vessel") {
    # A vessel has no altitude, so neither the criterion nor the unit check
    # applies. Say so explicitly rather than print nothing.
    pass("not a criterion for a vessel, and not checked. `flag_effort()` is",
         " called with `max_alt_m = NULL`, because a missing ALT fails any",
         " ceiling - see `platform_defaults(\"vessel\")`")
  } else if (!"ALT" %in% names(dat)) {
    warn("no ALT column. `perp_distance()` needs it, so declination-angle",
         " distances are unavailable")
  } else {
    # Median altitude in metres, over the records diagnosed.
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
      # almost nothing reaches effort. The likeliest cause is a column recorded
      # in feet; ALT is metres (handbook 8.A.1). 1 ft = 0.3048 m.
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
  # Flag on-effort records with the platform's criteria.
  header("Effort")
  next_dat <- tryCatch(
    flag_effort_for_platform(dat, defaults$effort_args),
    error = function(e) {
      fail("flag_effort() failed: ", conditionMessage(e))
      NULL
    }
  )
  if (is.null(next_dat)) {
    return(verdict(list(dat = dat, findings = findings)))
  }
  dat <- next_dat
  n_on <- sum(dat$OnOff.Effort == 1, na.rm = TRUE)

  # Count which criterion excluded the off-effort records, using
  # `flag_effort()`'s default thresholds. The result of `flag_effort()` says
  # only that a record is off effort, not why, so the counts are made here.
  if (n_on < nrow(dat)) {
    off <- dat$OnOff.Effort != 1 | is.na(dat$OnOff.Effort)
    # Missing values count as failing, because `flag_effort()` defaults to
    # `na_action = "fail"`. Without this, an empty ALT column would exclude
    # every record and show nothing in the breakdown. An absent column counts
    # every record.
    absent <- function(nm) {
      if (!nm %in% names(dat)) nrow(dat) else sum(off & is.na(dat[[nm]]))
    }
    culprits <- c(
      list(
        c("BEAUFORT above 3",
          sum(off & !is.na(dat$BEAUFORT) & dat$BEAUFORT > 3)),
        c("BEAUFORT missing", absent("BEAUFORT"))
      ),
      # ALT is not a criterion for a vessel, so it is not listed.
      if (platform == "vessel") list() else list(
        c("ALT above 366 m", sum(off & !is.na(dat$ALT) & dat$ALT > 366)),
        c("ALT missing", absent("ALT"))
      ),
      list(
        c("VISIBLTY below 2",
          sum(off & !is.na(dat$VISIBLTY) & dat$VISIBLTY < 2)),
        c("VISIBLTY missing", absent("VISIBLTY")),
        # LEGTYPE 5 and 6 are shipboard codes for platforms of opportunity,
        # not designed lines. They are off effort for a vessel as for an
        # aircraft. See `platform_defaults()`.
        c("LEGTYPE not 2", sum(off & !is.na(dat$LEGTYPE) & dat$LEGTYPE != 2)),
        c("LEGTYPE missing", absent("LEGTYPE"))
      )
    )
    # Print only the criteria that excluded at least one record.
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

  # Total on-effort distance in km, grouped by whichever of DATE, FILEID and
  # LEGNO3 exist. A file with no DATE cannot have its days separated; that is
  # reported below rather than raised as an error.
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
    # Measure the grouping hazard. Recompute effort without DATE; any
    # difference is ferry distance between days counted as survey effort.
    merged <- sum(
      point_to_point_effort(dat, by = setdiff(by_now, "DATE"))$pt2pt.effort
    )
    if (!isTRUE(all.equal(merged, total))) {
      warn("grouping without DATE gives ", round(merged, 1), " km, ",
           round(merged / total, 1), "x this. That difference is the distance",
           " between survey days being counted as on-effort track")
    } else {
      pass("grouping without DATE gives the same total; no days are merging")
    }
  }

  # Compare the receiver's recorded distance (TRKDIST) with the computed
  # total. A straight line between fixes is a chord, so the recorded total
  # should be slightly larger. More than 25% larger means the fixes are far
  # enough apart to cut the corners of the track flown.
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

  # Check that the platform matches the one named. Nothing in the data states
  # it, and either kind of track runs through the pipeline under the other's
  # criteria with plausible-looking results. Speed distinguishes them.
  if (all(c("TIME", "LATITUDE", "LONGITUDE") %in% names(dat)) && nrow(dat) > 2) {
    # TIME is HHMMSS as a number; convert to seconds since midnight.
    tt <- sprintf("%06d", ifelse(is.na(dat$TIME), 0, round(dat$TIME)))
    tsec <- as.numeric(substr(tt, 1, 2)) * 3600 +
      as.numeric(substr(tt, 3, 4)) * 60 + as.numeric(substr(tt, 5, 6))
    # Time gap (s) and distance (m) between consecutive records.
    gap <- diff(tsec)
    step <- gc_distance(utils::head(dat$LATITUDE, -1),
                        utils::head(dat$LONGITUDE, -1),
                        utils::tail(dat$LATITUDE, -1),
                        utils::tail(dat$LONGITUDE, -1)) * 1000
    # Use only gaps of 1 s to 5 min, and only with more than 20 of them. Median
    # speed in m/s is converted to knots (1 m/s = 1.94384 kn).
    use <- !is.na(gap) & gap > 0 & gap < 300 & !is.na(step)
    if (sum(use) > 20) {
      kn <- stats::median(step[use] / gap[use]) * 1.94384
      if (kn < band$min || kn > band$max) {
        # Name what the speed looks like: under 2 kn barely moving, under
        # 40 kn a vessel, otherwise an aircraft.
        seen <- if (kn < 2) "a platform barely moving" else
          if (kn < 40) "a vessel" else "a survey aircraft"
        warn("the platform is moving at a median ", round(kn),
             " knots. That is ", seen, ", not ", band$what, " - and this run",
             " is applying the ", defaults$kind, " platform's effort criteria",
             " and distance sources to it. These numbers will look reasonable",
             " and mean something else. `platform = \"",
             if (kn < 40) "vessel" else "aerial", "\"` is what this file",
             " looks like")
      } else {
        pass("median speed ", round(kn), " knots, consistent with ",
             band$what)
      }
    }
  }

  # --- Distance sources -----------------------------------------------------
  # Count sightings that carry each distance source the platform can use.
  header("Right-angle distance sources")
  # A sighting has a non-blank species code, as everywhere else.
  has_spec <- "SPECCODE" %in% names(dat)
  is_sighting <- if (has_spec) {
    !is.na(dat$SPECCODE) & dat$SPECCODE != ""
  } else {
    rep(FALSE, nrow(dat))
  }
  n_sight <- sum(is_sighting)
  if (!has_spec) {
    warn("no SPECCODE column, so sightings cannot be identified")
  } else if (!n_sight) {
    pass("no sightings in this file; effort-only")
  } else {
    pass(n_sight, " sighting record(s)")
    # Number of sightings with a value in any of `cols`; 0 if a column is
    # absent.
    have <- function(cols) {
      if (!all(cols %in% names(dat))) return(0L)
      sum(is_sighting & Reduce(`|`, lapply(cols, function(c) !is.na(dat[[c]]))))
    }
    # Only the sources this platform can use. A declination-angle distance is
    # altitude divided by a tangent, so it does not exist on a vessel.
    usable <- list(
      angle = list(n = have(c("ANGLEL", "ANGLER")),
                   what = "a declination angle"),
      exact = list(n = have(c("S_LAT", "S_LONG")),
                   what = "an exact position"),
      strip = list(n = have("STRIP"), what = "a strip code")
    )[defaults$distance_sources]
    for (src in usable) {
      if (src$n) pass(src$n, " with ", src$what) else
        pass("none with ", src$what)
    }
    # On a vessel, note aircraft-only measurements present but not used.
    if (platform == "vessel") {
      aerial_only <- have(c("ANGLEL", "ANGLER")) + have("STRIP")
      if (aerial_only) {
        pass(aerial_only, " sighting record(s) carry a declination angle or a",
             " strip code as well. Both are aircraft measurements and are not",
             " read here - see `platform_defaults(\"vessel\")`")
      }
    }
    if (!sum(vapply(usable, function(src) src$n, integer(1)))) {
      warn("no sighting carries any distance source this platform can use",
           " (", paste(defaults$distance_sources, collapse = ", "), "), so no",
           " detection function can be fitted from this file")
    }
  }

  # --- Segments -------------------------------------------------------------
  # Segment the survey and check that segments exist and carry effort.
  header("Segments")
  seg <- tryCatch(
    segment_survey(dat, seg_length = seg_length, species = species,
                   platform = platform),
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
