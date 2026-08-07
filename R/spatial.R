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

  if (what == "midpoints") {
    segs <- x$segments[!is.na(x$segments$mid_lon) & !is.na(x$segments$mid_lat), ]
    return(sf::st_as_sf(segs, coords = c("mid_lon", "mid_lat"), crs = crs,
                        remove = FALSE))
  }

  pts <- x$points
  pts <- pts[!is.na(pts$LONGITUDE) & !is.na(pts$LATITUDE), ]
  # A LINESTRING needs at least two positions.
  keep <- names(which(table(pts$seg_id) >= 2))
  pts <- pts[pts$seg_id %in% keep, ]
  if (!nrow(pts)) {
    rlang::abort("No segment has two or more positions to build a line from.")
  }

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

  if (inherits(x, "distsamp_segments")) {
    x$segments <- crop_to_bbox(x$segments, box, coords = c("mid_lon", "mid_lat"))
    x$points <- crop_to_bbox(x$points, box, coords = coords)
    x$sightings <- x$sightings[x$sightings$seg_id %in% x$segments$seg_id, ]
    return(x)
  }

  if (inherits(x, "sf")) {
    check_sf()
    return(sf::st_crop(x, sf::st_bbox(
      c(xmin = box[["xmin"]], ymin = box[["ymin"]],
        xmax = box[["xmax"]], ymax = box[["ymax"]]),
      crs = sf::st_crs(x)
    )))
  }

  if (!all(coords %in% names(x))) {
    alt <- c("mid_lon", "mid_lat")
    if (all(alt %in% names(x))) {
      coords <- alt
    } else {
      abort_missing_columns(setdiff(coords, names(x)))
    }
  }

  lon <- x[[coords[1]]]
  lat <- x[[coords[2]]]
  keep <- !is.na(lon) & !is.na(lat) &
    lon >= box[["xmin"]] & lon <= box[["xmax"]] &
    lat >= box[["ymin"]] & lat <= box[["ymax"]]
  x[keep, , drop = FALSE]
}

as_bbox <- function(bbox) {
  if (is.numeric(bbox) && all(c("xmin", "xmax", "ymin", "ymax") %in% names(bbox))) {
    b <- bbox[c("xmin", "xmax", "ymin", "ymax")]
  } else {
    check_sf()
    b0 <- sf::st_bbox(bbox)
    b <- c(xmin = b0[["xmin"]], xmax = b0[["xmax"]],
           ymin = b0[["ymin"]], ymax = b0[["ymax"]])
  }
  # Tolerate a box given with its corners the other way round.
  c(
    xmin = min(b[["xmin"]], b[["xmax"]]), xmax = max(b[["xmin"]], b[["xmax"]]),
    ymin = min(b[["ymin"]], b[["ymax"]]), ymax = max(b[["ymin"]], b[["ymax"]])
  )
}

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
#' else in the package writes to disk, so output is always something you asked
#' for.
#'
#' @param x A `distsamp_segments` object.
#' @param dir Directory to write to. Created if it does not exist.
#' @param prefix Filename prefix. Default `"segments"`.
#' @param tables Which tables to write. Default all four.
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
                           tables = c("segments", "sightings", "tracks", "points")) {
  stopifnot(inherits(x, "distsamp_segments"))
  tables <- match.arg(tables, several.ok = TRUE)

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
