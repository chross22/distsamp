#' Diagnostic plots for a segmentation
#'
#' Four views of a [segment_survey()] result, each answering a question that is
#' hard to answer from the tables. Returns a `ggplot` object, so it can be
#' modified, saved, or faceted further like any other.
#'
#' @section What each view is for:
#' \describe{
#'   \item{`"segments"`}{The track flown, the segment midpoints, and where the
#'     sightings were. Look here first: a segmentation that has gone wrong is
#'     usually obvious, as midpoints strung along a line the aircraft never
#'     flew, or clustered where a track should have been split.}
#'   \item{`"tracks"`}{The same positions coloured by `new_trackno`, faceted by
#'     date. This view shows whether [split_tracks()] worked: a break in effort
#'     should start a new colour, and a colour should never span two places the
#'     aircraft could not have flown between.}
#'   \item{`"effort"`}{Segment lengths against the target. The Becker method
#'     produces segments near `seg_length` but not at it, with one absorbing
#'     segment per track taking up the remainder, so a spread is expected. Mass
#'     outside the tolerance band (the dashed lines) is not expected.}
#'   \item{`"distances"`}{The distribution of perpendicular distances. This is
#'     the detection-function diagnostic: look for a shoulder near zero and a
#'     tail that falls away. A spike at zero, a peak away from zero, or a long
#'     flat tail all mean something, and all of them matter before
#'     `Distance::ds()` is called. See the note on `g(0)` below.
#'     The axis stops at the 99th percentile and the subtitle reports what lies
#'     beyond it; otherwise one implausible distance would set the scale and put
#'     every real one in the first bin. Such a distance is usually a bug, so the
#'     subtitle says when the largest is too far to be a detection.}
#' }
#'
#' @section Coastlines, and why the default is none:
#' `coastline = TRUE` draws Natural Earth land under the track. That is enough
#' to orient a shelf-scale survey, and **not** enough for a bay. Natural Earth's
#' medium scale is 1:50,000,000. Against survey lines a few kilometres apart,
#' its shoreline is wrong by more than the features being examined, and a
#' segmentation that hugs the coast appears to run over land.
#'
#' Use it for orientation, and pass an `sf` object of your own for any figure
#' others will see.
#'
#' ```r
#' plot(segs, coastline = sf::st_read("gshhg_cape_cod.shp"))
#' ```
#'
#' `scale = "large"` (1:10m) is better and needs `rnaturalearthhires`, which is
#' not on CRAN; install it from the rOpenSci r-universe.
#'
#' @section On reading the distance histogram:
#' A dip in the first bin is not necessarily a sampling artefact: an aircraft
#' cannot see the water directly beneath it, and for the Skymaster the handbook
#' says so (8.A.31). That is a reason to truncate on the left, not to
#' assume the animals were not there. Neither is a smooth curve evidence that
#' `g(0) = 1`: animals submerged when the aircraft passed leave no trace in this
#' plot at all. See `docs/07-fitting-architecture.md` in the package repository.
#'
#' @param x A `distsamp_segments` object from [segment_survey()].
#' @param what Which view: `"segments"` (default), `"tracks"`, `"effort"`, or
#'   `"distances"`.
#' @param species Optional character vector of `SPECCODE` values to show, for
#'   the views that draw sightings. `NULL` (default) shows all.
#' @param sightings Draw the sightings over the segments? Default `TRUE`. Set
#'   `FALSE` for the whole-archive segments view, where thousands of markers
#'   hide the colouring that shows where the cuts fall. A sighting's position
#'   against its segment is readable in the per-day figures.
#' @param max_legend Most groups to name in the legend. Default `8`. Species
#'   beyond it are gathered into one "other" entry (they stay on the map
#'   without their own colour). Tracks beyond it take a recycled palette and no
#'   legend. Otherwise a survey with 36 species or 130 tracks gives a legend
#'   that squeezes the map to nothing.
#' @param dates,years,months Which survey days to draw, passed to
#'   [filter_days()]. `NULL` (default) draws all of them. Every table in the
#'   object (points, segments, detections) is cut to the same days.
#' @param coastline Land to draw under the map views. `FALSE` (default) draws
#'   none. `TRUE` fetches Natural Earth countries through `rnaturalearth`. A
#'   scale name (`"small"`, `"medium"`, `"large"`) picks the resolution. An
#'   `sf` object is drawn as given. Ignored by the `"effort"` and `"distances"`
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
                                   species = NULL, coastline = FALSE,
                                   max_legend = 8, dates = NULL, years = NULL,
                                   months = NULL, sightings = TRUE, ...) {
  # Cut every table to the requested days, then dispatch to the chosen view.
  what <- match.arg(what)
  check_ggplot2()
  x <- filter_segments_days(x, dates, years, months)

  switch(what,
    segments  = plot_segments_map(x, species, coastline, max_legend, sightings),
    tracks    = plot_tracks_map(x, coastline, max_legend),
    effort    = plot_effort_hist(x),
    distances = plot_distance_hist(x, species)
  )
}

