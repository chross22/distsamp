## Colour and legend helpers shared by every map in the package.
##
## Two problems recur on the real archive: legends with more entries than a
## legend can hold, and palettes that cannot be read. Both are handled here so
## every plot handles them the same way.

# Okabe-Ito: eight qualitative colours that stay distinguishable under the
# common forms of colour blindness. ggplot2's default hue wheel does not.
# Brewer's "Dark2" stops at eight, past which ggplot2 returns NA colours.
okabe_ito <- c(
  "#E69F00", "#56B4E9", "#009E73", "#F0E442",
  "#0072B2", "#D55E00", "#CC79A7", "#000000"
)

# Sorted unique non-missing levels of `x`, as character. If every level looks
# like a number, they sort numerically (so 10 comes after 2, not between 1 and
# 2); otherwise alphabetically. Order of appearance is not used because it
# follows the order flown, which is meaningless in a legend.
sort_levels <- function(x) {
  u <- unique(stats::na.omit(as.character(x)))
  if (length(u) && all(grepl("^-?[0-9]+(\\.[0-9]+)?$", u))) {
    u[order(as.numeric(u))]
  } else {
    sort(u)
  }
}

# Colour grouping for identifiers such as track or occupation numbers.
# Returns a list: `named` (TRUE if the legend lists each identifier), `n`
# (number of distinct identifiers), and `col` (the factor to map to colour).
#
# With few enough identifiers, each gets its own colour and legend entry.
# Beyond that, colours are recycled from the palette in order of appearance,
# so only neighbours need to differ, and no legend is drawn.
#
# The limit is the smaller of `max_legend` (how long a legend may be) and the
# palette size (how many colours can be told apart). Without the palette
# limit, 9 to 12 identifiers would be drawn on the viridis ramp, which reads
# as an order that a track number does not have.
#
# `max_legend = Inf` means the caller is colouring a meaning (a LEGSTAGE, a
# platform), not an identifier. The levels then always keep their names, and
# the viridis fallback is intended.
capped_groups <- function(values, max_legend = 12) {
  ids <- as.character(values)
  levs <- sort_levels(ids)
  # Effective limit on named levels.
  cap <- if (is.finite(max_legend)) {
    min(max_legend, length(okabe_ito))
  } else {
    max_legend
  }
  named <- length(levs) <= cap

  # Recycled colours: the identifier's order of appearance modulo 8.
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

# Reduce a factor to at most `max_levels` levels, gathering the rest under
# one label.
#
# Used for meanings such as species codes, where colours cannot be recycled:
# RIWH must stay identifiable. The most frequent levels keep their own colour
# and legend entry, the rest become one labelled group (e.g. "other (29
# more)"), and every sighting stays on the map.
#
# `max_levels` includes the "other" entry, because the caller cares about how
# many colours the scale needs. Keeping 8 and adding "other" would make 9 and
# push a palette of 8 over to the fallback.
lump_levels <- function(x, max_levels = 8L, other = "other") {
  # Count levels, most frequent first. Few enough: keep them all, sorted.
  ids <- as.character(x)
  tab <- sort(table(ids, useNA = "no"), decreasing = TRUE)
  if (length(tab) <= max_levels) {
    return(factor(ids, levels = sort_levels(ids)))
  }
  # Keep the max_levels - 1 most frequent; relabel the rest.
  top <- names(tab)[seq_len(max_levels - 1L)]
  lab <- paste0(other, " (", length(tab) - length(top), " more)")
  ids[!ids %in% top] <- lab
  factor(ids, levels = c(top, lab))
}

# Colour scale for `n` levels: Okabe-Ito up to eight, viridis beyond. No
# qualitative set past eight stays colourblind-safe; viridis at least stays
# legible. Missing values are grey.
scale_colour_safe <- function(n, ...) {
  if (n <= length(okabe_ito)) {
    ggplot2::scale_colour_manual(values = unname(okabe_ito),
                                 na.value = "grey60", ...)
  } else {
    ggplot2::scale_colour_viridis_d(na.value = "grey60", ...)
  }
}

# The same palette for the `fill` aesthetic. ggplot2 allows one scale per
# aesthetic, so when sightings are drawn over a coloured effort layer, effort
# uses `colour` and sightings use `fill` (as outlined markers).
scale_fill_safe <- function(n, ...) {
  if (n <= length(okabe_ito)) {
    ggplot2::scale_fill_manual(values = unname(okabe_ito),
                               na.value = "grey60", ...)
  } else {
    ggplot2::scale_fill_viridis_d(na.value = "grey60", ...)
  }
}

# Sighting rows of a point-level survey frame: rows with a non-blank
# SPECCODE, optionally restricted to the codes in `species`. Returns NULL when
# there are none or SPECCODE is absent.
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

# Colour legend layout for `n` entries: keys large enough to read a colour
# from, and two columns once there are more than 12 entries.
legend_guide <- function(n) {
  ggplot2::guides(colour = ggplot2::guide_legend(
    override.aes = list(size = 2.8, alpha = 1, linewidth = 0),
    ncol = if (n > 12L) 2L else 1L,
    keyheight = ggplot2::unit(0.85, "lines")
  ))
}

# Point size for a plot of `n` points. Larger counts get smaller points, so
# that tens of thousands of points do not merge into a solid mass.
point_size_for <- function(n) {
  if (n <= 500L) 1.6 else if (n <= 5000L) 0.8 else 0.4
}
