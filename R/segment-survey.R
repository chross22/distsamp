#' Segment a line-transect survey
#'
#' Runs the whole segmentation pipeline: identify line occupations, flag effort,
#' accumulate along-track distance, split lines where effort breaks, plan how
#' many segments each continuous track carries, cut them, and summarise
#' sightings and conditions onto each segment.
#'
#' This is the function most users want. The individual steps are exported too,
#' so you can run them yourself when you need to intervene between stages.
#'
#' @section Pipeline:
#' 1. [make_leg_id()] — separate re-occupations of the same survey line.
#' 2. [flag_effort()] — decide which records are on effort.
#' 3. [point_to_point_effort()] — great-circle distance between consecutive
#'    on-effort positions.
#' 4. [split_tracks()] — start a new track wherever effort breaks.
#' 5. [track_effort()] — total effort per continuous track.
#' 6. [plan_segments()] — how many segments, and how long each should be.
#' 7. [cut_segments()] — walk the records and make the cuts.
#' 8. [segment_midpoints()] — the along-track midpoint of each segment.
#' 9. [segment_sightings()] — counts and conditions per segment.
#'
#' Steps 1 and 2 are skipped when the input already carries `LEGNO3` or
#' `OnOff.Effort` respectively, so you can substitute your own definitions.
#'
#' @section Reproducibility:
#' Segmentation makes two random choices: which segment absorbs a track's
#' leftover distance, and whether a segment that cannot land exactly on its
#' target runs slightly long or slightly short. Pass a `seed` to make a run
#' repeatable. The calling session's RNG state is never disturbed.
#'
#' @param dat NARWC survey data, ideally from [read_narwc()].
#' @param seg_length Target segment length in km.
#' @param species Character vector of `SPECCODE` values to count, or `NULL` for
#'   all.
#' @param seed Integer RNG seed, or `NULL` for unseeded (not reproducible).
#' @param seg_tol_frac Passed to [plan_segments()].
#' @param min_track_km Passed to [track_effort()].
#' @param min_segment_km Passed to [cut_segments()].
#' @param dist_method Great-circle distance method: `"haversine"` (default),
#'   `"becker"`, or `"kenney"`. See [gc_distance()] and [dist_methods()].
#'   Becker and Kenney are the same formula and give identical results.
#' @param distance_sources Precedence order over the right-angle distance
#'   sources, passed to [sighting_distances()]. Defaults to
#'   `c("angle", "exact", "strip")`; `"circling"` is available but not on by
#'   default. Each detection records which source supplied it, in
#'   `distance_source`.
#' @param distance_units Units for perpendicular sighting distances computed
#'   from `ANGLEL`/`ANGLER`: `"m"` (default) or `"km"`. Note that `seg_eff` is
#'   always in km — see [perp_distance()].
#' @param circling How to handle sightings recorded while circling off the
#'   census track: `"same_species"` (default), `"all"`, or `"none"`. See
#'   [attach_circling_sightings()].
#' @param circling_distance What an attached circling record carries:
#'   `"inherit"` (default), the perpendicular distance of the on-effort group
#'   it was counted with; `"break_off"`, the measured great-circle distance
#'   from where the aircraft left the line; or `"with_group"`, which gives it
#'   no distance and no detection of its own, adding the animals to the group
#'   they were counted with instead. See [attach_circling_sightings()].
#'   `settings$circling_distance` records which was used.
#' @param effort_args Named list of arguments for [flag_effort()], used only
#'   when `dat` has no `OnOff.Effort` column.
#' @param sighting_args Named list of arguments for [segment_sightings()].
#'
#' @return An object of class `distsamp_segments`: a list with
#'   \describe{
#'     \item{`segments`}{One row per segment — `seg_id`, `DATE`, `FILEID`,
#'       `LEGNO`, `LEGNO3`, `new_trackno`, `seg_no`, `seg_eff` (km),
#'       `mid_lat`, `mid_lon`, `mean_beaufort`, `wt_beaufort`, `n_records`,
#'       `events`, `case`, `start_time`.}
#'     \item{`sightings`}{One row per segment per species.}
#'     \item{`detections`}{One row per qualifying sighting, with perpendicular
#'       `distance` and `side` when `ANGLEL`/`ANGLER` were recorded. The input
#'       for a detection function.}
#'     \item{`tracks`}{One row per continuous track.}
#'     \item{`points`}{The point-level data with segment assignments, for
#'       diagnostics and mapping.}
#'     \item{`call`, `settings`}{The call and the parameters used.}
#'   }
#'
#' @references
#' Becker, E.A., Forney, K.A., Ferguson, M.C., Foley, D.G., Smith, R.C., Barlow,
#' J. and Redfern, J.V. (2010) Comparing California Current cetacean-habitat
#' models developed using in situ and remotely sensed sea surface temperature
#' data. *Marine Ecology Progress Series* 413:163-183.
#' \doi{10.3354/meps08696}
#'
#' Hedley, S.L. and Buckland, S.T. (2004) Spatial models for line transect
#' sampling. *Journal of Agricultural, Biological, and Environmental Statistics*
#' 9:181-199. \doi{10.1198/1085711043578}
#'
#' Miller, D.L., Burt, M.L., Rexstad, E.A. and Thomas, L. (2013) Spatial models
#' for distance sampling data: recent developments and future directions.
#' *Methods in Ecology and Evolution* 4:1001-1010.
#' \doi{10.1111/2041-210X.12105}
#'
#' Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database: A
#' Guide for Users and Contributors, Version 8*. NARWC Reference Document
#' 2023-01. University of Rhode Island, Graduate School of Oceanography.
#'
#' @seealso [segments_wide()] for a segment table with one count column per
#'   species, which is the shape `dsm` expects.
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' segs <- segment_survey(read_narwc(path), seg_length = 5, seed = 1)
#' segs
#' segs$segments[, c("seg_id", "seg_eff", "mid_lat", "mid_lon")]
#'
#' @export
segment_survey <- function(dat,
                           seg_length,
                           species = NULL,
                           seed = NULL,
                           seg_tol_frac = 0.5,
                           min_track_km = 1,
                           min_segment_km = 1,
                           dist_method = c("haversine", "becker", "kenney",
                                           "eab", "rdk"),
                           circling = c("same_species", "all", "none"),
                           circling_distance = c("inherit", "break_off",
                                                 "with_group"),
                           distance_units = c("m", "km"),
                           distance_sources = c("angle", "exact", "strip"),
                           effort_args = list(),
                           sighting_args = list()) {
  dist_method <- dist_method_canonical(match.arg(dist_method))
  circling <- match.arg(circling)
  circling_distance <- match.arg(circling_distance)
  distance_units <- match.arg(distance_units)
  stopifnot(is.data.frame(dat))
  stopifnot(is.numeric(seg_length), length(seg_length) == 1L, seg_length > 0)

  settings <- list(
    seg_length = seg_length, species = species, seed = seed,
    seg_tol_frac = seg_tol_frac, min_track_km = min_track_km,
    min_segment_km = min_segment_km, dist_method = dist_method,
    circling = circling, circling_distance = circling_distance,
    distance_units = distance_units,
    distance_sources = distance_sources
  )

  # 1. line occupations
  if (!"LEGNO3" %in% names(dat)) {
    dat <- make_leg_id(dat)
  }

  # This package is aerial by construction — the effort criteria are the
  # handbook's aerial ones and `perp_distance()` is a declination angle from
  # an aircraft. A NARWC extract can hold a shipboard survey alongside an
  # aerial one with nothing to say so, and it segments without complaint into
  # numbers that look entirely reasonable. Checked after the occupations are
  # built, because that is what a platform is judged over.
  if (all(c("LATITUDE", "LONGITUDE", "TIME") %in% names(dat))) {
    kind <- narwcr::classify_platform(dat)
    other <- !is.na(kind) & kind != "aerial"
    if (any(other)) {
      counts <- table(droplevels(kind[other]))
      rlang::warn(paste0(
        sum(other), " of ", nrow(dat), " records are not moving at aerial ",
        "survey speed (", paste(names(counts), unname(counts), sep = ": ",
                                collapse = ", "),
        "). distsamp is aerial by construction, and a shipboard survey ",
        "segmented here yields effort and distances that look reasonable and ",
        "mean something else. `prepare_aerial()` splits them, in the order ",
        "that has to hold: occupations, then the platform filter, then ",
        "effort. Filtering before `make_leg_id()` makes two occupations of ",
        "one line adjacent, so they merge and the ferry between them counts ",
        "as survey effort."
      ))
    }
  }
  if (!"CIRCLE" %in% names(dat)) {
    dat <- flag_circling(dat)
  }

  # 2. effort
  if (!"OnOff.Effort" %in% names(dat)) {
    dat <- do.call(flag_effort, c(list(dat), effort_args))
  }

  # 3. along-track distance
  dat <- point_to_point_effort(dat, method = dist_method)

  # Right-angle distances from whichever source the survey recorded. Computed
  # here so they travel with the point data through cutting and end up on each
  # detection, carrying `distance_source` with them.
  if (!"distance" %in% names(dat)) {
    dat <- sighting_distances(dat, sources = distance_sources,
                              units = distance_units)
  }

  # 4-5. continuous tracks and their totals
  dat <- split_tracks(dat)
  tracks <- track_effort(dat, min_track_km = min_track_km)

  # 6-7. plan and cut. Both draw from the RNG; running them under one seeded
  # block keeps the whole segmentation reproducible from a single seed.
  chopped <- with_optional_seed(seed, {
    plan <- plan_segments(
      tracks, seg_length = seg_length, seg_tol_frac = seg_tol_frac, seed = NULL
    )
    cut_segments(plan, dat, min_segment_km = min_segment_km, seed = NULL)
  })

  # Bring back sightings made while circling off the census track, attributing
  # them to the segment that was in progress at the break-off.
  chopped <- attach_circling_sightings(chopped, dat, mode = circling,
                                       distance = circling_distance)

  # 8-9. per-segment products
  mids <- segment_midpoints(chopped)
  summaries <- do.call(
    segment_sightings,
    c(list(chopped, species = species), sighting_args)
  )

  segments <- assemble_segments(chopped, mids, summaries$conditions, tracks)

  structure(
    list(
      segments = segments,
      sightings = summaries$sightings,
      detections = summaries$detections,
      tracks = tracks,
      points = chopped,
      call = match.call(),
      settings = settings
    ),
    class = "distsamp_segments"
  )
}

