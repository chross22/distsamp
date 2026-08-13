staged <- function() {
  narwcr::flag_effort(narwcr::make_leg_id(example_data(), quiet = TRUE))
}

test_that("each view draws from the stage that provides its column", {
  d <- staged()
  expect_s3_class(plot_survey(d, "effort"), "ggplot")
  expect_s3_class(plot_survey(d, "occupations"), "ggplot")
  expect_s3_class(plot_survey(d, "legstage"), "ggplot")

  d <- split_tracks(point_to_point_effort(d))
  expect_s3_class(plot_survey(d, "tracks"), "ggplot")
})

test_that("a view whose column is missing says which stage adds it", {
  expect_error(plot_survey(example_data(), "effort"), "flag_effort")
  expect_error(plot_survey(example_data(), "tracks"), "split_tracks")
  expect_error(plot_survey(example_data(), "platform"), "classify_platform")
})

test_that("position is required whatever the view", {
  d <- staged()
  d$LATITUDE <- NULL
  expect_error(plot_survey(d, "effort"), "LATITUDE")
})

test_that("thinning takes every nth and says so", {
  d <- staged()
  p <- plot_survey(d, "effort", max_points = 20)
  expect_lte(nrow(p$data), 20)
  expect_match(p$labels$subtitle, "thinned from")
})

test_that("nothing is thinned when it fits", {
  p <- plot_survey(staged(), "effort")
  expect_equal(nrow(p$data), nrow(staged()))
  expect_no_match(p$labels$subtitle, "thinned")
})

test_that("occupations get recycled colours, not one per level", {
  # 700 occupations cannot have 700 distinguishable colours, and do not need
  # to: what matters is that neighbours differ.
  p <- plot_survey(staged(), "occupations")
  expect_lte(length(levels(p$data$.col)), 8)
  expect_match(p$labels$subtitle, "occupations drawn")
})

test_that("faceting by day happens only where it is readable", {
  d <- staged()                                   # 2 days
  expect_true(length(plot_survey(d, "effort")$facet$params$facets) > 0)

  d$DATE <- as.Date("2024-04-01") + seq_len(nrow(d))   # every record its own day
  expect_equal(length(plot_survey(d, "effort")$facet$params$facets), 0)
})

test_that("records on no occupation are drawn but not joined into one", {
  d <- staged()
  p <- plot_survey(d, "occupations")
  # The main layer holds only records that belong to an occupation.
  expect_false(any(is.na(p$data$LEGNO3)))
  expect_match(p$labels$subtitle, "on none \\(grey\\)")
})

test_that("a view with nothing loose says nothing about it", {
  d <- staged()
  d <- d[!is.na(d$LEGNO3), ]
  expect_no_match(plot_survey(d, "occupations")$labels$subtitle, "on none")
})
