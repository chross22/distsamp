#' Summarise sightings and conditions by segment
#'
#' Counts sightings and animals per segment per species, and summarises the
#' survey conditions over each segment.
#'
#' @section Which sightings count:
#' Only sightings usable in a density estimate are counted. By default that
#' excludes:
#'
#' * `LEGSTAGE == 6` — a sighting by someone other than an on-duty observer,
#'   typically the pilot. Handbook 4.2 is explicit that such a sighting "cannot
#'   be included in a density estimate", because it did not arise from the
#'   standard search effort the detection function describes.
#' * `LEGSTAGE == 7` — a sighting detected afterwards in a vertical photograph
#'   (handbook 8.A.19), which likewise is not a visual detection by an observer.
#' * `IDREL` of `1` (possible) or `9` (unknown). Handbook 8.A.15 records
#'   Kenney's own practice of using only definite and probable identifications.
#'
#' The original processing code excluded `LEGSTAGE == 7` but kept `LEGSTAGE == 6`,
#' which lets pilot sightings inflate counts.
#'
#' @section Beaufort summaries:
#' Two are produced. `mean_beaufort` is the plain mean over the segment's
#' records; `wt_beaufort` weights each record by the distance it contributes, so
#' a sea state recorded over 3 km counts for more than one recorded over 200 m.
#' Prefer the weighted value as a detection covariate.
#'
#' @param chopped Point-level segmented data from [cut_segments()].
#' @param species Character vector of `SPECCODE` values to count, or `NULL`
#'   (default) for every species present.
#' @param legstage_exclude `LEGSTAGE` values whose sightings are not counted.
#'   Default `c(6, 7)`.
#' @param idrel_keep `IDREL` values whose sightings are counted. Default
#'   `c(2, 3)`.
#'
#' @return A list with two tibbles:
#'   \describe{
#'     \item{`sightings`}{One row per segment per species, with `n_sightings`
#'       (number of sighting records) and `n_animals` (sum of `NUMBER`).}
#'     \item{`conditions`}{One row per segment, with `mean_beaufort`,
#'       `wt_beaufort`, and `n_records`.}
#'   }
#'
#' @seealso [segment_survey()]
#' @export
segment_sightings <- function(chopped,
                              species = NULL,
                              legstage_exclude = c(6, 7),
                              idrel_keep = c(2, 3)) {
  require_columns(chopped, c("seg_id", "pt2pt.effort", "seg_eff"))

  empty_sight <- tibble::tibble(
    seg_id = character(0), SPECCODE = character(0),
    n_sightings = integer(0), n_animals = numeric(0)
  )

  # --- conditions ----------------------------------------------------------
  if ("BEAUFORT" %in% names(chopped)) {
    conditions <- dplyr::summarise(
      dplyr::group_by(chopped, .data$seg_id),
      mean_beaufort = mean(as.numeric(.data$BEAUFORT), na.rm = TRUE),
      wt_beaufort = weighted_mean_safe(
        as.numeric(.data$BEAUFORT), .data$pt2pt.effort
      ),
      n_records = dplyr::n(),
      .groups = "drop"
    )
    conditions$mean_beaufort[is.nan(conditions$mean_beaufort)] <- NA_real_
  } else {
    conditions <- dplyr::summarise(
      dplyr::group_by(chopped, .data$seg_id),
      mean_beaufort = NA_real_, wt_beaufort = NA_real_,
      n_records = dplyr::n(), .groups = "drop"
    )
  }

  # --- sightings -----------------------------------------------------------
  if (!"SPECCODE" %in% names(chopped)) {
    return(list(sightings = empty_sight, conditions = conditions))
  }

  sight <- dplyr::filter(chopped, !is.na(.data$SPECCODE), .data$SPECCODE != "")

  if ("LEGSTAGE" %in% names(sight) && length(legstage_exclude)) {
    sight <- dplyr::filter(
      sight,
      is.na(.data$LEGSTAGE) | !.data$LEGSTAGE %in% legstage_exclude
    )
  }
  if ("IDREL" %in% names(sight) && length(idrel_keep)) {
    sight <- dplyr::filter(
      sight,
      is.na(.data$IDREL) | .data$IDREL %in% idrel_keep
    )
  }
  if (!is.null(species)) {
    sight <- dplyr::filter(sight, .data$SPECCODE %in% species)
  }

  if (is_empty_df(sight)) {
    return(list(sightings = empty_sight, conditions = conditions))
  }

  n_col <- if ("NUMBER" %in% names(sight)) sight$NUMBER else rep(NA_real_, nrow(sight))
  sight$.n_animals <- as.numeric(n_col)

  sightings <- dplyr::summarise(
    dplyr::group_by(sight, .data$seg_id, .data$SPECCODE),
    n_sightings = dplyr::n(),
    n_animals = sum(.data$.n_animals, na.rm = TRUE),
    .groups = "drop"
  )

  list(sightings = sightings, conditions = conditions)
}

# weighted.mean() returns NaN when every weight is zero, which happens on a
# segment whose records all sit at the same position. Fall back to the plain
# mean there.
weighted_mean_safe <- function(x, w) {
  keep <- !is.na(x) & !is.na(w)
  if (!any(keep)) return(NA_real_)
  x <- x[keep]; w <- w[keep]
  if (sum(w) <= 0) return(mean(x))
  sum(x * w) / sum(w)
}
