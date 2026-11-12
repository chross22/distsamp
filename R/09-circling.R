#' Flag records made while circling
#'
#' Marks the records where the aircraft had left the census track to circle a
#' sighting.
#'
#' Two signals are used, either of which is sufficient:
#'
#' * `LEGTYPE == 4`, the line-transect "other (circling)" code (handbook
#'   8.A.21); and
#' * any record between a `LEGSTAGE == 3` (break off line to circle) and the
#'   following `LEGSTAGE == 4` (resume line) within the same survey line
#'   occupation (handbook 8.A.20).
#'
#' The second signal matters because a survey may log positions during circling
#' without changing `LEGTYPE`, and because the break-off and resume records
#' themselves stay at `LEGTYPE == 2`.
#'
#' @param dat A data frame of NARWC survey data in survey order, with `LEGTYPE`
#'   and ideally `LEGSTAGE` and `LEGNO3`.
#'
#' @return `dat` with an integer `CIRCLE` column: `1` while circling, `0`
#'   otherwise.
#'
#' @references
#' Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database: A
#' Guide for Users and Contributors, Version 8*, sections 8.A.20 and 8.A.21. NARWC Reference Document
#' 2023-01.
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' dat <- flag_circling(make_leg_id(read_narwc(path)))
#' sum(dat$CIRCLE)
#'
#' @export
flag_circling <- function(dat) {
  require_columns(dat, "LEGTYPE")

  # Empty input: add an empty column and return.
  if (is_empty_df(dat)) {
    dat$CIRCLE <- integer(0)
    return(dat)
  }

  # Signal 1: LEGTYPE 4 (circling).
  circ <- !is.na(dat$LEGTYPE) & dat$LEGTYPE == 4

  # Signal 2: records between a break-off (LEGSTAGE 3) and the next resume
  # (LEGSTAGE 4). Walk the records in order, keeping `state` = TRUE while a
  # circle is open. The state is reset at the start of each line occupation
  # (DATE + FILEID + LEGNO3), so a circle never runs on into the next line or
  # file. Without
  # LEGNO3 the whole table is one group.
  if ("LEGSTAGE" %in% names(dat)) {
    group <- if ("LEGNO3" %in% names(dat)) {
      # `[[`, not `$`: on a tibble `$` warns for a missing column on its way
      # to returning NULL.
      paste(dat[["DATE"]] %||% "", dat[["FILEID"]] %||% "", dat$LEGNO3)
    } else {
      rep("all", nrow(dat))
    }
    stage <- dat$LEGSTAGE
    open <- logical(nrow(dat))
    state <- FALSE
    prev <- NA_character_
    for (i in seq_len(nrow(dat))) {
      # New occupation: no circle is open.
      if (!identical(group[i], prev)) {
        state <- FALSE
        prev <- group[i]
      }
      # Break-off opens a circle. The record itself is still on the line.
      if (!is.na(stage[i]) && stage[i] == 3) {
        state <- TRUE
        open[i] <- FALSE
        next
      }
      # Resume closes it. The record itself is back on the line.
      if (!is.na(stage[i]) && stage[i] == 4) {
        state <- FALSE
        open[i] <- FALSE
        next
      }
      open[i] <- state
    }
    circ <- circ | open
  }

  dat$CIRCLE <- as.integer(circ)
  dat
}