assemble_segments <- function(chopped, mids, conditions, tracks) {
  if (is_empty_df(chopped)) {
    return(tibble::tibble(
      seg_id = character(0), DATE = as.Date(character(0)),
      new_trackno = character(0), seg_no = integer(0), seg_eff = numeric(0),
      mid_lat = numeric(0), mid_lon = numeric(0)
    ))
  }

  carry <- intersect(c("FILEID", "LEGNO", "LEGNO2", "LEGNO3"), names(chopped))

  segs <- dplyr::summarise(
    dplyr::group_by(chopped, .data$seg_id),
    DATE = dplyr::first(.data$DATE),
    new_trackno = dplyr::first(.data$new_trackno),
    seg_no = dplyr::first(.data$seg_no),
    seg_eff = dplyr::first(.data$seg_eff),
    events = dplyr::first(.data$events),
    case = dplyr::first(.data$case),
    start_time = suppressWarnings(min(as.numeric(.data$TIME), na.rm = TRUE)),
    dplyr::across(dplyr::all_of(carry), dplyr::first),
    .groups = "drop"
  )
  segs$start_time[!is.finite(segs$start_time)] <- NA_real_

  segs <- dplyr::left_join(segs, mids, by = "seg_id")
  segs <- dplyr::left_join(segs, conditions, by = "seg_id")

  front <- c(
    "seg_id", "DATE", carry, "new_trackno", "seg_no", "seg_eff",
    "mid_lat", "mid_lon", "mean_beaufort", "wt_beaufort", "n_records",
    "start_time", "events", "case"
  )
  front <- intersect(front, names(segs))
  segs <- segs[, c(front, setdiff(names(segs), front)), drop = FALSE]

  dplyr::arrange(segs, .data$DATE, .data$new_trackno, .data$seg_no)
}


