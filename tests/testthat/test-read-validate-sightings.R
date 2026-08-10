test_that("LAT_DD and LONG_DD are accepted", {
  dat <- example_data()
  expect_true(all(c("LATITUDE", "LONGITUDE") %in% names(dat)))
  expect_false(any(c("LAT_DD", "LONG_DD") %in% names(dat)))
  expect_type(dat$LATITUDE, "double")
})

test_that("a canonical name is never clobbered by its alias", {
  raw <- data.frame(
    FILEID = "A", EVENTNO = 1, YEAR = 2024, MONTH = 4, DAY = 1, TIME = 120000,
    LATITUDE = 43, LAT_DD = 99, LONGITUDE = -69, LEGTYPE = 2
  )
  dat <- read_narwc(raw)
  expect_equal(dat$LATITUDE, 43)
})

test_that("NARWC missing-value placeholders become NA", {
  raw <- data.frame(
    FILEID = "A", EVENTNO = "1", YEAR = "2024", MONTH = "4", DAY = "1",
    TIME = "120000", LATITUDE = "43", LONGITUDE = "-69", LEGTYPE = "2",
    LEGNO = ".", SPECCODE = "", stringsAsFactors = FALSE
  )
  dat <- read_narwc(raw)
  expect_true(is.na(dat$LEGNO))
  expect_true(is.na(dat$SPECCODE))
})

test_that("DATE is derived", {
  dat <- example_data()
  expect_s3_class(dat$DATE, "Date")
  expect_equal(min(dat$DATE), as.Date("2024-04-01"))
})

test_that("extra columns can be carried through", {
  raw <- data.frame(
    FILEID = "A", EVENTNO = 1, YEAR = 2024, MONTH = 4, DAY = 1, TIME = 120000,
    LATITUDE = 43, LONGITUDE = -69, LEGTYPE = 2, Effort_Type = "on"
  )
  # Dropping it is now reported; that the message happens is tested in
  # test-profiles.R, so keep it out of the way here.
  expect_false("Effort_Type" %in% names(suppressMessages(read_narwc(raw))))
  expect_true("Effort_Type" %in% names(read_narwc(raw, extra_columns = "Effort_Type")))
  expect_true("Effort_Type" %in% names(read_narwc(raw, extra_columns = NULL)))
})

test_that("a missing file is reported clearly", {
  expect_error(read_narwc("no/such/file.csv"), "not found")
})

test_that("the bundled fixture raises nothing above a note", {
  issues <- validate_narwc(example_data())
  expect_setequal(issues$severity, "note")

  # The one note is the line abandoned when the sea state rose, which has no
  # end-line record. That is a property of the fixture, not a defect in it.
  expect_equal(issues$check, "legstage_line_not_closed")
  expect_equal(issues$n, 1L)
})

test_that("a missing required column is an error-level finding", {
  dat <- example_data()
  dat$LATITUDE <- NULL
  iss <- validate_narwc(dat)
  expect_true("missing_required" %in% iss$check)
  expect_equal(iss$severity[iss$check == "missing_required"], "error")
})

test_that("out-of-book codes are flagged", {
  dat <- example_data()
  dat$LEGTYPE[1] <- 8 # not a NARWC LEGTYPE
  dat$IDREL[!is.na(dat$IDREL)][1] <- 4
  iss <- validate_narwc(dat)
  expect_setequal(iss$column[iss$check == "unknown_code"], c("LEGTYPE", "IDREL"))
})

test_that("sightings at line-boundary events are flagged", {
  dat <- example_data()
  i <- which(dat$LEGSTAGE == 1)[1]
  dat$SPECCODE[i] <- "RIWH"
  iss <- validate_narwc(dat)
  expect_true("sighting_at_boundary" %in% iss$check)
})

test_that("lost longitude sign convention is flagged", {
  dat <- example_data()
  dat$LONGITUDE <- abs(dat$LONGITUDE)
  iss <- validate_narwc(dat)
  expect_true("positive_west_longitude" %in% iss$check)
})

test_that("mis-sorted events are flagged", {
  dat <- example_data()
  dat$EVENTNO[10] <- 1
  iss <- validate_narwc(dat)
  expect_true("eventno_not_increasing" %in% iss$check)
})

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
  seg4 <- segs$segments$seg_id[segs$segments$LEGNO3 == "4_8"]
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
  segs <- segment_survey(dat, seg_length = 100, seed = 1)
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
