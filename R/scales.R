## Colour and legend, in one place.
##
## Every map in this package colours points by some identifier, and every one of
## them met the same two problems on the real archive: a legend with more
## entries than a legend can hold, and a palette nobody could read. Both are
## solved here so they are solved the same way everywhere.

# Okabe-Ito: eight qualitative colours chosen to stay distinguishable under the
# common forms of colour blindness. ggplot2's default hue wheel is not, and
# Brewer's "Dark2" runs out at eight - past which ggplot2 hands back `NA` and
# draws a legend of colourless labels.
okabe_ito <- c(
  "#E69F00", "#56B4E9", "#009E73", "#F0E442",
  "#0072B2", "#D55E00", "#CC79A7", "#000000"
)

# Levels in an order a reader can follow. `unique()` gives order of appearance,
# which is what produced a LEGSTAGE legend reading 1, 2, 4, 3, 5, 6, 7 - the
# order the aircraft happened to fly them. Numbers sort as numbers, so that
# occupation 10 does not land between 1 and 2.
sort_levels <- function(x) {
  u <- unique(stats::na.omit(as.character(x)))
  if (length(u) && all(grepl("^-?[0-9]+(\\.[0-9]+)?$", u))) {
    u[order(as.numeric(u))]
  } else {
    sort(u)
  }
}

# Colour by the identifier itself where there are few enough to tell apart, so
# the legend says which line is which. Beyond `max_legend` a legend is a wall of
# labels and the colours cannot be distinguished anyway, so a small palette is
# recycled: what has to be visible then is only that neighbours differ.
capped_groups <- function(values, max_legend = 12) {
  ids <- as.character(values)
  levs <- sort_levels(ids)
  named <- length(levs) <= max_legend

  list(
    named = named,
    n = length(levs),
    col = if (named) {
      factor(ids, levels = levs)
    } else {
      factor(match(ids, unique(ids)) %% length(okabe_ito))
    }
  )
}

# Reduce to at most `max_levels` levels, gathering the rest under one label.
#
# For an identifier - a track, an occupation - recycling colours is right,
# because the only question is whether neighbours differ. For a *meaning* like
# a species code it is not: RIWH has to stay findable. So the common levels keep
# their own colour and their own legend entry, the tail becomes one labelled
# group, and every sighting stays on the map. 36 species is not a legend; eight
# and "29 more" is.
#
# `max_levels` counts the "other" entry, because the thing the caller cares
# about is how many colours the scale ends up needing. Keeping 8 *and* adding
# "other" makes 9, which tips a palette of exactly 8 over to the fallback.
lump_levels <- function(x, max_levels = 8L, other = "other") {
  ids <- as.character(x)
  tab <- sort(table(ids, useNA = "no"), decreasing = TRUE)
  if (length(tab) <= max_levels) {
    return(factor(ids, levels = sort_levels(ids)))
  }
  top <- names(tab)[seq_len(max_levels - 1L)]
  lab <- paste0(other, " (", length(tab) - length(top), " more)")
  ids[!ids %in% top] <- lab
  factor(ids, levels = c(top, lab))
}

# Okabe-Ito while its eight last, viridis after. There is no qualitative set
# past eight that stays colourblind-safe, and a continuous scale read as
# categories is the better failure - it is at least ordered and at least legible.
scale_colour_safe <- function(n, ...) {
  if (n <= length(okabe_ito)) {
    ggplot2::scale_colour_manual(values = unname(okabe_ito),
                                 na.value = "grey60", ...)
  } else {
    ggplot2::scale_colour_viridis_d(na.value = "grey60", ...)
  }
}

# The same palette through the `fill` channel. Sightings drawn over a coloured
# effort layer need a scale of their own, and ggplot2 allows one scale per
# aesthetic - so the effort keeps `colour` and the sightings take `fill`, drawn
# as outlined markers that read as points on top rather than more of the track.
scale_fill_safe <- function(n, ...) {
  if (n <= length(okabe_ito)) {
    ggplot2::scale_fill_manual(values = unname(okabe_ito),
                               na.value = "grey60", ...)
  } else {
    ggplot2::scale_fill_viridis_d(na.value = "grey60", ...)
  }
}

# Sighting rows in a point-level survey frame: the ones naming a species.
survey_sightings <- function(dat, species = NULL) {
  if (!"SPECCODE" %in% names(dat)) {
    return(NULL)
  }
  code <- blank_to_na(as.character(dat$SPECCODE))
  out <- dat[!is.na(code), , drop = FALSE]
  if (is.character(species)) {
    out <- out[as.character(out$SPECCODE) %in% species, , drop = FALSE]
  }
  if (!nrow(out)) NULL else out
}

# A legend that does not squeeze the map: keys big enough to read a colour off,
# and a second column before a single one runs the height of the plot.
legend_guide <- function(n) {
  ggplot2::guides(colour = ggplot2::guide_legend(
    override.aes = list(size = 2.8, alpha = 1, linewidth = 0),
    ncol = if (n > 12L) 2L else 1L,
    keyheight = ggplot2::unit(0.85, "lines")
  ))
}

# Enough points and they stop being points and become a black mass: 19,774
# segment midpoints at the default size covered the survey area entirely.
point_size_for <- function(n) {
  if (n <= 500L) 1.6 else if (n <= 5000L) 0.8 else 0.4
}
