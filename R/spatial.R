#' Convert segments to spatial features
#'
#' Builds an `sf` object from a [segment_survey()] result, either as the segment
#' midpoints or as the trackline geometry of each segment.
#'
#' @param x A `distsamp_segments` object.
#' @param what `"midpoints"` (default) for one point per segment, or `"lines"`
#'   for the trackline each segment covers.
#' @param crs Coordinate reference system for the result. Default `4326`
#'   (WGS 84), the datum NARWC coordinates are recorded in.
#'
#' @return An `sf` object with one feature per segment, carrying the segment
#'   attributes.
#'
#' @references
#' Pebesma, E. (2018) Simple features for R: standardized support for spatial
#' vector data. *The R Journal* 10(1):439-446. \doi{10.32614/RJ-2018-009}
#'
#' @examples
#' if (requireNamespace("sf", quietly = TRUE)) {
#'   path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#'   segs <- segment_survey(read_narwc(path), seg_length = 5, seed = 1)
#'   segments_as_sf(segs)
#' }
#'
#' @export
segments_as_sf <- function(x, what = c("midpoints", "lines"), crs = 4326) {
  stopifnot(inherits(x, "distsamp_segments"))
  what <- match.arg(what)
  check_sf()

  # Midpoints: one POINT per segment with a known midpoint. The coordinate
  # columns are kept as attributes as well.
  if (what == "midpoints") {
    segs <- x$segments[!is.na(x$segments$mid_lon) & !is.na(x$segments$mid_lat), ]
    return(sf::st_as_sf(segs, coords = c("mid_lon", "mid_lat"), crs = crs,
                        remove = FALSE))
  }

  # Lines: build each segment's trackline from its positioned points, in
  # their stored order. A LINESTRING needs at least two positions, so
  # segments with fewer are left out.
  pts <- x$points
  pts <- pts[!is.na(pts$LONGITUDE) & !is.na(pts$LATITUDE), ]
  keep <- names(which(table(pts$seg_id) >= 2))
  pts <- pts[pts$seg_id %in% keep, ]
  if (!nrow(pts)) {
    rlang::abort("No segment has two or more positions to build a line from.")
  }

  # Points -> one MULTIPOINT per segment (do_union = FALSE keeps the order)
  # -> LINESTRING, then attach the segment attributes.
  geom <- sf::st_as_sf(pts, coords = c("LONGITUDE", "LATITUDE"), crs = crs)
  lines <- dplyr::summarise(
    dplyr::group_by(geom, .data$seg_id),
    do_union = FALSE, .groups = "drop"
  )
  lines <- sf::st_cast(lines, "LINESTRING")
  dplyr::left_join(lines, x$segments, by = "seg_id")
}


#' Restrict data to a bounding box
#'
#' Keeps only the records or segments falling inside a rectangular area.
#'
#' Replaces the `crop_data()` helper that the original scripts called but never
#' defined.
#'
#' @param x A data frame with longitude and latitude columns, an `sf` object, or
#'   a `distsamp_segments` object. For a `distsamp_segments` object both the
#'   `segments` and `points` tables are cropped, the former on its midpoint.
#' @param bbox Either a numeric vector with names `xmin`, `xmax`, `ymin`,
#'   `ymax`, or an object [sf::st_bbox()] understands.
#' @param coords Names of the longitude and latitude columns, used for plain
#'   data frames. Defaults to `c("LONGITUDE", "LATITUDE")`, falling back to the
#'   midpoint columns for a segment table.
#'
#' @return The input, cropped, with the same class.
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' dat <- read_narwc(path)
#' gom <- c(xmin = -71, xmax = -66, ymin = 42, ymax = 45)
#' nrow(crop_to_bbox(dat, gom))
#'
#' @export
crop_to_bbox <- function(x, bbox, coords = c("LONGITUDE", "LATITUDE")) {
  box <- as_bbox(bbox)

  # A segmentation: crop segments on their midpoints and points on their
  # positions, then keep the sightings of the segments that remain.
  if (inherits(x, "distsamp_segments")) {
    x$segments <- crop_to_bbox(x$segments, box, coords = c("mid_lon", "mid_lat"))
    x$points <- crop_to_bbox(x$points, box, coords = coords)
    kept <- x$segments$seg_id
    x$sightings <- x$sightings[x$sightings$seg_id %in% kept, ]
    if (!is.null(x$detections)) {
      x$detections <- x$detections[x$detections$seg_id %in% kept, ]
    }
    # Tracks are kept when any of their segments is.
    if (!is.null(x$tracks) && all(c("DATE", "new_trackno") %in% names(x$tracks))) {
      on <- paste(x$segments$DATE, x$segments$new_trackno)
      x$tracks <- x$tracks[paste(x$tracks$DATE, x$tracks$new_trackno) %in% on, ]
    }
    return(x)
  }

  # An sf object: let sf crop it, in its own CRS.
  if (inherits(x, "sf")) {
    check_sf()
    return(sf::st_crop(x, sf::st_bbox(
      c(xmin = box[["xmin"]], ymin = box[["ymin"]],
        xmax = box[["xmax"]], ymax = box[["ymax"]]),
      crs = sf::st_crs(x)
    )))
  }

  # A plain data frame: use `coords`, or the midpoint columns of a segment
  # table if `coords` are absent.
  if (!all(coords %in% names(x))) {
    alt <- c("mid_lon", "mid_lat")
    if (all(alt %in% names(x))) {
      coords <- alt
    } else {
      abort_missing_columns(setdiff(coords, names(x)))
    }
  }

  # Keep rows inside the box, edges included. Rows without a position go.
  lon <- x[[coords[1]]]
  lat <- x[[coords[2]]]
  keep <- !is.na(lon) & !is.na(lat) &
    lon >= box[["xmin"]] & lon <= box[["xmax"]] &
    lat >= box[["ymin"]] & lat <= box[["ymax"]]
  x[keep, , drop = FALSE]
}

