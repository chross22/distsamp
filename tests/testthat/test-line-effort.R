prepped <- function() {
  point_to_point_effort(flag_effort(make_leg_id(example_data())))
}

test_that("effort is summarised per line occupation", {
  out <- line_effort(prepped())
  expect_true(all(c("DATE", "FILEID", "LEGNO", "LEGNO3", "occupation",
                    "effort_km", "n_records") %in% names(out)))
  # Five lines, one of them flown twice.
  expect_equal(nrow(out), 6)
  expect_equal(sum(out$occupation > 1), 1)
})

test_that("every kilometre of effort is accounted for exactly once", {
  dat <- prepped()
  expect_equal(sum(line_effort(dat)$effort_km),
               sum(track_effort(split_tracks(dat))$track_effort))
  expect_equal(sum(line_effort(dat, combine = "line")$effort_km),
               sum(line_effort(dat)$effort_km))
})

test_that("re-flights combine into one line", {
  by_line <- line_effort(prepped(), combine = "line")
  expect_equal(nrow(by_line), 5)

  four <- by_line[by_line$LEGNO == "4", ]
  expect_equal(four$n_occupations, 2L)
  # The fixture flies line 4, abandons it when the sea state rises, and returns
  # to it later the same day.
  expect_equal(four$n_days, 1L)
  expect_equal(four$effort_km, 3.3336 + 8.8896, tolerance = 1e-9)
})

test_that("a line occupation is not merged with a re-flight of the same LEGNO", {
  # LEGNO3 separates the two attempts; LEGNO alone would not.
  per <- line_effort(prepped())
  four <- per[per$LEGNO == "4", ]
  expect_equal(nrow(four), 2)
  expect_equal(four$occupation, 1:2)
  expect_false(four$LEGNO3[1] == four$LEGNO3[2])
})

test_that("the two re-flight rates are reported separately", {
  s <- reflight_summary(prepped())
  expect_equal(s$n_lines, 5L)
  expect_equal(s$n_occupations, 6L)
  expect_equal(s$n_lines_reflown, 1L)

  # One of five lines needed a second attempt; one of six occupations was a
  # repeat. The original computed the second and called it the first.
  expect_equal(s$prop_lines_reflown, 1 / 5)
  expect_equal(s$prop_occupations_repeat, 1 / 6)
  expect_false(isTRUE(all.equal(s$prop_lines_reflown,
                                s$prop_occupations_repeat)))
})

test_that("repeat effort is the effort on second and later attempts", {
  s <- reflight_summary(prepped())
  per <- line_effort(prepped())
  expect_equal(s$effort_km_repeat, sum(per$effort_km[per$occupation > 1]))
  expect_lt(s$effort_km_repeat, s$effort_km)
})

test_that("a survey with no re-flights reports a zero rate", {
  dat <- prepped()
  dat <- dat[dat$LEGNO3 != "4_8" | is.na(dat$LEGNO3), ]
  s <- reflight_summary(dat)
  expect_equal(s$n_lines_reflown, 0L)
  expect_equal(s$prop_lines_reflown, 0)
  expect_equal(s$prop_occupations_repeat, 0)
  expect_equal(s$effort_km_repeat, 0)
})

test_that("LEGNO3 is derived when it is absent", {
  dat <- prepped()
  dat$LEGNO3 <- NULL
  dat$LEGNO2 <- NULL
  expect_equal(nrow(line_effort(dat)), 6)
})

test_that("a segmentation is accepted, and says what it leaves out", {
  segs <- segment_survey(example_data(), seg_length = 5, seed = 1)
  expect_message(line_effort(segs), "reached a segment")

  # With the default thresholds nothing is lost: the records segmentation
  # leaves out are off effort, and those carry no distance.
  from_segs <- suppressMessages(line_effort(segs))
  from_points <- line_effort(prepped())
  expect_equal(sum(from_segs$effort_km), sum(from_points$effort_km))
})

test_that("a track dropped for being too short does cost effort", {
  # This is the case the message warns about. Line 4's first occupation is
  # 3.33 km, so a 5 km minimum discards it along with the distance it flew.
  segs <- segment_survey(example_data(), seg_length = 5, seed = 1,
                         min_track_km = 5)
  from_segs <- suppressMessages(line_effort(segs))
  from_points <- line_effort(prepped())

  expect_lt(sum(from_segs$effort_km), sum(from_points$effort_km))
  # And line 4 now looks like it was flown once rather than twice.
  four_segs <- from_segs[from_segs$LEGNO == "4", ]
  four_points <- from_points[from_points$LEGNO == "4", ]
  expect_lt(nrow(four_segs), nrow(four_points))
})

test_that("empty input gives an empty summary of the right shape", {
  empty <- prepped()[0, ]
  expect_equal(nrow(line_effort(empty)), 0)
  expect_equal(reflight_summary(empty)$n_lines, 0L)
})

test_that("records with no LEGNO are left out rather than grouped together", {
  dat <- prepped()
  # Transits carry no LEGNO and are not part of any line.
  expect_gt(sum(is.na(dat$LEGNO)), 0)
  expect_false(any(is.na(line_effort(dat)$LEGNO)))
})
