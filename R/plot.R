#' Diagnostic plots for a segmentation
#'
#' Four views of a [segment_survey()] result, each answering a question that is
#' hard to answer from the tables. Returns a `ggplot` object, so it can be
#' modified, saved, or faceted further like any other.
#'
#' @section What each view is for:
#' \describe{
#'   \item{`"segments"`}{The track flown, the segment midpoints, and where the
#'     sightings were. The first thing to look at: a segmentation that has gone
#'     wrong is usually obvious here, as midpoints strung along a line the
#'     aircraft never flew, or clustered where a track should have been split.}
#'   \item{`"tracks"`}{The same positions coloured by `new_trackno`, faceted by
#'     date. This is the view that shows whether [split_tracks()] did the right
#'     thing — a break in effort should start a new colour, and a colour should
#'     never span two places the aircraft could not have flown between.}
#'   \item{`"effort"`}{Segment lengths against the target. The Becker method
#'     produces segments near `seg_length` but not at it, with one absorbing
#'     segment per track taking up the remainder, so a spread is expected. What
#'     is not expected is mass outside the tolerance band, which the dashed lines
#'     mark.}
#'   \item{`"distances"`}{The distribution of perpendicular distances. This is
#'     the detection-function diagnostic: look for a shoulder near zero and a
#'     tail that falls away. A spike at zero, a peak away from zero, or a long
#'     flat tail all mean something, and all of them matter before
#'     `Distance::ds()` is called. See the note on `g(0)` below.}
#' }
#'
#' @section Coastlines, and why the default is none:
#' `coastline = TRUE` draws Natural Earth land under the track. That is enough
#' to orient a shelf-scale survey, and **not** enough for a bay. Natural Earth's
#' medium scale is 1:50,000,000; against a survey whose lines are a few
#' kilometres apart, its shoreline is wrong by more than the thing you are
#' looking at, and a segmentation that hugs the coast will appear to run over
#' land.
#'
#' So: use it to get your bearings, and pass your own `sf` object for anything
#' anyone else will see.
#'
#' ```r
#' plot(segs, coastline = sf::st_read("gshhg_cape_cod.shp"))
#' ```
#'
#' `scale = "large"` (1:10m) is better and needs `rnaturalearthhires`, which is
#' not on CRAN — install it from the rOpenSci r-universe.
#'
#' @section On reading the distance histogram:
#' A dip in the first bin is not necessarily a sampling artefact — an aircraft
#' cannot see the water directly beneath it, and for the Skymaster the handbook
#' says so explicitly (8.A.31). That is a reason to truncate on the left, not to
#' assume the animals were not there. Neither is a smooth curve evidence that
#' `g(0) = 1`: animals submerged when the aircraft passed leave no trace in this
#' plot at all. See `docs/07-fitting-architecture.md` in the package repository.
#'
#' @param x A `distsamp_segments` object from [segment_survey()].
#' @param what Which view: `"segments"` (default), `"tracks"`, `"effort"`, or
#'   `"distances"`.
#' @param species Optional character vector of `SPECCODE` values to show, for
#'   the views that draw sightings. `NULL` (default) shows all.
#' @param coastline Land to draw under the map views. `FALSE` (default) draws
#'   none. `TRUE` fetches Natural Earth countries through `rnaturalearth`; a
#'   scale name — `"small"`, `"medium"`, `"large"` — picks the resolution; or
#'   pass your own `sf` object. Ignored by the `"effort"` and `"distances"`
#'   views. See the note on resolution below.
#' @param ... Ignored, for compatibility with [plot()].
#'
#' @return A `ggplot` object.
#'
#' @seealso [segment_survey()], [segments_as_sf()] to hand positions to `sf` for
#'   a proper map with coastlines.
#'
#' @examplesIf requireNamespace("ggplot2", quietly = TRUE)
#' path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
#' segs <- segment_survey(read_narwc(path), seg_length = 5, seed = 1)
#'
#' # Where the segments are, and what was seen
#' plot(segs)
#'
#' # Did track splitting do the right thing? A break in effort should start a
#' # new colour.
#' plot(segs, what = "tracks")
#'
#' # Are segment lengths near the target? Dashed lines are the tolerance band.
#' plot(segs, what = "effort")
#'
#' # The detection-function diagnostic, before handing anything to Distance
#' plot(segs, what = "distances")
#'
#' # Just one species
#' plot(segs, species = "RIWH")
#'
#' # It is an ordinary ggplot, so keep going
#' plot(segs) + ggplot2::labs(title = "Synthetic example survey")
#'
#' @export
plot.distsamp_segments <- function(x, what = c("segments", "tracks", "effort",
                                               "distances"),
                                   species = NULL, coastline = FALSE, ...) {
  what <- match.arg(what)
  check_ggplot2()

  switch(what,
    segments  = plot_segments_map(x, species, coastline),
    tracks    = plot_tracks_map(x, coastline),
    effort    = plot_effort_hist(x),
    distances = plot_distance_hist(x, species)
  )
}

