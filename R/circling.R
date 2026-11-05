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

  if (is_empty_df(dat)) {
    dat$CIRCLE <- integer(0)
    return(dat)
  }

  circ <- !is.na(dat$LEGTYPE) & dat$LEGTYPE == 4

  if ("LEGSTAGE" %in% names(dat)) {
    group <- if ("LEGNO3" %in% names(dat)) {
      # `[[`, not `$`: on a tibble `$` warns for a missing column on its way
      # to returning NULL.
      paste(dat[["DATE"]] %||% "", dat$LEGNO3)
    } else {
      rep("all", nrow(dat))
    }
    stage <- dat$LEGSTAGE
    open <- logical(nrow(dat))
    state <- FALSE
    prev <- NA_character_
    for (i in seq_len(nrow(dat))) {
      if (!identical(group[i], prev)) {
        state <- FALSE
        prev <- group[i]
      }
      if (!is.na(stage[i]) && stage[i] == 3) {
        state <- TRUE
        open[i] <- FALSE # the break-off record itself is still on the line
        next
      }
      if (!is.na(stage[i]) && stage[i] == 4) {
        state <- FALSE
        open[i] <- FALSE # the resume record is back on the line
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
#' It may sit in an earlier segment than the circling record. Segment
#' boundaries know nothing of circling, and an earlier version that searched
#' only the segment in progress dropped the circled animals whenever a boundary
#' fell between the sighting and the break-off.
#'
#' @section Which distance:
#' "Counted with the original on-effort group" is also a statement about
#' distance. `distance = "with_group"` (the default) reads it literally: if
#' these animals are counted with the original group then they *are* that
#' group, and a group has one distance, one detection probability and one row.
#' The animals are added to its `NUMBER` and no second observation is made.
#' Nothing is inherited or constructed. What this does not remove is the
#' judgement underneath: it is right only where the animals really are that
#' group or associated with it, which is what `mode = "same_species"` is
#' testing.
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
#'   `distance_source == "break_off"`. That is a slant distance from an
#'   off-effort position, not a perpendicular one, and a group circled twice
#'   before logging is further from the break-off than it ever was from the
#'   line. The logged position during a circle is the aircraft's, not the
#'   animal's.
#'
#' `"with_group"` and `"break_off"` will not agree, and which is nearer the
#' truth depends on how the circle was actually flown, which the records do not
#' record.
#'
#' An earlier `distance = "inherit"` gave the circling record a row of its own
#' carrying the on-effort group's perpendicular distance. It produced the same
#' estimate as `"with_group"`, segment for segment, while adding a row that
#' claimed a distance nothing was detected at, and it was removed. Naming it
#' now errors with that explanation.
#'
#' This function sets an attached record's distance itself, replacing any
#' `distance` it arrived with.
#'
#' Run them and compare if it matters to your estimate; `break_off_distance` is
#' on every attached record whichever is chosen, so the comparison needs no
#' re-segmentation to see the size of it.
#'
#' The original processing code instead hard-coded right whales, attaching every
#' circling right whale and discarding circling sightings of everything else.
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
#'   [segment_sightings()] does not count them twice. Nothing is inherited or
#'   constructed.
#'
#'   `"break_off"` makes it an observation of its own on a density surface.
#'   Its distance is the perpendicular distance of its exact position
#'   (`S_LAT`/`S_LONG`) from the census line where one exists, marked
#'   `distance_source == "circling"`, and otherwise the great-circle distance
#'   from the point on the line where the aircraft broke off, marked
#'   `distance_source == "break_off"`.
#'
#'   `break_off_distance` is computed under both, so the size of the
#'   disagreement is visible whichever is chosen. No option puts a circling
#'   record into a detection function — [detection_data()] excludes them all.
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
  mode <- match.arg(mode)
  units <- match.arg(units)
  stopifnot(is.numeric(max_gap_km), length(max_gap_km) == 1L,
            !is.na(max_gap_km), max_gap_km >= 0)
  reject_removed_inherit(distance, "distance")
  distance <- match.arg(distance)

  # A circle logged as a single record does not split the track: track
  # splitting treats one off-effort record between on-effort ones as on effort,
  # so cut_segments() keeps it. A circling sighting kept that way was counted
  # as an ordinary sighting and then again when attached below - and counted
  # even under `mode = "none"`. Attachment is the only way a circling sighting
  # reaches a segment, so any already there is removed first. Its effort is
  # zero (it is off effort), so no segment changes length.
  if ("CIRCLE" %in% names(chopped) && "SPECCODE" %in% names(chopped)) {
    leaked <- !is.na(chopped$CIRCLE) & chopped$CIRCLE == 1 &
      !is.na(chopped$SPECCODE) & chopped$SPECCODE != ""
    chopped <- chopped[!leaked, , drop = FALSE]
  }

  if (mode == "none" || is_empty_df(chopped)) {
    return(chopped)
  }
  if (!all(c("CIRCLE", "SPECCODE", "EVENTNO", "DATE") %in% names(dat))) {
    return(chopped)
  }

  cand_rows <- which(
    !is.na(dat$CIRCLE) & dat$CIRCLE == 1 &
      !is.na(dat$SPECCODE) & dat$SPECCODE != ""
  )
  cand <- dat[cand_rows, , drop = FALSE]
  if (!nrow(cand)) {
    return(chopped)
  }

  # Each segment's identity, for copying onto the records attached to it.
  # `na.last = FALSE`, so a record with no event number never sets a bound.
  by_event <- chopped[order(chopped$EVENTNO, na.last = FALSE), , drop = FALSE]
  bounds <- dplyr::summarise(
    dplyr::group_by(by_event, .data$DATE, .data$seg_id),
    seg_no = dplyr::first(.data$seg_no),
    seg_eff = dplyr::first(.data$seg_eff),
    new_trackno = dplyr::first(.data$new_trackno),
    first_event = min(.data$EVENTNO, na.rm = TRUE),
    last_event = max(.data$EVENTNO, na.rm = TRUE),
    .groups = "drop"
  )

  # Line occupation of each record, so nothing is looked for across lines.
  occ_cols <- intersect(c("DATE", "FILEID", "LEGNO3"), names(dat))
  occ_key <- function(df) {
    do.call(paste, c(lapply(occ_cols, function(nm) as.character(df[[nm]])),
                     sep = "\r"))
  }
  cand_occ <- occ_key(cand)
  cand_ev <- as.numeric(cand$EVENTNO)

  # The break-off each candidate belongs to: the latest `LEGSTAGE == 3` at or
  # before it in its occupation. And the previous resume (`LEGSTAGE == 4`)
  # before that break-off, which bounds how far back its group is looked for.
  # Without `LEGSTAGE`, or with no break-off record, the candidate's own event
  # stands in for the break-off and there is no lower bound.
  ref_ev <- cand_ev
  floor_ev <- rep(-Inf, nrow(cand))
  if ("LEGSTAGE" %in% names(dat)) {
    dat_occ <- occ_key(dat)
    dat_ev <- as.numeric(dat$EVENTNO)
    stage <- dat$LEGSTAGE
    for (k in unique(cand_occ)) {
      i <- which(cand_occ == k)
      in_occ <- dat_occ == k & !is.na(dat_ev) & !is.na(stage)
      brk <- sort(dat_ev[in_occ & stage == 3])
      res <- sort(dat_ev[in_occ & stage == 4])
      at <- findInterval(cand_ev[i], brk)
      ref_ev[i] <- ifelse(at >= 1L, brk[pmax(at, 1L)], cand_ev[i])
      r <- findInterval(ref_ev[i], res, left.open = TRUE)
      floor_ev[i] <- ifelse(r >= 1L, res[pmax(r, 1L)], -Inf)
    }
  }

  # The anchor: the last on-effort record at or before the break-off, on the
  # same day. With a break-off record on effort, that is the break-off record
  # itself. The candidate joins the anchor's segment, and distances are
  # measured from the anchor's position.
  #
  # Anchored on the break-off rather than on segment ends. A circle logged as
  # a single record does not split the track, so the break-off and the resume
  # can share a segment whose last event is after the circle; looking for the
  # segment that ended before the circle then picked the one before that, and
  # measured from its far end.
  #
  # One `findInterval()` per day. A per-candidate scan makes this
  # O(candidates x records), which is invisible while circling is rare and
  # quadratic when it is not - and on right whale surveys it is not.
  anchor <- rep(NA_integer_, nrow(cand))
  cand_day <- as.character(cand$DATE)
  ch_day <- as.character(chopped$DATE)
  for (day in unique(cand_day)) {
    rows <- which(ch_day == day & !is.na(chopped$EVENTNO))
    if (!length(rows)) next
    rows <- rows[order(chopped$EVENTNO[rows])]
    i <- which(cand_day == day)
    pos <- findInterval(ref_ev[i], as.numeric(chopped$EVENTNO[rows]))
    hit <- pos >= 1L
    anchor[i[hit]] <- rows[pos[hit]]
  }
  target <- match(chopped$seg_id[anchor], bounds$seg_id)
  break_lat <- chopped$LATITUDE[anchor]
  break_lon <- chopped$LONGITUDE[anchor]

  sel <- !is.na(target)

  # The on-effort sighting each candidate belongs to, where there is one: the
  # LAST of its own species seen from the line before the break-off, in the
  # same line occupation, and since the aircraft last rejoined that line. The
  # group most recently seen is the one the aircraft turned back for - taking
  # whichever row happened to come first in the frame would make the result
  # depend on row order, which is not a fact about the survey.
  #
  # Searched over the occupation, not the segment. Segment boundaries are
  # placed by the segmentation and know nothing of circling, so one can fall
  # between a sighting and the break-off it prompted. Searching only the
  # segment in progress then found no group, and under `"same_species"` the
  # circled animals were dropped: neither counted with their group nor
  # attached anywhere.
  #
  # Bounded below by the previous resume (`LEGSTAGE == 4`), so a group circled
  # earlier on the same line cannot collect animals from a later circle. With
  # no `LEGSTAGE` there is no such bound and the whole occupation is searched.
  #
  # This row is where `with_group` adds the animals, and the same-species rule:
  # no row, no attachment.
  #
  # Done with one `findInterval()` per occupation and species, and it has to
  # stay vectorised. A per-candidate scan makes this O(candidates x records),
  # which is invisible while circling is rare and quadratic when it is not -
  # and on right whale surveys it is not.
  seen <- which(!is.na(chopped$SPECCODE) & chopped$SPECCODE != "" &
                  !is.na(chopped$EVENTNO))
  seen_key <- paste(occ_key(chopped)[seen], chopped$SPECCODE[seen], sep = "\r")
  cand_key <- paste(cand_occ, cand$SPECCODE, sep = "\r")
  origin <- rep(NA_integer_, nrow(cand))
  for (k in intersect(unique(cand_key), seen_key)) {
    rows <- seen[seen_key == k]
    rows <- rows[order(chopped$EVENTNO[rows])]
    ev <- as.numeric(chopped$EVENTNO[rows])
    i <- which(cand_key == k)
    at <- findInterval(ref_ev[i], ev)
    hit <- at >= 1L
    hit[hit] <- ev[at[hit]] > floor_ev[i][hit]
    origin[i[hit]] <- rows[at[hit]]
  }

  # And near enough to the break-off to be what the aircraft turned back for.
  # The occupation bound alone would let a group seen 20 km back collect the
  # animals; the old per-segment search prevented that, but only by accident
  # of where the boundaries fell. Measured from the sighting's record to where
  # the aircraft left the line.
  near <- !is.na(origin) & !is.na(target)
  if (any(near)) {
    gap <- gc_distance(
      chopped$LATITUDE[origin[near]], chopped$LONGITUDE[origin[near]],
      break_lat[near], break_lon[near]
    )
    far <- is.na(gap) | gap > max_gap_km
    origin[which(near)[far]] <- NA_integer_
  }

  if (mode == "same_species") {
    # Handbook 4.2 / the CETAP rule: a circling sighting joins the segment only
    # if that segment already holds one of the same species.
    sel <- sel & !is.na(origin)
  }

  if (!any(sel)) {
    return(chopped)
  }

  extra <- cand[sel, , drop = FALSE]
  at <- target[sel]
  extra$seg_id <- bounds$seg_id[at]
  extra$seg_no <- bounds$seg_no[at]
  extra$seg_eff <- bounds$seg_eff[at]
  extra$new_trackno <- bounds$new_trackno[at]
  extra$events <- paste(bounds$first_event[at], bounds$last_event[at], sep = "_")
  extra$case <- "circling"
  # Attaching a record must not change how long the segment is.
  extra$pt2pt.effort <- 0

  # Whether the attached record becomes a detection of its own.
  #
  # It always did, and under `with_group` it must not: those animals are added
  # to the group they were counted with instead, so counting them again here
  # would count them twice. The record still rides along - its position is
  # where the animals were logged, which is the only record of that - and
  # `segment_sightings()` skips it.
  extra$circling_counted <- TRUE
  extra$circling_merged <- NA_real_

  # A circling record carries no perpendicular distance of its own, and none
  # is invented for it.
  #
  # No angle was taken while circling and none could have been, so there is
  # nothing to compute one from. An earlier version copied the on-effort
  # group's distance onto the record so it could be an observation in its own
  # right - which gave the identical estimate to counting the animals into that
  # group, segment for segment, while putting a row in the table that claimed
  # to be a detection at a distance nothing was detected at. The copy is gone.
  #
  # `break_off_distance` is the one measured thing here: great-circle metres
  # from where the aircraft left the line to where the animals were logged.
  # Nothing upstream can produce it, because it is the one fact about a
  # circling sighting that exists only once the break-off record is known. It
  # is not a perpendicular distance. Under `distance = "break_off"` it becomes
  # the record's `distance` anyway, which is that option's whole claim; under
  # `"with_group"` it stays a diagnostic, for judging whether the attachment
  # was reasonable before those animals enter a density estimate.
  at_origin <- origin[sel]
  has_origin <- !is.na(at_origin)

  extra$distance <- NA_real_
  extra$side <- NA_character_
  extra$distance_source <- NA_character_

  extra$break_off_distance <- gc_distance(
    break_lat[sel], break_lon[sel],
    extra$LATITUDE, extra$LONGITUDE
  ) * 1000

  # `distance = "break_off"` puts the measured one in `distance` instead.
  #
  # It is the other reading of the same question, and it is offered rather than
  # argued with because the two differ in a way no amount of reasoning settles
  # from here: one says these animals are part of a group whose distance from
  # the line is known, the other says they are where they were logged and that
  # is how far off the line they were. They will not agree, and which is closer
  # to the truth depends on how the aircraft actually flew the circle - which
  # the records do not say.
  #
  # What they do agree on is that neither belongs in a detection function. An
  # inherited distance is already in it under another row; a break-off distance
  # is a slant distance from an off-effort position and is not perpendicular to
  # anything. `detection_data()` excludes both on `CIRCLE == 1`.
  if (identical(distance, "break_off")) {
    scale <- if (units == "km") 1 / 1000 else 1
    extra$distance <- extra$break_off_distance * scale
    extra$side <- NA_character_
    extra$distance_source <- ifelse(is.na(extra$distance), NA_character_,
                                    "break_off")

    # Where the animals' own position was recorded, project it onto the census
    # line instead. That is a perpendicular distance, which the slant distance
    # from the break-off is not; the slant one stays as the fallback, and in
    # `break_off_distance` either way.
    if (all(c("S_LAT", "S_LONG") %in% names(dat))) {
      perp <- circling_distance(dat, units = units)[cand_rows[sel], ,
                                                   drop = FALSE]
      has <- !is.na(perp$distance)
      extra$distance[has] <- perp$distance[has]
      extra$side[has] <- perp$side[has]
      extra$distance_source[has] <- "circling"
    }
  }

  # `with_group` takes "counted with the original on-effort group" literally.
  #
  # The other two options give the attached record a distance so that it can be
  # an observation of its own on a density surface. This one says there should
  # be no second observation at all: these animals were counted with a group
  # that was detected from the line, at a distance that was measured, so they
  # are that group. Its `NUMBER` goes up by theirs and nothing is inherited,
  # constructed or copied.
  #
  # It is the reading that survives the obvious objection to `inherit` - a
  # second row carrying a distance it was not seen at, looking for all the
  # world like a trackline detection - and it needs no invented number to do
  # it. What it does need is that the animals really are that group or
  # associated with it, which is what `mode = "same_species"` is testing and
  # is a judgement about the survey rather than about the code.
  #
  # A record with no origin cannot be merged into anything. Those stay separate
  # detections, carrying whatever distance the rules above gave them, which
  # under `mode = "same_species"` never happens - the rule already required an
  # origin - and under `mode = "all"` is the honest outcome: a group of another
  # species found while circling was not counted with anything.
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
      # Several circling records can point at one on-effort sighting, so the
      # additions are summed per origin rather than assigned - assigning would
      # keep only the last.
      by_origin <- tapply(add[merged], at_origin[merged], sum)
      rows <- as.integer(names(by_origin))
      chopped$NUMBER[rows] <- as.numeric(chopped$NUMBER[rows]) + as.numeric(by_origin)
    }
    extra$circling_counted <- !has_origin

    # The animals MOVED. They did not get copied.
    #
    # Leaving `NUMBER` on a record whose animals are now in another row makes
    # every one of them count twice for anything that sums the column - which
    # `segment_sightings()` does not, because it skips the flagged rows, and
    # which anything else reasonably might. The count goes to zero and the
    # number that moved is kept beside it, so the record can still say what it
    # contributed and to what.
    extra$circling_merged <- ifelse(merged, add, NA_real_)
    extra$NUMBER[merged] <- 0
  }

  # The columns this function sets are named explicitly, not intersected.
  #
  # Intersecting with `chopped`'s columns keeps only what was already there,
  # which silently drops anything this function is the sole source of.
  # `break_off_distance` is always one of those. So are `distance`, `side` and
  # `distance_source` whenever the survey carried no angles for
  # `sighting_distances()` to work from: the attached rows would arrive with an
  # inherited distance, or a measured one under `distance = "break_off"`, and
  # lose it on the way out.
  added <- c("break_off_distance", "distance", "side", "distance_source",
             "circling_counted", "circling_merged")
  keep <- union(intersect(names(chopped), names(extra)), added)
  out <- dplyr::bind_rows(chopped, extra[, keep])
  dplyr::arrange(out, .data$DATE, .data$seg_id, .data$EVENTNO)
}


# Named before match.arg(), which would otherwise report a removed option as
# simply not one of the choices - true, and no help at all to anyone whose
# script or notes still say it. Shared with segment_survey(), whose own
# match.arg() runs first and would otherwise answer for it.
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
