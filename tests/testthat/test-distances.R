test_that("the declination geometry is right", {
  # Handbook 8.A.2: angle below the horizon, taken when the sighting is
  # perpendicular to the track. So x = altitude / tan(angle).
  expect_equal(perp_distance(45, 229), 229)
  expect_equal(perp_distance(90, 229), 0)
  expect_equal(perp_distance(60, 229), 229 / tan(60 * pi / 180))
  expect_equal(perp_distance(30, 1000), 1000 / tan(30 * pi / 180))

  # Shallower angle, animal further from the track.
  d <- perp_distance(c(75, 60, 45, 30, 15), 229)
  expect_false(is.unsorted(d))
})

test_that("distance scales with altitude", {
  expect_equal(perp_distance(45, 500), 500)
  expect_equal(perp_distance(30, 458), 2 * perp_distance(30, 229))
})

test_that("units convert", {
  expect_equal(perp_distance(45, 229, units = "km"), 0.229)
  expect_equal(
    perp_distance(30, 229, units = "km") * 1000,
    perp_distance(30, 229, units = "m")
  )
})

test_that("angles that cannot describe a sighting give NA", {
  expect_true(is.na(perp_distance(0, 229)))    # on the horizon
  expect_true(is.na(perp_distance(-5, 229)))   # above the horizon
  expect_true(is.na(perp_distance(95, 229)))   # behind the aircraft
  expect_true(is.na(perp_distance(NA, 229)))
})

test_that("an unusable altitude gives NA", {
  expect_true(is.na(perp_distance(45, NA)))
  expect_true(is.na(perp_distance(45, 0)))
  expect_true(is.na(perp_distance(45, -100)))
})

test_that("perp_distance is vectorised and recycles", {
  expect_length(perp_distance(c(30, 45, 60), 229), 3)
  expect_length(perp_distance(45, c(200, 300)), 2)
  expect_equal(perp_distance(c(45, 45), c(100, 200)), c(100, 200))
})

test_that("side is taken from whichever angle column is populated", {
  dat <- tibble::tibble(
    ANGLEL = c(45, NA, 30, NA),
    ANGLER = c(NA, 45, 60, NA),
    ALT = 229, LEGTYPE = 2, LEGSTAGE = 2, OnOff.Effort = 1L
  )
  out <- sighting_distances(dat)
  expect_equal(out$side, c("left", "right", "both", NA))
  expect_equal(out$distance[1:2], c(229, 229))
  # Both sides recorded is ambiguous, so no distance.
  expect_true(is.na(out$distance[3]))
})

test_that("distances are restricted to on-effort census records by default", {
  dat <- tibble::tibble(
    ANGLEL = 45, ANGLER = NA, ALT = 229,
    LEGTYPE = c(2, 2, 1, 4), LEGSTAGE = c(2, 6, NA, NA),
    OnOff.Effort = c(1L, 1L, 0L, 0L)
  )
  out <- sighting_distances(dat)
  # Only the on-effort LEGSTAGE 2 record qualifies.
  expect_equal(sum(!is.na(out$distance)), 1)
  expect_equal(out$distance[1], 229)

  loose <- sighting_distances(dat, on_effort_only = FALSE)
  expect_equal(sum(!is.na(loose$distance)), 4)
})

test_that("data without angle columns still gets the columns", {
  dat <- tibble::tibble(ALT = 229, LEGTYPE = 2, LEGSTAGE = 2, OnOff.Effort = 1L)
  out <- sighting_distances(dat)
  expect_true(all(c("distance", "side") %in% names(out)))
  expect_true(is.na(out$distance))
})

test_that("the fixture's detections carry the expected distances", {
  segs <- segment_survey(example_data(), seg_length = 5, seed = 1)
  det <- segs$detections

  expect_true(all(c("seg_id", "SPECCODE", "size", "distance", "side") %in% names(det)))
  expect_gt(nrow(det), 0)

  # Every distance is reproducible from the recorded angle and 229 m altitude.
  with_dist <- det[!is.na(det$distance), ]
  expect_gt(nrow(with_dist), 0)
  expect_true(all(with_dist$distance > 0))
  expect_true(all(with_dist$side %in% c("left", "right")))

  # 45 degrees at 229 m is exactly 229 m; the fixture has one of those.
  expect_true(any(abs(with_dist$distance - 229) < 1e-8))
})

