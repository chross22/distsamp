test_that("one degree of latitude is 111.12 km", {
  expect_equal(gc_distance(43, -69, 44, -69, method = "becker"), KM_PER_DEG)
  expect_equal(gc_distance(43, -69, 44, -69, method = "kenney"), KM_PER_DEG)
  expect_equal(gc_distance(43, -69, 44, -69, method = "haversine"), KM_PER_DEG)
})

test_that("Becker and Kenney are the same formula", {
  set.seed(42)
  lat1 <- runif(50, 25, 50); lon1 <- runif(50, -80, -60)
  lat2 <- runif(50, 25, 50); lon2 <- runif(50, -80, -60)
  expect_identical(
    gc_distance(lat1, lon1, lat2, lon2, method = "becker"),
    gc_distance(lat1, lon1, lat2, lon2, method = "kenney")
  )
})

test_that("historical aliases resolve", {
  expect_identical(
    gc_distance(43, -69, 44, -70, method = "eab"),
    gc_distance(43, -69, 44, -70, method = "becker")
  )
  expect_identical(
    gc_distance(43, -69, 44, -70, method = "rdk"),
    gc_distance(43, -69, 44, -70, method = "kenney")
  )
})

test_that("haversine agrees with the law of cosines at survey scales", {
  set.seed(7)
  lat1 <- runif(200, 35, 48); lon1 <- runif(200, -75, -60)
  # Displacements of the size seen between consecutive survey records.
  lat2 <- lat1 + runif(200, -0.05, 0.05)
  lon2 <- lon1 + runif(200, -0.05, 0.05)
  hav <- gc_distance(lat1, lon1, lat2, lon2, method = "haversine")
  cos <- gc_distance(lat1, lon1, lat2, lon2, method = "becker")
  # Well inside a millimetre.
  expect_lt(max(abs(hav - cos)), 1e-6)
})

test_that("distances are symmetric, zero, and NA in the right places", {
  expect_equal(gc_distance(43, -69, 44, -70), gc_distance(44, -70, 43, -69))
  expect_identical(gc_distance(43, -69, 43, -69), 0)
  expect_true(is.na(gc_distance(43, NA, 44, -70)))
  expect_true(is.na(gc_distance(43, -69, NA, -70)))
})

test_that("gc_distance is vectorised and recycles", {
  d <- gc_distance(c(43, 44), -69, c(44, 45), -69)
  expect_length(d, 2)
  expect_equal(d, c(KM_PER_DEG, KM_PER_DEG))
})

test_that("an unknown method is rejected", {
  expect_error(gc_distance(43, -69, 44, -69, method = "vincenty"))
})

test_that("point-to-point effort sums to the line length", {
  dat <- straight_line(n = 21, step = 0.01)
  dat <- point_to_point_effort(flag_effort(make_leg_id(dat)))
  # 20 intervals of 0.01 degrees
  expect_equal(sum(dat$pt2pt.effort), 20 * 0.01 * KM_PER_DEG)
  # Effort is attributed to the first record of each pair, so the last is zero.
  expect_equal(dat$pt2pt.effort[nrow(dat)], 0)
  expect_true(all(dat$Effort == sum(dat$pt2pt.effort)))
})

test_that("off-effort records contribute no distance", {
  dat <- straight_line(n = 11, step = 0.01)
  dat$BEAUFORT[6:11] <- 5 # above the default cutoff
  dat <- point_to_point_effort(flag_effort(make_leg_id(dat)))
  # Only the five intervals among records 1-5 count.
  expect_equal(sum(dat$pt2pt.effort), 4 * 0.01 * KM_PER_DEG)
})

