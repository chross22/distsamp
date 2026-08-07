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