# Normalises `bbox` to a named numeric vector c(xmin, xmax, ymin, ymax) in
# the bbox's own units (decimal degrees for NARWC data). Accepts a named
# vector or anything sf::st_bbox() understands.
as_bbox <- function(bbox) {
  if (is.numeric(bbox) && all(c("xmin", "xmax", "ymin", "ymax") %in% names(bbox))) {
    b <- bbox[c("xmin", "xmax", "ymin", "ymax")]
  } else {
    check_sf()
    b0 <- sf::st_bbox(bbox)
    b <- c(xmin = b0[["xmin"]], xmax = b0[["xmax"]],
           ymin = b0[["ymin"]], ymax = b0[["ymax"]])
  }
  # Accept a box given with its corners the other way round.
  c(
    xmin = min(b[["xmin"]], b[["xmax"]]), xmax = max(b[["xmin"]], b[["xmax"]]),
    ymin = min(b[["ymin"]], b[["ymax"]]), ymax = max(b[["ymin"]], b[["ymax"]])
  )
}

# Errors, attributed to the caller, if the suggested package sf is not
# installed.
check_sf <- function(call = rlang::caller_env()) {
  if (!requireNamespace("sf", quietly = TRUE)) {
    rlang::abort(
      "The `sf` package is required for spatial output. Install it with `install.packages(\"sf\")`.",
      call = call
    )
  }
}


#' Write segmentation results to CSV
#'
#' Writes the tables from a [segment_survey()] result to a directory. Nothing
#' else in the package writes to disk.
#'
#' @param x A `distsamp_segments` object.
#' @param dir Directory to write to. Created if it does not exist.
#' @param prefix Filename prefix. Default `"segments"`.
#' @param tables Which tables to write. Default all five.
#'
#' @return The paths written, invisibly.
#'
#' @examples
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' segs <- segment_survey(read_narwc(path), seg_length = 5, seed = 1)
#' out <- file.path(tempdir(), "segout")
#' write_segments(segs, out)
#' list.files(out)
#'
#' @export
write_segments <- function(x, dir, prefix = "segments",
                           tables = c("segments", "sightings", "detections", "tracks", "points")) {
  stopifnot(inherits(x, "distsamp_segments"))
  tables <- match.arg(tables, several.ok = TRUE)

  # Create the directory, then write one CSV per table, named
  # <prefix>_<table>.csv.
  if (!dir.exists(dir)) {
    dir.create(dir, recursive = TRUE)
  }

  paths <- vapply(tables, function(nm) {
    p <- file.path(dir, paste0(prefix, "_", nm, ".csv"))
    utils::write.csv(as.data.frame(x[[nm]]), p, row.names = FALSE)
    p
  }, character(1))

  invisible(unname(paths))
}