#' Attach sightings made while circling to the segment they came from
#'
#' A group sighted from the census track is often circled for photographs, and
#' the position recorded for it is the one taken during circling, off effort.
#' Dropping those records loses detections that genuinely arose from on-effort
#' search. This function attributes them back to the segment that was in
#' progress when the aircraft broke off.
#'
#' @section What the protocol says:
#' Handbook 4.2 (event 11) sets out the CETAP rule: counted with the original
#' on-effort group are any further individuals *of the same species* seen while
#' circling that can reasonably be called associated, plus one further
#' unassociated group of the same species. Groups of *other* species, not
#' originally seen from the track-line, are new off-effort sightings and do not
#' belong to the segment.
#'
#' `mode = "same_species"` implements that rule: a circling sighting is attached
#' only when an on-effort group of the same species was seen before the
#' break-off (see "Which group"). It is the default.
#'
#' @section Which group:
#' The group circled animals are counted with is the most recent on-effort
#' sighting of the same species that is
#'
#' * in the same line occupation (`DATE`, `FILEID`, `LEGNO3`);
#' * after the previous resume (`LEGSTAGE == 4`) on that line, so a group
#'   circled earlier cannot collect animals from a later circle; and
#' * within `max_gap_km` of the point where the aircraft broke off.
#'
#' It may sit in an earlier segment than the circling record, because segment
#' boundaries are placed without regard to circling.
#'
#' @section Which distance:
#' "Counted with the original on-effort group" is also a statement about
#' distance. `distance = "with_group"` (the default) reads it literally: the
#' animals *are* that group, and a group has one distance, one detection
#' probability and one row. The animals are added to its `NUMBER` and no
#' second observation is made. This is right only where the animals really are
#' that group or associated with it, which is what `mode = "same_species"`
#' tests.
#'
#' `distance = "break_off"` reads the sighting as its own, with a distance
#' from the census line at the break-off:
#'
#' * Where the record carries an exact position (`S_LAT`/`S_LONG`), that
#'   position is projected perpendicularly onto the census line through the
#'   break-off, by [circling_distance()], and marked
#'   `distance_source == "circling"`. This is a perpendicular distance, though
#'   the position is fixed minutes after the detection.
#' * Otherwise it falls back to the great-circle distance from where the
#'   aircraft left the line to where the record was logged, marked
#'   `distance_source == "break_off"`. That is a straight-line distance from an
#'   off-effort position, not a perpendicular one. The logged position during a
#'   circle is the aircraft's, not the animal's, and a group circled twice
#'   before logging is further from the break-off than it ever was from the
#'   line.
#'
#' `"with_group"` and `"break_off"` will not agree. Which is nearer the truth
#' depends on how the circle was flown, which the records do not show. Run
#' both and compare if it matters to your estimate; `break_off_distance` is on
#' every attached record under either option.
#'
#' This function sets an attached record's distance itself, replacing any
#' `distance` it arrived with. The former option `distance = "inherit"` is no
#' longer accepted; naming it gives an error that explains why.
#'
#' @param chopped Point-level segmented data from [cut_segments()].
#' @param dat The full point-level data, including the off-effort records that
#'   segmentation left out, with `CIRCLE` from [flag_circling()].
#' @param mode `"same_species"` (default), `"all"`, or `"none"`; see Details.
#' @param distance What an attached record carries.
#'
#'   `"with_group"` (default) makes it no observation at all: the animals are
#'   added to the `NUMBER` of the on-effort sighting they were counted with,
#'   and the record is marked `circling_counted = FALSE` so
#'   [segment_sightings()] does not count them twice.
#'
#'   `"break_off"` makes it an observation of its own on a density surface.
#'   Its distance is the perpendicular distance of its exact position
#'   (`S_LAT`/`S_LONG`) from the census line where one exists, marked
#'   `distance_source == "circling"`, and otherwise the great-circle distance
#'   from the point on the line where the aircraft broke off, marked
#'   `distance_source == "break_off"`.
#'
#'   `break_off_distance` is computed under both, so the size of the
#'   disagreement is visible whichever is chosen. [detection_data()] excludes
#'   circling detections by default.
#' @param max_gap_km Furthest, in km, that the on-effort group may have been
#'   seen from the point where the aircraft left the line. Default `5`;
#'   [segment_survey()] passes `seg_length`. See "Which group".
#' @param units Units of `distance` under `distance = "break_off"`: `"m"`
#'   (default) or `"km"`, matching [segment_survey()]'s `distance_units`.
#'   `break_off_distance` is always metres.
#'
#' @return `chopped` with the attachable circling records appended, carrying the
#'   `seg_id`, `seg_no`, and `seg_eff` of the segment they were attached to and
#'   `case = "circling"`. Their `pt2pt.effort` is set to `0` so that attaching
#'   them cannot change any segment's length.
#'
#' @references
#' Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database: A
#' Guide for Users and Contributors, Version 8*, section 4.2 (event 11). NARWC
#' Reference Document 2023-01.
#'
#' CETAP (1982) *A Characterization of Marine Mammals and Turtles in the Mid- and
#' North-Atlantic Areas of the U.S. Outer Continental Shelf, Final Report.*
#' Cetacean and Turtle Assessment Program, University of Rhode Island. Bureau of
#' Land Management, Washington, DC.
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' dat <- point_to_point_effort(flag_effort(make_leg_id(read_narwc(path))))
#' dat <- split_tracks(dat)
#' chopped <- cut_segments(
#'   plan_segments(track_effort(dat), seg_length = 5, seed = 1), dat, seed = 1
#' )
#'
#' # Circling records are off effort, so cut_segments() left them out. This
#' # puts the sightings among them back onto the segment that was in progress
#' # when the aircraft broke off.
#' full <- flag_circling(dat)
#' with_circling <- attach_circling_sightings(chopped, full)
#' nrow(with_circling) - nrow(chopped)
#'
#' # The CETAP same-species rule is the default; "all" ignores it
#' nrow(attach_circling_sightings(chopped, full, mode = "all")) - nrow(chopped)
#'
#' # Attaching a record never changes a segment's length
#' identical(
#'   tapply(chopped$pt2pt.effort, chopped$seg_id, sum),
#'   tapply(with_circling$pt2pt.effort, with_circling$seg_id, sum)
#' )
#'
#' @seealso [flag_circling()], [segment_sightings()]
#' @export
attach_circling_sightings <- function(chopped, dat,
                                      mode = c("same_species", "all", "none"),
                                      distance = c("with_group",
                                                   "break_off"),
                                      units = c("m", "km"),
                                      max_gap_km = 5) {
  # 0. Check arguments. reject_removed_inherit() runs before match.arg() so
  #    the removed "inherit" option gets an explanation.
  mode <- match.arg(mode)
  units <- match.arg(units)
  check_gap_km(max_gap_km, "max_gap_km")
  reject_removed_inherit(distance, "distance")
  distance <- match.arg(distance)

  # Nothing to do under mode "none", with no segments, or without the columns
  # needed to find circling sightings.
  if (mode == "none" || is_empty_df(chopped)) {
    return(chopped)
  }
  if (!all(c("CIRCLE", "SPECCODE", "EVENTNO", "DATE") %in% names(dat))) {
    return(chopped)
  }

  # 1. Candidates: circling records (CIRCLE == 1) with a species code.
  #    `cand_rows` are their row numbers in `dat`.
  cand_rows <- which(
    !is.na(dat$CIRCLE) & dat$CIRCLE == 1 &
      !is.na(dat$SPECCODE) & dat$SPECCODE != ""
  )
  cand <- dat[cand_rows, , drop = FALSE]
  if (!nrow(cand)) {
    return(chopped)
  }

  # Every lookup below stays within one line occupation (DATE, FILEID,
  # LEGNO3). EVENTNO restarts in each file, so it orders records only within
  # one. `cand_occ` and `ch_occ` are the occupation keys of the candidates and
  # of the rows of `chopped`; `cand_ev` and `ch_ev` their event numbers.
  by <- default_track_grouping(dat)
  cand_occ <- group_key(cand, by)
  ch_occ <- group_key(chopped, by)
  cand_ev <- as.numeric(cand$EVENTNO)
  ch_ev <- as.numeric(chopped$EVENTNO)

  # 2. Break-off. For each candidate:
  #    ref_ev   - EVENTNO of its break-off: the latest LEGSTAGE == 3 record at
  #               or before it in the same occupation. If there is none (or no
  #               LEGSTAGE column), the candidate's own EVENTNO is used.
  #    floor_ev - EVENTNO of the last resume (LEGSTAGE == 4) before the
  #               break-off. The group must have been seen after it, so a
  #               group circled earlier cannot collect animals from a later
  #               circle. -Inf when there is no earlier resume.
  #    For each occupation, the break-off and resume event numbers are sorted
  #    and findInterval() finds the latest one at or before each event
  #    (strictly before, for the resume).
  ref_ev <- cand_ev
  floor_ev <- rep(-Inf, nrow(cand))
  if ("LEGSTAGE" %in% names(dat)) {
    dat_ev <- as.numeric(dat$EVENTNO)
    marks <- which(!is.na(dat_ev) & dat$LEGSTAGE %in% c(3, 4))
    by_occ <- split(marks, group_key(dat[marks, , drop = FALSE], by))
    cand_by <- split(seq_len(nrow(cand)), cand_occ)
    for (k in names(cand_by)) {
      i <- cand_by[[k]]
      m <- by_occ[[k]]
      brk <- sort(dat_ev[m][dat$LEGSTAGE[m] == 3])
      res <- sort(dat_ev[m][dat$LEGSTAGE[m] == 4])
      at <- findInterval(cand_ev[i], brk)
      ref_ev[i] <- ifelse(at >= 1L, brk[pmax(at, 1L)], cand_ev[i])
      r <- findInterval(ref_ev[i], res, left.open = TRUE)
      floor_ev[i] <- ifelse(r >= 1L, res[pmax(r, 1L)], -Inf)
    }
  }

  # Helper: for each event `ev` with occupation `key`, the latest row of
  # `chopped` among `rows` in the same occupation with EVENTNO at or before
  # `ev` (NA if none). Rows are split by occupation once, then one
  # findInterval() runs per occupation, so the cost stays linear in the number
  # of records.
  latest <- function(rows, ev, key) {
    out <- rep(NA_integer_, length(ev))
    rows <- rows[!is.na(ch_ev[rows])]
    rows_by <- split(rows, ch_occ[rows])
    key_by <- split(seq_along(ev), key)
    for (k in intersect(names(key_by), names(rows_by))) {
      r <- rows_by[[k]]
      r <- r[order(ch_ev[r])]
      i <- key_by[[k]]
      at <- findInterval(ev[i], ch_ev[r])
      out[i[at >= 1L]] <- r[at[at >= 1L]]
    }
    out
  }

  # 3. Anchor: the row of `chopped` for the last on-effort record at or before
  #    the break-off. Normally this is the break-off record itself. The
  #    candidate joins the anchor's segment, and distances are measured from
  #    the anchor's position. Restricted to on-effort rows so that, without
  #    LEGSTAGE, a candidate kept inside a track cannot be its own anchor.
  anchor <- latest(which(on_effort(chopped)), ref_ev, cand_occ)

  # 4. Group (`origin`): the row of `chopped` for the on-effort sighting the
  #    circled animals belong to. It is the most recent on-effort sighting of
  #    the same species in the same occupation that is
  #      - at or before the break-off (found per species with latest()),
  #      - after the previous resume (ch_ev > floor_ev), and
  #      - within max_gap_km of the anchor (great-circle distance, km).
  #    It may be in an earlier segment than the anchor. NA when there is none.
  seen <- which(!is.na(chopped$SPECCODE) & chopped$SPECCODE != "" &
                  on_effort(chopped))
  origin <- rep(NA_integer_, nrow(cand))
  for (sp in unique(cand$SPECCODE)) {
    i <- which(cand$SPECCODE == sp)
    origin[i] <- latest(seen[chopped$SPECCODE[seen] == sp], ref_ev[i],
                        cand_occ[i])
  }
  origin[!is.na(origin) & ch_ev[origin] <= floor_ev] <- NA_integer_
  near <- !is.na(origin) & !is.na(anchor)
  gap <- gc_distance(chopped$LATITUDE[origin[near]], chopped$LONGITUDE[origin[near]],
                     chopped$LATITUDE[anchor[near]], chopped$LONGITUDE[anchor[near]])
  origin[which(near)[is.na(gap) | gap > max_gap_km]] <- NA_integer_

  # 5. Rule. A candidate needs an anchor to be attached. Under the CETAP rule
  #    (mode "same_species", handbook 4.2) it also needs a group. `sel` marks
  #    the candidates to attach.
  sel <- !is.na(anchor)
  if (mode == "same_species") sel <- sel & !is.na(origin)
  if (!any(sel)) {
    return(chopped)
  }

  # 6. Build the attached rows (`extra`) from the selected candidates.
  #    at         - anchor row of each, in `chopped`
  #    at_origin  - group row of each, or NA
  #    The segment fields are copied from the anchor. pt2pt.effort is 0, so
  #    attaching never changes a segment's length. Distance fields start empty
  #    and are set in step 7.
  at <- anchor[sel]
  at_origin <- origin[sel]
  has_origin <- !is.na(at_origin)
  extra <- cand[sel, , drop = FALSE]
  for (nm in c("seg_id", "seg_no", "seg_eff", "new_trackno", "events")) {
    extra[[nm]] <- chopped[[nm]][at]
  }
  extra$case <- "circling"
  extra$pt2pt.effort <- 0
  extra$circling_counted <- TRUE
  extra$circling_merged <- NA_real_
  extra$distance <- NA_real_
  extra$side <- NA_character_
  extra$distance_source <- NA_character_

  # 7. Distances. break_off_distance is always set: metres from the anchor to
  #    the logged position (the aircraft's, during the circle). It is a check
  #    on the attachment, not a perpendicular distance.
  extra$break_off_distance <- gc_distance(
    chopped$LATITUDE[at], chopped$LONGITUDE[at],
    extra$LATITUDE, extra$LONGITUDE
  ) * 1000

  # 7a. "break_off": a detection of its own. Start from break_off_distance in
  #     `units` (source "break_off"). Where S_LAT/S_LONG give the sighting's
  #     position, replace it with that position's perpendicular distance from
  #     the line at the break-off (source "circling").
  if (identical(distance, "break_off")) {
    extra$distance <- extra$break_off_distance * (if (units == "km") 1 / 1000 else 1)
    extra$distance_source <- ifelse(is.na(extra$distance), NA_character_,
                                    "break_off")
    if (all(c("S_LAT", "S_LONG") %in% names(dat))) {
      perp <- circling_distance(dat, units = units)[cand_rows[sel], , drop = FALSE]
      has <- !is.na(perp$distance)
      extra$distance[has] <- perp$distance[has]
      extra$side[has] <- perp$side[has]
      extra$distance_source[has] <- "circling"
    }
  }

  # 7b. "with_group": no distance of its own. The candidates' NUMBER is added
  #     to their group's NUMBER in `chopped`, summed when several candidates
  #     share one group. Each merged candidate's own NUMBER is set to 0 and the
  #     amount moved is kept in `circling_merged`, so the animals are not
  #     counted twice. circling_counted = FALSE tells segment_sightings() to
  #     skip it. A candidate with no group (possible only under mode "all")
  #     stays a sighting of its own, with no distance.
  if (identical(distance, "with_group")) {
    if (!"NUMBER" %in% names(chopped)) {
      rlang::abort(paste0(
        "`circling_distance = \"with_group\"` adds the circling animals to ",
        "the group they were counted with, and this data has no `NUMBER` ",
        "column to add them to."
      ))
    }
    add <- as.numeric(extra$NUMBER)
    add[is.na(add)] <- 0
    merged <- has_origin & add > 0
    if (any(merged)) {
      by_origin <- tapply(add[merged], at_origin[merged], sum)
      rows <- as.integer(names(by_origin))
      chopped$NUMBER[rows] <- as.numeric(chopped$NUMBER[rows]) + as.numeric(by_origin)
    }
    extra$circling_counted <- !has_origin
    extra$circling_merged <- ifelse(merged, add, NA_real_)
    extra$NUMBER[merged] <- 0
  }

  # 8. Append the attached rows. Keep the columns `chopped` and `extra` share,
  #    plus the columns this function adds, which `chopped` may lack.
  added <- c("break_off_distance", "distance", "side", "distance_source",
             "circling_counted", "circling_merged")
  keep <- union(intersect(names(chopped), names(extra)), added)
  out <- dplyr::bind_rows(chopped, extra[, keep])
  # Sort in survey order. Sort by track and segment number, not by `seg_id`
  # text, which would put segment 19 before segment 2.
  dplyr::arrange(out, .data$DATE, as.numeric(.data$new_trackno), .data$seg_no,
                 .data$EVENTNO)
}


# Stop with an explanation when the removed option "inherit" is passed. Called
# before match.arg(), which would otherwise give a generic "should be one of"
# error. Used by segment_survey() and attach_circling_sightings().
reject_removed_inherit <- function(distance, arg) {
  if (identical(distance, "inherit")) {
    rlang::abort(paste0(
      "`", arg, " = \"inherit\"` was removed. It gave the circling record an ",
      "observation of\nits own carrying the on-effort group's perpendicular ",
      "distance - which produced the\nexact same estimate as ",
      "`\"with_group\"`, segment for segment, while adding a row that\n",
      "claimed a distance nothing was detected at. Use `\"with_group\"`."
    ))
  }
  invisible(distance)
}

# Stop unless `x` is a single non-negative number (a distance in km).
check_gap_km <- function(x, arg, call = rlang::caller_env()) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || x < 0) {
    rlang::abort(paste0("`", arg, "` must be one non-negative number of km."),
                 call = call)
  }
  invisible(x)
}