#' @export
print.distsamp_segments <- function(x, ...) {
  cat("<distsamp_segments>\n")
  cat("  segments:  ", nrow(x$segments), "\n", sep = "")
  cat("  tracks:    ", nrow(x$tracks), "\n", sep = "")
  cat("  total effort: ", format(round(sum(x$segments$seg_eff), 2), nsmall = 2),
      " km\n", sep = "")
  if (nrow(x$segments)) {
    cat("  segment length: median ",
        format(round(stats::median(x$segments$seg_eff), 2), nsmall = 2),
        " km, range ",
        format(round(min(x$segments$seg_eff), 2), nsmall = 2), "-",
        format(round(max(x$segments$seg_eff), 2), nsmall = 2), " km\n", sep = "")
  }
  cat("  target length: ", x$settings$seg_length, " km", sep = "")
  cat("   seed: ", if (is.null(x$settings$seed)) "none" else x$settings$seed,
      "\n", sep = "")
  if (nrow(x$sightings)) {
    spp <- sort(unique(x$sightings$SPECCODE))
    cat("  species:   ", paste(spp, collapse = ", "), "\n", sep = "")
  }
  nd <- if (is.null(x$detections)) 0L else nrow(x$detections)
  if (nd) {
    withd <- sum(!is.na(x$detections$distance))
    cat("  detections: ", nd, " (", withd, " with a perpendicular distance",
        if (withd) paste0(", ", x$settings$distance_units) else "", ")\n",
        sep = "")
  }
  invisible(x)
}