# Errors, attributed to the caller, if the suggested package ggplot2 is not
# installed.
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

# Sighting records (non-blank SPECCODE) from the point-level table,
# optionally restricted to `species`. NULL when there are none.
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

# The "segments" view: positions coloured by segment, with sightings on top.
plot_segments_map <- function(x, species = NULL, coastline = FALSE,
                              max_legend = 8, sightings = TRUE) {
  segs <- x$segments
  pts <- x$points
  sight <- if (isFALSE(sightings)) NULL else sightings_with_position(x, species)

  # Draw only positions that belong to a segment, coloured by segment so that
  # each cut shows as a colour change. Thousands of segments cannot each have
  # a distinct colour; only neighbours need to differ. Positions are put in
  # survey order (DATE, EVENTNO) so that `capped_groups()` recycles the palette
  # along the track. Off-effort positions and segment midpoints are not drawn:
  # at archive scale they hide the colouring.
  on_seg <- pts[!is.na(pts$seg_id), , drop = FALSE]
  if (nrow(on_seg)) {
    on_seg <- on_seg[order(on_seg$DATE, on_seg$EVENTNO), , drop = FALSE]
    on_seg$.col <- capped_groups(on_seg$seg_id, max_legend)$col
  }

  # Land (if any) first, then the segment positions with no colour legend.
  p <- ggplot2::ggplot() + coastline_layer(coastline)

  if (nrow(on_seg)) {
    p <- p +
      ggplot2::geom_point(
        data = on_seg,
        ggplot2::aes(x = .data$LONGITUDE, y = .data$LATITUDE,
                     colour = .data$.col),
        size = 0.55, na.rm = TRUE
      ) +
      scale_colour_safe(nlevels(on_seg$.col)) +
      ggplot2::guides(colour = "none")
  }

  # Sightings as outlined markers on the `fill` scale, so they keep their own
  # legend. Rare species are lumped into one "other" entry.
  n_spp <- 0L
  if (!is.null(sight)) {
    n_spp <- length(unique(as.character(sight$SPECCODE)))
    sight$.spp <- lump_levels(sight$SPECCODE, max_levels = max_legend)
    p <- p +
      ggplot2::geom_point(
        data = sight,
        ggplot2::aes(x = .data$LONGITUDE, y = .data$LATITUDE,
                     fill = .data$.spp),
        shape = 21, size = 1.9, stroke = 0.3, colour = "grey15", na.rm = TRUE
      ) +
      scale_fill_safe(nlevels(sight$.spp), name = "Species") +
      ggplot2::guides(fill = ggplot2::guide_legend(
        override.aes = list(size = 2.8),
        keyheight = ggplot2::unit(0.85, "lines")
      ))
  }

  p +
    # Map extent from the segment positions, not all positions, so that
    # undrawn transits do not add empty margins.
    map_coord(coastline,
              if (nrow(on_seg)) on_seg$LONGITUDE else pts$LONGITUDE,
              if (nrow(on_seg)) on_seg$LATITUDE else pts$LATITUDE) +
    ggplot2::labs(
      x = "Longitude", y = "Latitude",
      title = if (is.null(sight)) "Segments" else "Segments and sightings",
      subtitle = segments_map_subtitle(segs, sight, n_spp, max_legend)
    ) +
    ggplot2::theme_minimal()
}

