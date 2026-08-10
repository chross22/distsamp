skip_if_not_installed("ggplot2")

segs_fixture <- function(...) {
  segment_survey(example_data(), seg_length = 5, seed = 1, ...)
}

test_that("every view builds a ggplot", {
  segs <- segs_fixture()
  for (what in c("segments", "tracks", "effort", "distances")) {
    p <- plot(segs, what = what)
    expect_s3_class(p, "ggplot")
    # Building is what catches a bad aesthetic or a missing column; the object
    # constructs happily either way.
    expect_no_error(ggplot2::ggplot_build(p))
  }
})

test_that("an unknown view is refused", {
  expect_error(plot(segs_fixture(), what = "sightings"))
})

test_that("the species filter reaches the layers", {
  segs <- segs_fixture()
  all_spp <- plot(segs, species = NULL)
  one <- plot(segs, species = "RIWH")

  # The sighting layer is the last one; it should carry fewer rows.
  n_all <- nrow(all_spp$layers[[3]]$data)
  n_one <- nrow(one$layers[[3]]$data)
  expect_gt(n_all, n_one)
  expect_true(all(one$layers[[3]]$data$SPECCODE == "RIWH"))
})

test_that("the effort view marks the target and its tolerance band", {
  p <- plot(segs_fixture(), what = "effort")
  built <- ggplot2::ggplot_build(p)

  # Solid line at the target, dashed at target +/- tolerance.
  expect_equal(built$data[[2]]$xintercept, 5)
  expect_setequal(built$data[[3]]$xintercept, c(2.5, 7.5))
})

test_that("the distance view reports how many detections carry a distance", {
  p <- plot(segs_fixture(), what = "distances")
  expect_match(p$labels$subtitle, "detections carry a distance")
  expect_match(p$labels$x, "\\(m\\)")

  km <- plot(segs_fixture(distance_units = "km"), what = "distances")
  expect_match(km$labels$x, "\\(km\\)")
})

test_that("the distance view says what to do when there are no distances", {
  bare <- example_data()
  bare$ANGLEL <- NULL
  bare$ANGLER <- NULL
  bare$S_LAT <- NULL
  bare$S_LONG <- NULL
  segs <- segment_survey(bare, seg_length = 5, seed = 1)
  expect_error(plot(segs, what = "distances"), "sighting_distances")
})

test_that("tracks facet only when there is more than one date", {
  multi <- plot(segs_fixture(), what = "tracks")
  expect_s3_class(multi$facet, "FacetWrap")

  one_day <- example_data()
  one_day <- one_day[one_day$DATE == min(one_day$DATE), ]
  single <- plot(segment_survey(one_day, seg_length = 5, seed = 1),
                 what = "tracks")
  expect_s3_class(single$facet, "FacetNull")
})

test_that("a plot is an ordinary ggplot and can be extended", {
  p <- plot(segs_fixture()) + ggplot2::labs(title = "changed")
  expect_equal(p$labels$title, "changed")
  expect_no_error(ggplot2::ggplot_build(p))
})
