#' Build a flatfile for `Distance::ds()`
#'
#' Assembles segments and detections into the single "flatfile" data frame the
#' `Distance` package accepts directly, with effort, area, and region alongside
#' each distance.
#'
#' @section The shape:
#' `Distance` accepts one table carrying both the sampling units and the
#' detections, keyed by `Sample.Label`:
#'
#' | column | from |
#' |---|---|
#' | `Region.Label` | `region`, or the `STRATUM` column |
#' | `Area` | the `area` argument |
#' | `Sample.Label` | `seg_id` |
#' | `Effort` | `seg_eff` |
#' | `object` | one id per detection |
#' | `distance` | the resolved right-angle distance |
#' | `distbegin`, `distend` | interval bounds, for `STRIP`-derived rows |
#' | `size` | group size |
#'
#' **Every segment appears, including those with no detections**, carrying a
#' missing `distance`. That is not padding: it is how the flatfile records
#' effort that produced no sightings, and dropping those rows would inflate
#' density by removing the denominator.
#'
#' @section Truncation applies to two things:
#' `truncation` drops detections beyond the given distance — and leaves their
#' segment in place, with its effort intact. That is the whole point: effort
#' searched is effort searched whether or not anything was seen within the
#' truncation distance, so removing the segment as well would remove the
#' denominator along with the numerator and bias density upward.
#'
#' Truncation is reported rather than silent. It also has to match what you pass
#' to `ds()`; passing `truncation` here and a different value there fits the
#' model to one set of detections and scales abundance by another.
#'
#' @section Binned distances cannot be mixed with exact ones:
#' `STRIP` gives an interval, not a point, so those rows carry `distbegin` and
#' `distend` and no `distance`. A single `ds()` call cannot fit both — the
#' likelihoods differ — so a table containing both is a survey era boundary
#' rather than a model set. `mixed = "error"` (the default) refuses it;
#' `mixed = "warn"` lets it through for inspection. Split on `distance_source`
#' and fit each era separately.
#'
#' The top bin of every `STRIP` scheme is open-ended (`>1`, `>2`, `>4` nmi), so
#' `distend` is infinite and no detection function can be fitted to it. Those
#' rows are dropped, and counted in the report.
#'
#' @section Circling detections:
#' Excluded by default, and the reason is stronger than "the position is off the
#' track". A circling detection's `distance` is not measured at all: it is
#' inherited from the on-effort sighting these animals were counted with, which
#' is already a row in this table. Keeping both puts the same perpendicular
#' distance into the detection function twice and weights it twice.
#' `include_circling = TRUE` does keep them — a choice worth stating in a
#' methods section rather than making silently — but it is a choice about
#' double-counting, not about which positions are trustworthy.
#'
#' Note that this is independent of whether circling sightings count towards
#' abundance in a density surface model, which they should and do; that is
#' controlled by `segment_survey(circling = )`. Excluding them here does not
#' remove them from `segs$sightings` or `segs$detections`, and a surface fitted
#' from this flatfile alone will miss them — build its observation table from
#' the detections instead.
#'
#' @section This assumes g(0) = 1, and it almost certainly is not:
#' Nothing in this table corrects for animals that were submerged when the
#' aircraft passed, or that surfaced and were missed. A detection function fitted
#' to it estimates detection *given that the animal was available and seen*, and
#' treats the track-line as certain. For a deep-diving species that biases
#' density low, and not slightly.
#'
#' `distsamp` does not estimate `g(0)` — it cannot be estimated from a standard
#' NARWC extract, which records neither dive data nor the double-observer
#' structure mark-recapture needs — but it must not be assumed away either.
#' Apply a correction from external sources at the abundance step, with its
#' standard error propagated, and say which components it covers.
#'
#' @param x A `distsamp_segments` object from [segment_survey()].
#' @param area Study area, in the units your density estimate should use —
#'   usually km². A single number, or one per region. Required: there is no
#'   sensible default, and a wrong one scales abundance directly.
#' @param region Region labels, one per segment, or a single string. `NULL`
#'   (default) uses the `STRATUM` column if the segments carry one, and
#'   otherwise puts everything in one region called `"all"`.
#' @param truncation Drop detections beyond this distance, in the same units as
#'   `x$settings$distance_units`. `NULL` (default) keeps everything.
#' @param include_circling Keep detections logged while circling. Default
#'   `FALSE`.
#' @param covariates Character vector of segment columns to carry onto every
#'   row, for detection-function covariates. `wt_beaufort` is usually the one
#'   you want.
#' @param mixed What to do when point and interval distances both appear:
#'   `"error"` (default) or `"warn"`.
#' @param quiet Suppress the report of what was dropped. Default `FALSE`.
#'
#' @return A tibble in `Distance` flatfile shape, with a `distance_units`
#'   attribute.
#'
#' @references
#' Miller, D.L., Rexstad, E., Thomas, L., Marshall, L. and Laake, J.L. (2019)
#' Distance sampling in R. *Journal of Statistical Software* 89(1):1-28.
#' \doi{10.18637/jss.v089.i01}
#'
#' Buckland, S.T., Anderson, D.R., Burnham, K.P., Laake, J.L., Borchers, D.L.
#' and Thomas, L. (2001) *Introduction to Distance Sampling.* Oxford University
#' Press.
#'
#' @seealso [sighting_distances()] for where the distances come from,
#'   [segment_survey()], [segments_wide()] for the density-surface side.
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' segs <- segment_survey(read_narwc(path), seg_length = 5, seed = 1)
#'
#' # Area is required and is yours to supply - it scales abundance directly
#' flat <- detection_data(segs, area = 5811)
#' head(flat)
#'
#' # Segments with no detections are kept, carrying their effort
#' sum(is.na(flat$distance))
#'
#' # Truncation drops detections but never the effort that searched for them
#' nrow(detection_data(segs, area = 5811, truncation = 500))
#'
#' # With a detection covariate
#' head(detection_data(segs, area = 5811, covariates = "wt_beaufort"))
#'
#' @export
detection_data <- function(x, area, region = NULL, truncation = NULL,
                           include_circling = FALSE, covariates = character(),
                           mixed = c("error", "warn"), quiet = FALSE) {
  mixed <- match.arg(mixed)
  if (!inherits(x, "distsamp_segments")) {
    rlang::abort("`x` must be a `distsamp_segments` object from `segment_survey()`.")
  }
  if (missing(area) || !is.numeric(area) || !length(area)) {
    rlang::abort(paste0(
      "`area` is required and must be numeric: the size of the study area, in ",
      "the units your density estimate should use (usually square km). It ",
      "scales abundance directly, so there is no defensible default."
    ))
  }

  segs <- x$segments
  det <- x$detections
  units <- x$settings$distance_units %||% "m"
  dropped <- c(circling = 0L, truncated = 0L, open_bin = 0L)

  if (is_empty_df(segs)) {
    rlang::abort("`x` has no segments.")
  }
  require_columns(segs, c("seg_id", "seg_eff"), what = "x$segments")
  if (length(covariates)) {
    require_columns(segs, covariates, what = "x$segments")
  }

  # --- the sampling units ---------------------------------------------------
  labels <- resolve_region(segs, region)
  base <- tibble::tibble(
    Region.Label = labels,
    Area = rep_len(as.numeric(area), nrow(segs)),
    Sample.Label = segs$seg_id,
    Effort = as.numeric(segs$seg_eff)
  )
  for (nm in covariates) base[[nm]] <- segs[[nm]]

  # --- the detections -------------------------------------------------------
  if (!is_empty_df(det)) {
    if (!include_circling && "circling" %in% names(det)) {
      is_circ <- !is.na(det$circling) & det$circling == 1
      dropped["circling"] <- sum(is_circ)
      det <- det[!is_circ, , drop = FALSE]
    }

    # An open top bin cannot be fitted, whatever the truncation.
    if ("distend" %in% names(det)) {
      open <- !is.na(det$distend) & is.infinite(det$distend)
      dropped["open_bin"] <- sum(open)
      det <- det[!open, , drop = FALSE]
    }

    if (!is.null(truncation)) {
      stopifnot(is.numeric(truncation), length(truncation) == 1L, truncation > 0)
      far <- (!is.na(det$distance) & det$distance > truncation) |
        (!is.na(det$distbegin) & det$distbegin >= truncation)
      dropped["truncated"] <- sum(far)
      det <- det[!far, , drop = FALSE]
    }

    det <- det[!is.na(det$distance) | !is.na(det$distbegin), , drop = FALSE]
  }

  has_point <- !is_empty_df(det) && any(!is.na(det$distance))
  has_bin <- !is_empty_df(det) && any(!is.na(det$distbegin))
  if (has_point && has_bin) {
    msg <- paste0(
      "Both point and interval distances are present, and one `ds()` call ",
      "cannot fit both - `STRIP` rows are binned, angle and exact-position ",
      "rows are not. Split on `distance_source` and fit each separately."
    )
    if (mixed == "error") rlang::abort(msg) else rlang::warn(msg)
  }

  out <- assemble_flatfile(base, det, covariates)
  if (!quiet) report_detection_data(dropped, out, units)
  attr(out, "distance_units") <- units
  out
}