# Subtitle for the segments view: segment count, total effort (km), and the
# sighting and species counts when sightings are drawn.
segments_map_subtitle <- function(segs, sight, n_spp, max_legend) {
  effort <- paste0(
    fmt_count(nrow(segs)), " segments over ",
    fmt_count(sum(segs$seg_eff, na.rm = TRUE)), " km of effort. ",
    "Colour separates neighbouring segments; it means nothing else."
  )
  if (is.null(sight)) {
    return(effort)
  }
  paste(effort, paste0(
    fmt_count(nrow(sight)), " sightings of ", n_spp, " species",
    if (n_spp > max_legend) {
      paste0("; the ", max_legend - 1L, " most seen are named - pass ",
             "`species =` for the others")
    } else "", "."
  ), sep = "\n")
}

# The "tracks" view: positions coloured by continuous-effort track.
plot_tracks_map <- function(x, coastline = FALSE, max_legend = 12) {
  pts <- x$points

  # Colour by track number, recycling colours and dropping the legend when
  # there are too many tracks to name.
  # A track is identified by day plus track number: numbers restart at 1 on
  # every survey date. This key groups the paths, sets the colours, and gives
  # the count in the subtitle.
  pts$.pathgrp <- if ("DATE" %in% names(pts)) {
    paste(pts$DATE, pts$new_trackno)
  } else {
    as.character(pts$new_trackno)
  }
  cap <- capped_groups(pts$.pathgrp, max_legend)
  pts$.track <- cap$col

  p <- ggplot2::ggplot(
    pts,
    ggplot2::aes(x = .data$LONGITUDE, y = .data$LATITUDE, colour = .data$.track)
  ) +
    coastline_layer(coastline) +
    # Paths are grouped by track, not by colour: once colours recycle, two
    # tracks share a colour and must not be joined.
    ggplot2::geom_path(ggplot2::aes(group = .data$.pathgrp),
                       linewidth = 0.4, na.rm = TRUE) +
    ggplot2::geom_point(size = 0.7, na.rm = TRUE) +
    scale_colour_safe(nlevels(pts$.track)) +
    map_coord(coastline, pts$LONGITUDE, pts$LATITUDE) +
    ggplot2::labs(
      x = "Longitude", y = "Latitude", colour = "Track",
      title = "Continuous-effort tracks",
      subtitle = paste0(
        format(cap$n, big.mark = ","),
        " tracks - one unbroken stretch of on-effort flying, so a break in ",
        "effort starts a new one.",
        if (!cap$named) {
          paste0("\nToo many to name, so colours repeat: what to look for is ",
                 "that neighbouring tracks differ.")
        } else ""
      )
    ) +
    ggplot2::theme_minimal()

  # Legend only when the tracks are named.
  p <- if (cap$named) {
    p + legend_guide(nlevels(pts$.track))
  } else {
    p + ggplot2::guides(colour = "none")
  }

  # Facet by day only for 2 to 12 days, as in `plot_survey()`. More days give
  # panels too small to read.
  if ("DATE" %in% names(pts)) {
    n_days <- length(unique(stats::na.omit(pts$DATE)))
    if (n_days >= 2L && n_days <= 12L) {
      p <- p + ggplot2::facet_wrap(~DATE)
    }
  }
  p
}

