test_that("a break in effort starts a new track", {
  dat <- straight_line(n = 11)
  dat$BEAUFORT[5:7] <- 5 # three consecutive off-effort records
  dat <- split_tracks(point_to_point_effort(flag_effort(make_leg_id(dat))))

  # Effort before the break, the break itself, effort after: three tracks.
  expect_equal(length(unique(dat$new_trackno)), 3)
  # The break is one track, not one per record.
  expect_equal(length(unique(dat$new_trackno[dat$OnOff.Effort == 0])), 1)
  # Each on-effort track holds only on-effort records.
  on_tracks <- unique(dat$new_trackno[dat$OnOff.Effort == 1])
  expect_true(all(dat$OnOff.Effort[dat$new_trackno %in% on_tracks] == 1))
  # Only the two on-effort tracks survive the minimum-length filter.
  expect_equal(nrow(track_effort(dat)), 2)
})

test_that("a single off-effort record does not fragment a track", {
  # The rule needs two consecutive off-effort records, so a momentary
  # excursion logged as one point leaves the track intact.
  dat <- straight_line(n = 11)
  dat$BEAUFORT[6] <- 5
  dat <- split_tracks(point_to_point_effort(flag_effort(make_leg_id(dat))))
  expect_equal(length(unique(dat$new_trackno)), 1)
})

test_that("a new line occupation starts a new track", {
  dat <- dplyr::bind_rows(
    straight_line(n = 5, legno = 1),
    straight_line(n = 5, legno = 2, lat0 = 44)
  )
  dat$EVENTNO <- seq_len(nrow(dat))
  dat <- split_tracks(point_to_point_effort(flag_effort(make_leg_id(dat))))
  expect_equal(length(unique(dat$new_trackno)), 2)
})

test_that("track numbers restart on each survey date", {
  a <- straight_line(n = 5, date = "2024-04-01")
  b <- straight_line(n = 5, date = "2024-04-02", lat0 = 44)
  dat <- dplyr::bind_rows(a, b)
  dat$EVENTNO <- seq_len(nrow(dat))
  dat <- split_tracks(point_to_point_effort(flag_effort(make_leg_id(dat))))
  expect_equal(unique(dat$new_trackno[dat$DATE == as.Date("2024-04-01")]), "1")
  expect_equal(unique(dat$new_trackno[dat$DATE == as.Date("2024-04-02")]), "1")
})

test_that("multi-record circling splits the track, and the fixture shows it", {
  dat <- example_data()
  d <- split_tracks(point_to_point_effort(flag_effort(make_leg_id(dat))))
  day1 <- d[d$DATE == as.Date("2024-04-01") &
              !is.na(d$LEGNO2) & d$LEGNO2 == "2", ]

  break_off <- day1$new_trackno[!is.na(day1$LEGSTAGE) & day1$LEGSTAGE == 3]
  circling <- unique(day1$new_trackno[day1$LEGTYPE == 4])
  resume <- day1$new_trackno[!is.na(day1$LEGSTAGE) & day1$LEGSTAGE == 4]

  # Three distinct tracks: line, circling excursion, line again.
  expect_length(unique(c(break_off, circling, resume)), 3)
  expect_length(circling, 1)
  # The circling track carries no effort and is dropped.
  te <- track_effort(d)
  expect_false(circling %in% te$new_trackno[te$DATE == as.Date("2024-04-01")])
})

test_that("the midpoint sits halfway along the segment, not at the centroid", {
  # A line whose records are deliberately bunched at one end: the coordinate
  # mean is pulled towards the bunch, the along-track midpoint is not.
  dat <- tibble::tibble(
    FILEID = "T", EVENTNO = 1:6, YEAR = 2024L, MONTH = 4L, DAY = 1L,
    TIME = 120000 + 1:6,
    LATITUDE = c(43.000, 43.001, 43.002, 43.003, 43.050, 43.100),
    LONGITUDE = -69, LEGTYPE = 2, LEGSTAGE = 2, LEGNO = 1,
    ALT = 229, BEAUFORT = 2, VISIBLTY = 5,
    SPECCODE = NA_character_, IDREL = NA_real_, NUMBER = NA_real_,
    DATE = as.Date("2024-04-01")
  )
  segs <- segment_survey(dat, seg_length = 100, seed = 1) # one segment
  expect_equal(nrow(segs$segments), 1)

  # Total span is 43.000 to 43.100, so half the effort is at 43.050.
  expect_equal(segs$segments$mid_lat, 43.05, tolerance = 1e-6)
  # The centroid of the coordinates is well south of that.
  expect_lt(mean(dat$LATITUDE), 43.03)
})

test_that("midpoints lie on the line for every segment", {
  dat <- straight_line(n = 101, step = 0.01, lon = -69)
  segs <- segment_survey(dat, seg_length = 5, seed = 2)
  expect_true(all(abs(segs$segments$mid_lon - (-69)) < 1e-9))
  expect_true(all(segs$segments$mid_lat >= 43))
  expect_true(all(segs$segments$mid_lat <= 44))
  # Midpoints increase monotonically along a northbound line.
  expect_false(is.unsorted(segs$segments$mid_lat))
})

test_that("gc_interpolate hits the endpoints and the midpoint", {
  a <- gc_interpolate(43, -69, 44, -69, 0)
  expect_equal(a$lat, 43); expect_equal(a$lon, -69)

  b <- gc_interpolate(43, -69, 44, -69, 1)
  expect_equal(b$lat, 44, tolerance = 1e-9)

  m <- gc_interpolate(43, -69, 44, -69, 0.5)
  expect_equal(m$lat, 43.5, tolerance = 1e-6)
})

test_that("gc_interpolate handles coincident endpoints", {
  p <- gc_interpolate(43, -69, 43, -69, 0.5)
  expect_equal(p$lat, 43)
  expect_equal(p$lon, -69)
})