# One region label per segment: explicit, else STRATUM, else everything in one.
resolve_region <- function(segs, region) {
  n <- nrow(segs)
  if (!is.null(region)) {
    return(as.character(rep_len(region, n)))
  }
  if ("STRATUM" %in% names(segs) && !all(is.na(segs$STRATUM))) {
    return(as.character(segs$STRATUM))
  }
  rep("all", n)
}

# Join detections onto their segment, keeping segments that have none.
assemble_flatfile <- function(base, det, covariates) {
  empty_cols <- function(df, n) {
    df$object <- rep(NA_integer_, n)
    df$distance <- rep(NA_real_, n)
    df$distbegin <- rep(NA_real_, n)
    df$distend <- rep(NA_real_, n)
    df$size <- rep(NA_real_, n)
    df$distance_source <- rep(NA_character_, n)
    df
  }

  if (is_empty_df(det)) {
    return(empty_cols(base, nrow(base)))
  }

  pick <- function(nm, default) {
    if (nm %in% names(det)) det[[nm]] else rep(default, nrow(det))
  }
  rows <- tibble::tibble(
    Sample.Label = det$seg_id,
    object = seq_len(nrow(det)),
    distance = as.numeric(pick("distance", NA_real_)),
    distbegin = as.numeric(pick("distbegin", NA_real_)),
    distend = as.numeric(pick("distend", NA_real_)),
    size = as.numeric(pick("size", NA_real_)),
    distance_source = as.character(pick("distance_source", NA_character_))
  )

  with_det <- merge(base, rows, by = "Sample.Label")
  bare <- base[!base$Sample.Label %in% rows$Sample.Label, , drop = FALSE]
  bare <- empty_cols(bare, nrow(bare))

  out <- dplyr::bind_rows(tibble::as_tibble(with_det), bare)
  keep <- c("Region.Label", "Area", "Sample.Label", "Effort", "object",
            "distance", "distbegin", "distend", "size", "distance_source",
            covariates)
  out <- out[, intersect(keep, names(out)), drop = FALSE]
  dplyr::arrange(out, .data$Region.Label, .data$Sample.Label, .data$object)
}

report_detection_data <- function(dropped, out, units) {
  n_det <- sum(!is.na(out$object))
  lines <- paste0(
    "`detection_data()`: ", length(unique(out$Sample.Label)), " segments, ",
    n_det, " detection", if (n_det != 1) "s" else "", " (", units, ")."
  )
  if (dropped["circling"] > 0) {
    lines <- c(lines, paste0(
      "  dropped ", dropped["circling"],
      " circling detection(s) - set `include_circling = TRUE` to keep them"
    ))
  }
  if (dropped["open_bin"] > 0) {
    lines <- c(lines, paste0(
      "  dropped ", dropped["open_bin"],
      " in an open top STRIP bin, which cannot be fitted"
    ))
  }
  if (dropped["truncated"] > 0) {
    lines <- c(lines, paste0(
      "  dropped ", dropped["truncated"],
      " beyond the truncation distance; their segments keep their effort"
    ))
  }
  lines <- c(lines, "  g(0) = 1 is assumed; see `?detection_data`.")
  rlang::inform(paste(lines, collapse = "\n"))
}