#' Segment table with one column per species
#'
#' Reshapes a [segment_survey()] result into the layout density surface models
#' expect: one row per segment, with a count column for each species.
#'
#' @param x A `distsamp_segments` object.
#' @param value Which count to spread: `"animals"` (default, the sum of
#'   `NUMBER`) or `"sightings"` (the number of sighting records).
#' @param prefix Prefix for the generated count columns. Default `"n_"`.
#'
#' @return A tibble: the `segments` table with one count column per species.
#'   Segments with no sightings of a species get `0`, not `NA`.
#'
#' @references
#' Miller, D.L., Burt, M.L., Rexstad, E.A. and Thomas, L. (2013) Spatial models
#' for distance sampling data: recent developments and future directions.
#' *Methods in Ecology and Evolution* 4:1001-1010.
#' \doi{10.1111/2041-210X.12105}
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' segs <- segment_survey(read_narwc(path), seg_length = 5, seed = 1)
#' segments_wide(segs)
#'
#' @export
segments_wide <- function(x, value = c("animals", "sightings"), prefix = "n_") {
  stopifnot(inherits(x, "distsamp_segments"))
  value <- match.arg(value)
  col <- if (value == "animals") "n_animals" else "n_sightings"

  out <- x$segments
  if (is_empty_df(x$sightings)) {
    return(out)
  }

  wide <- tidyr::pivot_wider(
    x$sightings[, c("seg_id", "SPECCODE", col)],
    names_from = "SPECCODE",
    values_from = dplyr::all_of(col),
    names_prefix = prefix,
    values_fill = 0
  )

  out <- dplyr::left_join(out, wide, by = "seg_id")
  count_cols <- setdiff(names(wide), "seg_id")
  for (nm in count_cols) {
    out[[nm]][is.na(out[[nm]])] <- 0
  }
  out
}