# The "effort" view: histogram of segment effort (km), with the target length
# as a solid line and the tolerance band as dashed lines.
plot_effort_hist <- function(x) {
  segs <- x$segments
  target <- x$settings$seg_length
  # Tolerance in km: target x seg_tol_frac (0.5 if the setting is absent).
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

# The "distances" view: histogram of perpendicular distances, in the units
# the segmentation used.
plot_distance_hist <- function(x, species = NULL, trim = 0.99) {
  # Detections with a distance, optionally for chosen species only.
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

  # Stop the axis at the `trim` quantile so that one huge outlier cannot put
  # every real distance in the first bin. Only the view is trimmed; the
  # subtitle reports what lies beyond. If the quantile is unusable, use the
  # maximum.
  d <- det$distance
  hi <- unname(stats::quantile(d, trim, na.rm = TRUE))
  if (!is.finite(hi) || hi <= 0) {
    hi <- max(d, na.rm = TRUE)
  }
  shown <- det[d <= hi, , drop = FALSE]
  beyond <- sum(d > hi)

  ggplot2::ggplot(shown, ggplot2::aes(x = .data$distance)) +
    ggplot2::geom_histogram(bins = 30, fill = "grey60", colour = "white") +
    ggplot2::labs(
      x = paste0("Perpendicular distance (", units, ")"),
      y = "Detections",
      title = "Perpendicular distances",
      subtitle = distance_hist_subtitle(det, x$detections, d, hi, beyond, units)
    ) +
    ggplot2::theme_minimal()
}

# Subtitle for the distances view: how many detections carry a distance,
# where the axis stops and what lies beyond, and a warning if the largest
# distance is implausible.
distance_hist_subtitle <- function(det, all_det, d, hi, beyond, units) {
  have <- paste0(
    fmt_count(nrow(det)), " of ", fmt_count(nrow(all_det)),
    " detections carry a distance. g(0) = 1 is assumed unless corrected."
  )
  # Report the largest distance drawn, not the quantile value, so the number
  # matches the axis.
  axis <- if (beyond > 0) {
    paste0(
      "\nAxis stops at ", fmt_count(max(d[d <= hi], na.rm = TRUE)), " ", units,
      "; ", fmt_count(beyond), " detection", if (beyond != 1L) "s" else "",
      " beyond it, largest ", fmt_count(max(d, na.rm = TRUE)), " ", units, "."
    )
  } else ""

  # A perpendicular distance cannot exceed how far an observer can see from
  # the aircraft. A larger one is an error (a sighting matched to the wrong
  # segment, or a coordinate with a sign error), and the subtitle says so.
  cap <- plausible_max(units)
  warn <- if (!is.na(cap) && max(d, na.rm = TRUE) > cap) {
    paste0(
      "\nThe largest is too far to be a detection - check `?sighting_distances`",
      " before fitting."
    )
  } else ""

  paste0(have, axis, warn)
}

# Largest plausible perpendicular distance in `units`: 20 km (about 11 nmi).
# NA for unknown units, which disables the check.
plausible_max <- function(units) {
  switch(units, m = 20000, km = 20, nmi = 11, nm = 11, NA_real_)
}


# The land layer, or NULL for none. Added before the survey layers so the
# track is drawn on top.
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

# Map coordinates. coord_quickmap() when there is no land layer; coord_sf()
# when there is an sf layer. Limits come from the survey positions (degrees),
# not the land, or a world coastline would zoom out to the world.
map_coord <- function(coastline, lon, lat) {
  if (is.null(resolve_coastline(coastline))) {
    return(ggplot2::coord_quickmap())
  }
  # Pad each range by 8% of its width, and by at least 0.05 degrees.
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

# As resolve_coastline(), but a coastline that cannot be fetched gives a
# warning and NULL instead of an error. For exploratory plots, where a missing
# coastline is a nuisance rather than a failure.
resolve_coastline_soft <- function(coastline) {
  tryCatch(resolve_coastline(coastline), error = function(e) {
    rlang::warn(paste0(
      "Drawing without a coastline: ", conditionMessage(e)
    ))
    NULL
  })
}

# The land to draw: NULL for no coastline, otherwise an sf object. FALSE or
# NULL gives NULL; an sf object is returned as given; TRUE or a scale name
# fetches Natural Earth countries. Errors if they cannot be fetched.
resolve_coastline <- function(coastline) {
  if (isFALSE(coastline) || is.null(coastline)) {
    return(NULL)
  }
  if (inherits(coastline, "sf")) {
    return(coastline)
  }
  check_sf()

  # TRUE means the medium scale. Anything else must be a scale name.
  scale <- if (isTRUE(coastline)) "medium" else coastline
  if (!is.character(scale) || length(scale) != 1L ||
      !scale %in% c("small", "medium", "large")) {
    rlang::abort(paste0(
      "`coastline` must be FALSE, TRUE, one of \"small\", \"medium\", ",
      "\"large\", or an `sf` object to draw."
    ))
  }
  # Fetch the countries layer, with a specific message for the large scale,
  # which needs a package not on CRAN.
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