check_ggplot2 <- function(call = rlang::caller_env()) {
  if (!requireNamespace("ggplot2", quietly = TRUE)) {
    rlang::abort(
      paste0(
        "The `ggplot2` package is required for plotting. Install it with ",
        "`install.packages(\"ggplot2\")`."
      ),
      call = call
    )
  }
}

# Sighting records carrying a position, from the point-level table.
sightings_with_position <- function(x, species = NULL) {
  pts <- x$points
  if (is_empty_df(pts) || !"SPECCODE" %in% names(pts)) {
    return(NULL)
  }
  out <- pts[!is.na(pts$SPECCODE) & pts$SPECCODE != "", , drop = FALSE]
  if (!is.null(species)) {
    out <- out[out$SPECCODE %in% species, , drop = FALSE]
  }
  if (!nrow(out)) NULL else out
}

plot_segments_map <- function(x, species = NULL, coastline = FALSE) {
  segs <- x$segments
  pts <- x$points
  sight <- sightings_with_position(x, species)
  land <- coastline_layer(coastline)

  p <- ggplot2::ggplot() +
    land +
    ggplot2::geom_point(
      data = pts,
      ggplot2::aes(x = .data$LONGITUDE, y = .data$LATITUDE),
      colour = "grey75", size = 0.4
    ) +
    ggplot2::geom_point(
      data = segs,
      ggplot2::aes(x = .data$mid_lon, y = .data$mid_lat, size = .data$seg_eff),
      shape = 21, fill = NA, colour = "grey25", stroke = 0.5
    ) +
    ggplot2::scale_size_continuous(name = "Segment effort (km)")

  if (!is.null(sight)) {
    p <- p + ggplot2::geom_point(
      data = sight,
      ggplot2::aes(x = .data$LONGITUDE, y = .data$LATITUDE,
                   colour = .data$SPECCODE),
      size = 2.2
    ) +
      ggplot2::scale_colour_brewer(name = "Species", palette = "Dark2")
  }

  p +
    map_coord(coastline, pts$LONGITUDE, pts$LATITUDE) +
    ggplot2::labs(
      x = "Longitude", y = "Latitude",
      title = "Segment midpoints and sightings",
      subtitle = paste0(
        nrow(segs), " segments over ",
        round(sum(segs$seg_eff, na.rm = TRUE), 1), " km of effort"
      )
    ) +
    ggplot2::theme_minimal()
}

plot_tracks_map <- function(x, coastline = FALSE) {
  pts <- x$points
  pts$.track <- factor(pts$new_trackno)

  p <- ggplot2::ggplot(
    pts,
    ggplot2::aes(x = .data$LONGITUDE, y = .data$LATITUDE, colour = .data$.track)
  ) +
    coastline_layer(coastline) +
    ggplot2::geom_path(ggplot2::aes(group = .data$.track), linewidth = 0.4) +
    ggplot2::geom_point(size = 0.7) +
    map_coord(coastline, pts$LONGITUDE, pts$LATITUDE) +
    ggplot2::labs(
      x = "Longitude", y = "Latitude", colour = "Track",
      title = "Continuous-effort tracks",
      subtitle = paste0(
        length(unique(pts$new_trackno)), " tracks; a break in effort starts a ",
        "new one"
      )
    ) +
    ggplot2::theme_minimal()

  if ("DATE" %in% names(pts) && length(unique(pts$DATE)) > 1) {
    p <- p + ggplot2::facet_wrap(~DATE)
  }
  p
}

