
test_that("segment_survey() fills LEGSTAGE so mid-line sightings get distances", {
  # Programmes record LEGSTAGE when it changes. A sighting with none of its own
  # was ineligible for a distance unless prepare_survey() had run first.
  dat <- example_data()
  # Only those in state 2: blanking a 6 or 7 would admit a sighting the
  # LEGSTAGE filter is meant to exclude.
  sighted <- which((!is.na(dat$ANGLEL) | !is.na(dat$ANGLER)) &
                     dat$LEGSTAGE %in% 2)
  dat$LEGSTAGE[sighted] <- NA

  segs <- suppressMessages(segment_survey(dat, seg_length = 5, seed = 1))
  expect_true(all(!is.na(segs$detections$distance)))
  expect_equal(nrow(segs$detections), 8)

  # And it is not done twice after prepare_survey().
  prepared <- suppressMessages(prepare_survey(dat, quiet = TRUE))
  expect_true("LEGSTAGE_FILLED" %in% names(prepared))
  again <- suppressMessages(segment_survey(prepared, seg_length = 5, seed = 1))
  expect_equal(again$detections$distance, segs$detections$distance)
})
