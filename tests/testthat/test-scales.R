okabe <- c("#E69F00", "#56B4E9", "#009E73", "#F0E442",
           "#0072B2", "#D55E00", "#CC79A7", "#000000")

test_that("the palette is Okabe-Ito, not ggplot2's hue wheel", {
  # This is the assertion that keeps it from regressing silently: a scale that
  # quietly goes back to the default still draws a perfectly nice plot, and
  # nobody notices until someone who cannot read it tries to.
  # A manual scale hands back its whole palette and ggplot2 takes the first n.
  expect_equal(scale_colour_safe(4)$palette(4)[1:4], okabe[1:4])
  expect_equal(scale_fill_safe(3)$palette(3)[1:3], okabe[1:3])
})

test_that("past eight levels it falls back to viridis rather than running out", {
  # Brewer "Dark2" has eight colours. Asked for 36 it returned NA for the rest,
  # which is what drew a legend of 28 labels with no colour beside them.
  s <- scale_colour_safe(36)
  cols <- s$palette(36)
  expect_length(cols, 36)
  expect_false(anyNA(cols))
  expect_match(cols, "^#[0-9A-Fa-f]{6}", all = TRUE)
})

test_that("groups are named while few and recycled once many", {
  ids <- c("a", "b", "c")
  cap <- capped_groups(ids, max_legend = 12)
  expect_true(cap$named)
  expect_equal(cap$n, 3)
  expect_equal(levels(cap$col), c("a", "b", "c"))

  cap <- capped_groups(ids, max_legend = 2)
  expect_false(cap$named)
  expect_equal(cap$n, 3)                       # still reports the true count
  expect_lte(nlevels(cap$col), 8)
})

test_that("lumping keeps the most seen and gathers the tail", {
  # 36 species is not a legend. Eight and "28 more" is - and every sighting
  # stays on the map, which dropping the tail would not manage.
  x <- c(rep("RIWH", 10), rep("HUWH", 5), rep("FIWH", 3), "SEWH", "MIWH")
  f <- lump_levels(x, max_levels = 3)
  expect_equal(levels(f), c("RIWH", "HUWH", "other (3 more)"))
  expect_equal(sum(f == "other (3 more)"), 5)
  expect_length(f, length(x))                  # nothing dropped

  # Under the cap, everything keeps its own name.
  expect_equal(levels(lump_levels(x, max_levels = 8)), sort(unique(x)))
})

test_that("lumping counts the other entry, so a cap of 8 needs 8 colours", {
  # Keeping 8 and *adding* "other" makes 9, which tipped a palette of exactly
  # eight over to the viridis fallback for want of one colour.
  x <- rep(letters[1:20], times = 20:1)
  expect_equal(nlevels(lump_levels(x, max_levels = 8)), 8)
})

test_that("legends gain a second column before they run the height of a map", {
  expect_equal(legend_guide(5)$guides$colour$params$ncol, 1)
  expect_equal(legend_guide(30)$guides$colour$params$ncol, 2)
})

test_that("points shrink as they multiply", {
  # 19,774 midpoints at the default size covered the survey area in black.
  expect_gt(point_size_for(100), point_size_for(20000))
})