plot_effort_hist <- function(x) {
  segs <- x$segments
  target <- x$settings$seg_length
  tol <- target * (x$settings$seg_tol_frac %||% 0.5)

  ggplot2::ggplot(segs, ggplot2::aes(x = .data$seg_eff)) +
    ggplot2::geom_histogram(bins = 15, fill = "grey60", colour = "white") +
    ggplot2::geom_vline(xintercept = target, linewidth = 0.6) +
    ggplot2::geom_vline(
      xintercept = c(target - tol, target + tol),
      linetype = "dashed", linewidth = 0.4
    ) +
    ggplot2::labs(
      x = "Segment effort (km)", y = "Segments",
      title = "Segment lengths against the target",
      subtitle = paste0(
        "Target ", target, " km, tolerance +/- ", tol,
        " km. One absorbing segment per track takes the remainder."
      )
    ) +
    ggplot2::theme_minimal()
}

plot_distance_hist <- function(x, species = NULL) {
  det <- x$detections
  if (!is.null(species)) {
    det <- det[det$SPECCODE %in% species, , drop = FALSE]
  }
  det <- det[!is.na(det$distance), , drop = FALSE]

  units <- x$settings$distance_units %||% "m"
  if (!nrow(det)) {
    rlang::abort(paste0(
      "No detections carry a perpendicular distance, so there is nothing to ",
      "plot. Distances come from `ANGLEL`/`ANGLER`, `STRIP`, or `S_LAT`/",
      "`S_LONG`; see `?sighting_distances`."
    ))
  }

  ggplot2::ggplot(det, ggplot2::aes(x = .data$distance)) +
    ggplot2::geom_histogram(bins = 12, fill = "grey60", colour = "white") +
    ggplot2::labs(
      x = paste0("Perpendicular distance (", units, ")"),
      y = "Detections",
      title = "Perpendicular distances",
      subtitle = paste0(
        nrow(det), " of ", nrow(x$detections),
        " detections carry a distance. Fitted with `Distance::ds()`; ",
        "g(0) = 1 is assumed unless corrected."
      )
    ) +
    ggplot2::theme_minimal()
}


# The land layer, or nothing. Drawn before the survey so the track sits on top.
coastline_layer <- function(coastline) {
  land <- resolve_coastline(coastline)
  if (is.null(land)) {
    return(NULL)
  }
  ggplot2::geom_sf(
    data = land, fill = "grey88", colour = "grey65", linewidth = 0.2,
    inherit.aes = FALSE
  )
}

# coord_sf() once there is an sf layer to reconcile, coord_quickmap() otherwise.
# The limits come from the survey rather than the land, or a world coastline
# would zoom the plot out to the world.
map_coord <- function(coastline, lon, lat) {
  if (is.null(resolve_coastline(coastline))) {
    return(ggplot2::coord_quickmap())
  }
  pad <- function(r) {
    d <- diff(r)
    r + c(-1, 1) * max(d * 0.08, 0.05)
  }
  ggplot2::coord_sf(
    xlim = pad(range(lon, na.rm = TRUE)),
    ylim = pad(range(lat, na.rm = TRUE)),
    expand = FALSE
  )
}

# NULL for no coastline, otherwise an sf object.
resolve_coastline <- function(coastline) {
  if (isFALSE(coastline) || is.null(coastline)) {
    return(NULL)
  }
  if (inherits(coastline, "sf")) {
    return(coastline)
  }
  check_sf()

  scale <- if (isTRUE(coastline)) "medium" else coastline
  if (!is.character(scale) || length(scale) != 1L ||
      !scale %in% c("small", "medium", "large")) {
    rlang::abort(paste0(
      "`coastline` must be FALSE, TRUE, one of \"small\", \"medium\", ",
      "\"large\", or an `sf` object to draw."
    ))
  }
  if (!requireNamespace("rnaturalearth", quietly = TRUE)) {
    rlang::abort(paste0(
      "`coastline = \"", scale, "\"` needs the `rnaturalearth` package. ",
      "Install it, or pass an `sf` object of your own to `coastline` - which ",
      "is the better option for anything at bay scale."
    ))
  }

  land <- try(
    rnaturalearth::ne_countries(scale = scale, returnclass = "sf"),
    silent = TRUE
  )
  if (inherits(land, "try-error")) {
    rlang::abort(paste0(
      "Natural Earth data at scale \"", scale, "\" is not available: ",
      sub("\n.*", "", conditionMessage(attr(land, "condition"))),
      if (scale == "large") {
        paste0(
          "\nScale \"large\" needs `rnaturalearthhires`, which is not on ",
          "CRAN; install it from https://ropensci.r-universe.dev."
        )
      } else {
        ""
      }
    ))
  }
  land
}