test_that("effort never crosses a re-occupation of the same line", {
  # Same LEGNO flown twice, far apart. Joining them would add a huge distance.
  a <- straight_line(n = 5, lat0 = 43.0, legno = 7)
  b <- straight_line(n = 5, lat0 = 44.0, legno = 7)
  b$EVENTNO <- b$EVENTNO + 100
  b$TIME <- b$TIME + 10000
  other <- straight_line(n = 3, lat0 = 43.5, legno = 8)
  other$EVENTNO <- other$EVENTNO + 50
  other$TIME <- other$TIME + 5000

  dat <- dplyr::bind_rows(a, other, b)
  dat <- point_to_point_effort(flag_effort(make_leg_id(dat)))

  expect_equal(length(unique(dat$LEGNO3)), 3)
  # 4 + 2 + 4 intervals, and nothing bridging 43.04 to 44.00
  expect_equal(sum(dat$pt2pt.effort), (4 + 2 + 4) * 0.01 * KM_PER_DEG)
})

test_that("empty input gives empty output", {
  dat <- straight_line(n = 21)[0, ]
  out <- point_to_point_effort(flag_effort(make_leg_id(dat)))
  expect_equal(nrow(out), 0)
  expect_true("pt2pt.effort" %in% names(out))
})

test_that("a constant FILEID does not merge two survey days", {
  # The real-extract failure: FILEID is the same string on every row, and the
  # two days share a LEGNO, so LEGNO3 never increments. Only DATE separates
  # them, and without it the ferry south is counted as on-effort track.
  day1 <- straight_line(n = 21, lat0 = 43, legno = 5, date = "2024-04-01")
  day2 <- straight_line(n = 21, lat0 = 40, legno = 5, date = "2024-04-02")
  day2$EVENTNO <- day2$EVENTNO + 100
  dat <- dplyr::bind_rows(day1, day2)
  dat$FILEID <- "F"
  dat <- flag_effort(make_leg_id(dat))

  # `make_leg_id()` now bounds an occupation by DATE, so it will not hand back
  # a LEGNO3 that spans two days. The frame is forced into that state here
  # because it is still reachable — a LEGNO3 computed by an earlier version,
  # or supplied by the caller — and DATE in the grouping is what catches it.
  dat$LEGNO3 <- "5_1"
  expect_equal(length(unique(dat$LEGNO3)), 1)

  correct <- 2 * 20 * 0.01 * KM_PER_DEG
  expect_equal(sum(point_to_point_effort(dat)$pt2pt.effort), correct)

  # The old default counts the ferry as effort. Day 1 climbs 0.20 degrees
  # before it ends, so the gap down to day 2 is 3.20 degrees, not 3.00.
  merged <- point_to_point_effort(dat, by = c("FILEID", "LEGNO3"))
  expect_equal(sum(merged$pt2pt.effort), correct + 3.2 * KM_PER_DEG)
  expect_gt(sum(merged$pt2pt.effort), 8 * correct)
})

test_that("a begin-line record separates the days on its own", {
  # The other defence: where LEGSTAGE is recorded, each day's begin-line
  # record opens its own occupation, so the days never merge even if the
  # grouping had no DATE in it.
  day1 <- straight_line(n = 21, lat0 = 43, legno = 5, date = "2024-04-01")
  day2 <- straight_line(n = 21, lat0 = 40, legno = 5, date = "2024-04-02")
  day2$EVENTNO <- day2$EVENTNO + 100
  dat <- dplyr::bind_rows(day1, day2)
  dat$FILEID <- "F"
  dat <- flag_effort(make_leg_id(dat))

  expect_equal(length(unique(dat$LEGNO3)), 2)
  correct <- 2 * 20 * 0.01 * KM_PER_DEG
  expect_equal(sum(point_to_point_effort(dat)$pt2pt.effort), correct)
  expect_equal(
    sum(point_to_point_effort(dat, by = c("FILEID", "LEGNO3"))$pt2pt.effort),
    correct
  )
})

test_that("Effort is per day when the days would otherwise merge", {
  day1 <- straight_line(n = 21, lat0 = 43, legno = 5, date = "2024-04-01")
  day2 <- straight_line(n = 21, lat0 = 40, legno = 5, date = "2024-04-02")
  day2$EVENTNO <- day2$EVENTNO + 100
  dat <- dplyr::bind_rows(day1, day2)
  dat$FILEID <- "F"
  dat <- point_to_point_effort(flag_effort(make_leg_id(dat)))

  per_day <- unique(dat[, c("DATE", "Effort")])
  expect_equal(nrow(per_day), 2)
  expect_true(all(abs(per_day$Effort - 20 * 0.01 * KM_PER_DEG) < 1e-8))
})

