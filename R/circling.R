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
      paste(dat$DATE %||% "", dat$LEGNO3)
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
#' only when the preceding segment already holds an on-effort sighting of the
#' same species. It is the default.
#'
#' @section Which distance:
#' "Counted with the original on-effort group" is also a statement about
#' distance, and `distance = "inherit"` reads it as one: the animals take that
#' group's perpendicular distance, which was measured from the line at the
#' moment of break-off.
#'
#' `distance = "break_off"` reads the sighting as its own: the great-circle
#' distance from where the aircraft left the line to where the animals were
#' logged. That is a real measurement of a real thing, and it is the honest
#' answer to "how far off the track were they" — but it is a slant distance
#' from an off-effort position minutes after the fact, not a perpendicular
#' distance, and a group circled twice before logging is further from the
#' break-off than it ever was from the line.
#'
#' The two will not agree, and which is nearer the truth depends on how the
#' circle was actually flown, which the records do not record.
#'
#' `distance = "with_group"` declines the question. If these animals are
#' counted with the original group then they *are* that group, and a group has
#' one distance, one detection probability and one row — so the animals are
#' added to its `NUMBER` and no second observation is made. That removes the
#' objection to inheriting, which is that a row appears carrying a distance it
#' was never seen at. What it does not remove is the judgement underneath: it
#' is right only where the animals really are that group or associated with it,
#' which is what `mode = "same_species"` is testing.
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
#'   `"inherit"` (default) gives it the perpendicular distance of the on-effort
#'   group these animals were counted with, marked
#'   `distance_source == "circling"`. `"break_off"` gives it the measured
#'   great-circle distance from the point on the line where the aircraft broke
#'   off, marked `distance_source == "break_off"`. Both make it an observation
#'   of its own on a density surface.
#'
#'   `"with_group"` makes it no observation at all: the animals are added to
#'   the `NUMBER` of the on-effort sighting they were counted with, and the
#'   record is marked `circling_counted = FALSE` so [segment_sightings()] does
#'   not count them twice. Nothing is inherited or constructed.
#'
#'   `break_off_distance` is computed under all three, so the size of the
#'   disagreement is visible whichever is chosen. No option puts a circling
#'   record into a detection function — [detection_data()] excludes them all.
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
                                                   "break_off")) {
  mode <- match.arg(mode)
  # Named before match.arg(), which would otherwise report a removed option as
  # simply not one of the choices - true, and no help at all to anyone whose
  # script or notes still say it.
  if (identical(distance, "inherit") ||
      (length(distance) == 1L && identical(distance, "inherit"))) {
    rlang::abort(paste0(
      "`distance = \"inherit\"` was removed. It gave the circling record an ",
      "observation of\nits own carrying the on-effort group's perpendicular ",
      "distance - which produced the\nexact same estimate as ",
      "`\"with_group\"`, segment for segment, while adding a row that\n",
      "claimed a distance nothing was detected at. Use `\"with_group\"`."
    ))
  }
  distance <- match.arg(distance)
  if (mode == "none" || is_empty_df(chopped)) {
    return(chopped)
  }
  if (!all(c("CIRCLE", "SPECCODE", "EVENTNO", "DATE") %in% names(dat))) {
    return(chopped)
  }

  cand <- dat[
    !is.na(dat$CIRCLE) & dat$CIRCLE == 1 &
      !is.na(dat$SPECCODE) & dat$SPECCODE != "", ,
    drop = FALSE
  ]
  if (!nrow(cand)) {
    return(chopped)
  }

  # Where each segment ended, so a circling sighting can be traced back to the
  # segment that was in progress immediately before the break-off.
  #
  # The last record's position comes with it. That record is where the aircraft
  # was when it left the line, and the distance from it to the circling
  # position is the only distance about a circling sighting that is measured
  # rather than inherited.
  # `na.last = FALSE`, so a record with no event number sorts first and can
  # never be taken as the one the aircraft broke off from. Its position would
  # then be measured from, and there is nothing to say it is where the aircraft
  # was.
  by_event <- chopped[order(chopped$EVENTNO, na.last = FALSE), , drop = FALSE]
  bounds <- dplyr::summarise(
    dplyr::group_by(by_event, .data$DATE, .data$seg_id),
    seg_no = dplyr::first(.data$seg_no),
    seg_eff = dplyr::first(.data$seg_eff),
    new_trackno = dplyr::first(.data$new_trackno),
    first_event = min(.data$EVENTNO, na.rm = TRUE),
    last_event = max(.data$EVENTNO, na.rm = TRUE),
    break_lat = dplyr::last(.data$LATITUDE),
    break_lon = dplyr::last(.data$LONGITUDE),
    .groups = "drop"
  )

  # Each candidate attaches to the segment that was in progress immediately
  # before it: the one on the same day with the largest `last_event` not past
  # the candidate's own.
  #
  # Done as a rolling lookup per day rather than a scan per candidate. Scanning
  # `bounds` and `chopped` once for every circling sighting made this
  # O(candidates x records), which is invisible when circling is rare and
  # quadratic when it is not - and on right whale surveys it is not.
  target <- rep(NA_integer_, nrow(cand))
  cand_day <- as.character(cand$DATE)
  bound_day <- as.character(bounds$DATE)

  for (day in unique(cand_day)) {
    b <- which(bound_day == day)
    if (!length(b)) next
    ord <- b[order(bounds$last_event[b])]
    i <- which(cand_day == day)
    pos <- findInterval(cand$EVENTNO[i], bounds$last_event[ord])
    hit <- pos >= 1L
    target[i[hit]] <- ord[pos[hit]]
  }

  sel <- !is.na(target)

  # The on-effort sighting each candidate belongs to, where there is one: the
  # LAST of its own species in the target segment, by event order. A segment
  # can hold several, and the group most recently seen is the one the aircraft
  # turned back for - taking whichever row happened to come first in the frame
  # would make the inherited distance depend on row order, which is not a fact
  # about the survey.
  #
  # `match()` takes the first hit, so the lookup is built in reverse. This row
  # is the source of the inherited distance below, and of the same-species
  # rule: no row, no attachment.
  #
  # One vectorised call over all candidates, and it has to stay that way. The
  # membership test this replaced carried the same warning: doing it per
  # candidate makes the function O(candidates x records), which is invisible
  # while circling is rare and quadratic when it is not - and on right whale
  # surveys it is not.
  seen <- which(!is.na(chopped$SPECCODE) & chopped$SPECCODE != "")
  seen <- seen[order(chopped$EVENTNO[seen], decreasing = TRUE)]
  origin <- seen[match(
    paste(bounds$seg_id[target], cand$SPECCODE, sep = "\r"),
    paste(chopped$seg_id[seen], chopped$SPECCODE[seen], sep = "\r")
  )]

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
    bounds$break_lat[at], bounds$break_lon[at],
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
    extra$distance <- extra$break_off_distance
    extra$side <- NA_character_
    extra$distance_source <- ifelse(is.na(extra$distance), NA_character_,
                                    "break_off")
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
