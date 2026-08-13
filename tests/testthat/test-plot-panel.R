prepped <- function() prepare_aerial(example_data(), quiet = TRUE)

test_that("it draws several views on one figure", {
  p <- plot_survey_panel(prepped(), c("raw", "occupations"), coastline = FALSE)
  expect_s3_class(p, "patchwork")
})

test_that("views default to the ones the data can answer", {
  raw_only <- example_data()
  expect_equal(plot_survey_panel(raw_only, coastline = FALSE)$patches$layout$ncol, 2)

  # A raw frame has LEGTYPE and LEGSTAGE but no occupations or effort yet.
  expect_setequal(available_views(raw_only), c("raw", "legstage"))
  expect_true(all(c("raw", "legstage", "occupations", "effort") %in%
                    available_views(prepped())))
})

test_that("a view whose stage has not run is skipped, not fatal", {
  expect_s3_class(plot_survey_panel(example_data(), coastline = FALSE),
                  "patchwork")
})

test_that("data answering no view at all is an error", {
  d <- example_data()[, c("LATITUDE", "LONGITUDE")]
  expect_error(plot_survey_panel(d, coastline = FALSE), "None of the views")
})

test_that("by_day writes one figure per survey day", {
  dir <- withr::local_tempdir()
  paths <- plot_survey_panel(prepped(), c("raw", "occupations"), by_day = TRUE,
                             dir = dir, coastline = FALSE)
  expect_length(paths, 2)                       # the fixture is two days
  expect_true(all(file.exists(paths)))
  expect_match(basename(paths[1]), "^survey-2024-04-0[12]\\.png$")
})

test_that("by_day needs a DATE column", {
  d <- prepped()
  d$DATE <- NULL
  expect_error(plot_survey_panel(d, by_day = TRUE, dir = tempdir(),
                                 coastline = FALSE), "DATE")
})

test_that("the panel title says when and how much", {
  p <- plot_survey_panel(prepped(), "raw", coastline = FALSE)
  expect_match(p$patches$annotation$title, "2 survey days")
  expect_match(p$patches$annotation$title, "records")
})