test_that("recorded effort uses TRKDIST, aligned to the interval it measures", {
  dat <- flag_effort(make_leg_id(straight_line(n = 5)))
  # Each fix is 0.01 degrees on from the last; TRKDIST measures back to it.
  step_m <- 0.01 * KM_PER_DEG * 1000
  dat$TRKDIST <- c(NA, rep(step_m, 4))

  out <- point_to_point_effort(dat, source = "recorded")
  expect_equal(sum(out$pt2pt.effort), 4 * 0.01 * KM_PER_DEG)
  # Attributed forward: the last record of a line closes at zero.
  expect_equal(out$pt2pt.effort[5], 0)
})

test_that("recorded and computed agree on a straight line", {
  dat <- flag_effort(make_leg_id(straight_line(n = 5)))
  dat$TRKDIST <- c(NA, rep(0.01 * KM_PER_DEG * 1000, 4))

  expect_equal(
    sum(point_to_point_effort(dat, source = "recorded")$pt2pt.effort),
    sum(point_to_point_effort(dat)$pt2pt.effort)
  )
})

test_that("a recorded reading spanning a ferry is discarded, not counted", {
  a <- straight_line(n = 3, lat0 = 43, legno = 1)
  b <- straight_line(n = 3, lat0 = 44, legno = 2)
  b$EVENTNO <- b$EVENTNO + 100
  dat <- flag_effort(make_leg_id(dplyr::bind_rows(a, b)))
  # The first record of line 2 measures back across the ferry from line 1.
  dat$TRKDIST <- c(NA, rep(0.01 * KM_PER_DEG * 1000, 2),
                   999999, rep(0.01 * KM_PER_DEG * 1000, 2))

  out <- point_to_point_effort(dat, source = "recorded")
  expect_equal(sum(out$pt2pt.effort), 4 * 0.01 * KM_PER_DEG)
})

test_that("recorded effort needs the column", {
  dat <- flag_effort(make_leg_id(straight_line(n = 3)))
  expect_error(point_to_point_effort(dat, source = "recorded"), "TRKDIST")
})

test_that("the default is unchanged", {
  dat <- flag_effort(make_leg_id(straight_line(n = 5)))
  dat$TRKDIST <- 999999
  expect_equal(sum(point_to_point_effort(dat)$pt2pt.effort),
               4 * 0.01 * KM_PER_DEG)
})

test_that("a missing TRKDIST reading is not counted as zero distance", {
  dat <- flag_effort(make_leg_id(straight_line(n = 5)))
  step_m <- 0.01 * KM_PER_DEG * 1000
  dat$TRKDIST <- c(NA, step_m, NA, step_m, step_m)   # a gap mid-line

  expect_warning(out <- point_to_point_effort(dat, source = "recorded"),
                 "no TRKDIST reading")
  # Every interval still counted: the gap falls back to the great circle.
  expect_equal(sum(out$pt2pt.effort), 4 * 0.01 * KM_PER_DEG)
})

test_that("Effort is recomputed after filling a missing reading", {
  dat <- flag_effort(make_leg_id(straight_line(n = 5)))
  step_m <- 0.01 * KM_PER_DEG * 1000
  dat$TRKDIST <- c(NA, step_m, NA, step_m, step_m)

  out <- suppressWarnings(point_to_point_effort(dat, source = "recorded"))
  expect_true(all(out$Effort == sum(out$pt2pt.effort)))
})

test_that("a complete TRKDIST is not warned about", {
  dat <- flag_effort(make_leg_id(straight_line(n = 5)))
  dat$TRKDIST <- c(NA, rep(0.01 * KM_PER_DEG * 1000, 4))
  expect_no_warning(point_to_point_effort(dat, source = "recorded"))
})
