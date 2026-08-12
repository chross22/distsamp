test_that("pilot and photograph sightings are excluded by default", {
  dat <- example_data()
  segs <- segment_survey(dat, seg_length = 5, seed = 1)
  # The fixture puts a FIWH at LEGSTAGE 6 (pilot) and a LOTU at LEGSTAGE 7
  # (vertical photograph).
  expect_false("LOTU" %in% segs$sightings$SPECCODE)
  # One FIWH sighting is on effort and one is the pilot's; only the first
  # should be counted.
  fiwh <- segs$sightings[segs$sightings$SPECCODE == "FIWH", ]
  expect_equal(sum(fiwh$n_sightings), 1)
})

test_that("excluded LEGSTAGEs can be overridden", {
  dat <- example_data()
  segs <- segment_survey(
    dat, seg_length = 5, seed = 1,
    sighting_args = list(legstage_exclude = numeric(0))
  )
  fiwh <- segs$sightings[segs$sightings$SPECCODE == "FIWH", ]
  expect_equal(sum(fiwh$n_sightings), 2)
})

test_that("only definite and probable identifications count by default", {
  dat <- example_data()
  segs <- segment_survey(dat, seg_length = 5, seed = 1)
  # The fixture has a lone RIWH at IDREL 1 on the second occupation of line 4.
  # Chosen by position rather than by name: LEGNO3 carries an occupation
  # counter, and that counter moves whenever leg identification changes.
  occ4 <- unique(segs$segments$LEGNO3[startsWith(segs$segments$LEGNO3, "4_")])
  seg4 <- segs$segments$seg_id[segs$segments$LEGNO3 == occ4[length(occ4)]]
  expect_false(any(segs$sightings$seg_id %in% seg4))

  loose <- segment_survey(
    dat, seg_length = 5, seed = 1,
    sighting_args = list(idrel_keep = c(1, 2, 3))
  )
  expect_true(any(loose$sightings$seg_id %in% seg4))
})

test_that("groups sharing one event are counted separately", {
  dat <- example_data()
  segs <- segment_survey(dat, seg_length = 5, seed = 1)
  # Two RIWH groups (2 and 1 animals) plus a FIWH share one event on line 1.
  riwh <- segs$sightings[segs$sightings$SPECCODE == "RIWH", ]
  expect_true(any(riwh$n_sightings == 2 & riwh$n_animals == 3))
})

test_that("circling sightings are attached, and only for the same species", {
  dat <- example_data()
  none <- segment_survey(dat, seg_length = 5, seed = 1, circling = "none")
  same <- segment_survey(dat, seg_length = 5, seed = 1, circling = "same_species")

  riwh <- function(x) sum(x$sightings$n_animals[x$sightings$SPECCODE == "RIWH"])
  expect_equal(riwh(same), riwh(none) + 1)

  # Attaching a sighting must never change how much effort a segment carries.
  expect_equal(sum(same$segments$seg_eff), sum(none$segments$seg_eff))
})

test_that("flag_circling finds both circling signals", {
  dat <- flag_circling(make_leg_id(example_data()))
  expect_equal(sum(dat$CIRCLE), 5)
  expect_true(all(dat$LEGTYPE[dat$CIRCLE == 1] == 4))
  # The break-off and resume records stay on the line.
  expect_true(all(dat$CIRCLE[!is.na(dat$LEGSTAGE) & dat$LEGSTAGE %in% c(3, 4)] == 0))
})

test_that("weighted Beaufort weights by distance, not record count", {
  dat <- straight_line(n = 6, step = 0.01)
  # One record covers a long stretch at sea state 1; the rest are bunched.
  dat$LATITUDE <- c(43.000, 43.100, 43.101, 43.102, 43.103, 43.104)
  dat$BEAUFORT <- c(1, 3, 3, 3, 3, 3)
  # Five of the six fixes are bunched into 300 m, which implies a speed no
  # aircraft flies and trips the platform guard. Deliberate: the point is one
  # long stretch against several short ones.
  segs <- suppressWarnings(segment_survey(dat, seg_length = 100, seed = 1))
  expect_equal(segs$segments$mean_beaufort, mean(dat$BEAUFORT))
  # Nearly all the distance was flown at sea state 1.
  expect_lt(segs$segments$wt_beaufort, 1.2)
})

test_that("segments_wide gives one column per species with zeros, not NA", {
  segs <- segment_survey(example_data(), seg_length = 5, seed = 1)
  wide <- segments_wide(segs)
  expect_true("n_RIWH" %in% names(wide))
  expect_equal(nrow(wide), nrow(segs$segments))
  expect_false(anyNA(wide$n_RIWH))
  expect_equal(sum(wide$n_RIWH),
               sum(segs$sightings$n_animals[segs$sightings$SPECCODE == "RIWH"]))
})

test_that("crop_to_bbox restricts every table consistently", {
  segs <- segment_survey(example_data(), seg_length = 5, seed = 1)
  box <- c(xmin = -69.05, xmax = -68.5, ymin = 42, ymax = 48)
  cropped <- crop_to_bbox(segs, box)
  expect_lt(nrow(cropped$segments), nrow(segs$segments))
  expect_true(all(cropped$sightings$seg_id %in% cropped$segments$seg_id))
  expect_true(all(cropped$segments$mid_lon >= -69.05))
})

test_that("a reversed bounding box is tolerated", {
  dat <- example_data()
  a <- crop_to_bbox(dat, c(xmin = -71, xmax = -66, ymin = 42, ymax = 45))
  b <- crop_to_bbox(dat, c(xmin = -66, xmax = -71, ymin = 45, ymax = 42))
  expect_equal(nrow(a), nrow(b))
})

test_that("write_segments writes what was asked for and nothing else", {
  segs <- segment_survey(example_data(), seg_length = 5, seed = 1)
  dir <- withr::local_tempdir()
  write_segments(segs, dir, tables = c("segments", "sightings"))
  expect_setequal(
    list.files(dir),
    c("segments_segments.csv", "segments_sightings.csv")
  )
})
