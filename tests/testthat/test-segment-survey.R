
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

test_that("an off-effort sighting kept inside a track is not counted", {
  # A lone off-effort record stays in its track; its sighting must not count.
  dat <- example_data()
  i <- which(!is.na(dat$ANGLEL) & dat$LEGSTAGE %in% 2)[1]
  base <- segment_survey(dat, seg_length = 5, seed = 1)
  dat$BEAUFORT[i] <- 5
  segs <- segment_survey(dat, seg_length = 5, seed = 1)

  expect_true(any(segs$points$EVENTNO == dat$EVENTNO[i] &
                    segs$points$OnOff.Effort == 0))
  expect_equal(sum(segs$sightings$n_animals),
               sum(base$sightings$n_animals) - dat$NUMBER[i])
  expect_equal(nrow(segs$detections), nrow(base$detections) - 1)
})

test_that("segment_sightings() counts everything when there is no effort column", {
  chopped <- data.frame(seg_id = c("a", "a"), pt2pt.effort = 1, seg_eff = 2,
                        SPECCODE = c("RIWH", NA), NUMBER = c(2, NA))
  out <- segment_sightings(chopped)
  expect_equal(out$sightings$n_animals, 2)
})