test_that("a circling detection is measured from the break-off, never guessed", {
  # `break_off` is the only option that makes a circling detection at all. The
  # default counts those animals into the group they were found with, which is
  # covered in test-attach-circling.R.
  segs <- segment_survey(example_data(), seg_length = 5, seed = 1,
                         circling = "same_species",
                         circling_distance = "break_off")
  det <- segs$detections
  circ <- det[!is.na(det$circling) & det$circling == 1, ]
  expect_gt(nrow(circ), 0)

  # Measured from where the aircraft left the line - not computed from an
  # angle, because none was taken, and not copied from another sighting.
  expect_false(anyNA(circ$distance))
  expect_equal(circ$distance, circ$break_off_distance)
  expect_true(all(circ$distance_source == "break_off"))
  expect_true(all(circ$break_off_distance > 0))

  # It is not perpendicular to anything, so there is no side of the line for
  # it to be on.
  expect_true(all(is.na(circ$side)))

  # And a sighting made from the line has no break-off to be measured from.
  on_line <- det[!is.na(det$circling) & det$circling == 0, ]
  expect_true(all(is.na(on_line$break_off_distance)))
})

test_that("excluded sightings never reach the detections table", {
  segs <- segment_survey(example_data(), seg_length = 5, seed = 1)
  # The fixture's pilot sighting (LEGSTAGE 6) carries an angle, so it would
  # produce a plausible-looking distance if the filter were not applied.
  expect_false("LOTU" %in% segs$detections$SPECCODE)
  expect_equal(sum(segs$detections$SPECCODE == "FIWH"), 1)
})

test_that("detections and sightings agree", {
  segs <- segment_survey(example_data(), seg_length = 5, seed = 1)
  from_det <- tapply(segs$detections$size, segs$detections$SPECCODE, sum)
  from_sig <- tapply(segs$sightings$n_animals, segs$sightings$SPECCODE, sum)
  expect_equal(from_det[order(names(from_det))], from_sig[order(names(from_sig))])
})

test_that("distance_units flows through segment_survey", {
  m <- segment_survey(example_data(), seg_length = 5, seed = 1)
  km <- segment_survey(example_data(), seg_length = 5, seed = 1,
                       distance_units = "km")
  expect_equal(m$detections$distance / 1000, km$detections$distance)
  expect_equal(km$settings$distance_units, "km")
})

test_that("out-of-range angles are flagged by validation", {
  dat <- example_data()
  i <- which(!is.na(dat$ANGLER))[1]
  dat$ANGLER[i] <- 120
  expect_true("angle_out_of_range" %in% validate_narwc(dat)$check)

  dat2 <- example_data()
  j <- which(!is.na(dat2$ANGLER))[1]
  dat2$ANGLEL[j] <- 30
  expect_true("angle_both_sides" %in% validate_narwc(dat2)$check)

  dat3 <- example_data()
  dat3$ALT <- NA
  expect_true("angle_without_altitude" %in% validate_narwc(dat3)$check)
})

test_that("segmentation is unaffected by the presence of angles", {
  with_angles <- example_data()
  without <- with_angles
  without$ANGLEL <- NULL
  without$ANGLER <- NULL
  # Exact positions are a distance source too now, so strip them as well or
  # this stops testing what it says it tests.
  without$S_LAT <- NULL
  without$S_LONG <- NULL

  a <- segment_survey(with_angles, seg_length = 5, seed = 1)
  b <- segment_survey(without, seg_length = 5, seed = 1)

  expect_equal(a$segments$seg_eff, b$segments$seg_eff)
  expect_equal(a$sightings, b$sightings)
  expect_true(all(is.na(b$detections$distance)))
})
