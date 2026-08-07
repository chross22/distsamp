test_that("planned target lengths always sum to the track length", {
  set.seed(1)
  for (total in c(0.5, 3, 5, 5.0001, 7.4, 7.6, 23, 100.7)) {
    tgt <- distsamp:::plan_one_track(total, seg_length = 5, seg_tol = 2.5)
    expect_equal(sum(tgt), total, tolerance = 1e-9,
                 label = paste("total =", total))
  }
})

test_that("a short track becomes one short segment", {
  tgt <- distsamp:::plan_one_track(3, seg_length = 5, seg_tol = 2.5)
  expect_equal(tgt, 3)
})

test_that("a large remainder becomes its own segment", {
  # 23 km at 5 km: 4 whole segments, 3 km left, which clears the 2.5 tolerance.
  set.seed(1)
  tgt <- distsamp:::plan_one_track(23, seg_length = 5, seg_tol = 2.5)
  expect_length(tgt, 5)
  expect_equal(sort(tgt), c(3, 5, 5, 5, 5))
})

test_that("a small remainder is absorbed rather than left as a stub", {
  # 22 km at 5 km: 4 whole segments, 2 km left, under the 2.5 tolerance.
  set.seed(1)
  tgt <- distsamp:::plan_one_track(22, seg_length = 5, seg_tol = 2.5)
  expect_length(tgt, 4)
  expect_equal(sort(tgt), c(5, 5, 5, 7))
})

test_that("the leftover can land on any segment, including the last", {
  # floor(runif(1, 1, n)), as the original used, can never return n, so the
  # final segment could never absorb the leftover.
  positions <- vapply(1:200, function(s) {
    set.seed(s)
    tgt <- distsamp:::plan_one_track(23, seg_length = 5, seg_tol = 2.5)
    which(tgt != 5)
  }, integer(1))
  expect_true(5 %in% positions)
  expect_true(1 %in% positions)
  expect_setequal(sort(unique(positions)), 1:5)
})

test_that("segments cover the whole track and lose no effort", {
  dat <- straight_line(n = 41, step = 0.01) # 40 * 1.1112 = 44.448 km
  segs <- segment_survey(dat, seg_length = 5, seed = 1)
  expect_equal(sum(segs$segments$seg_eff), 40 * 0.01 * KM_PER_DEG,
               tolerance = 1e-9)
  expect_equal(sum(segs$segments$seg_eff), segs$tracks$track_effort)
})

test_that("the last track is not dropped", {
  # The original loop ran to nrow - 1, so the final planned segment - and with
  # it the final track of the dataset - never got cut.
  dat <- dplyr::bind_rows(
    straight_line(n = 11, lat0 = 43.0, legno = 1),
    straight_line(n = 11, lat0 = 44.0, legno = 2),
    straight_line(n = 11, lat0 = 45.0, legno = 3)
  )
  dat$EVENTNO <- seq_len(nrow(dat))
  dat$TIME <- 120000 + seq_len(nrow(dat)) * 25

  segs <- segment_survey(dat, seg_length = 5, seed = 1)
  expect_equal(nrow(segs$tracks), 3)
  expect_equal(length(unique(segs$segments$new_trackno)), 3)
  expect_equal(sum(segs$segments$seg_eff), 3 * 10 * 0.01 * KM_PER_DEG,
               tolerance = 1e-9)
})

test_that("segment lengths stay inside the tolerance band", {
  dat <- straight_line(n = 201, step = 0.005) # 111.12 km
  # Segments are cut at record boundaries, so allow one record of slop either
  # side of the [0.5s, 1.5s] band.
  slop <- 0.005 * KM_PER_DEG
  for (s in 1:15) {
    eff <- segment_survey(dat, seg_length = 5, seed = s)$segments$seg_eff
    expect_true(all(eff >= 2.5 - slop), label = paste("seed", s, "lower"))
    expect_true(all(eff <= 7.5 + slop), label = paste("seed", s, "upper"))
  }
})

test_that("cutting error does not accumulate down a track", {
  # Cut points are measured from the start of the track, so per-segment
  # rounding cancels instead of piling up on the final segment. Without that,
  # a long track with many small records leaves the last segment far over the
  # tolerance band.
  dat <- straight_line(n = 401, step = 0.0025) # 111.12 km in 0.28 km records
  for (s in 1:10) {
    segs <- segment_survey(dat, seg_length = 5, seed = s)
    last <- segs$segments$seg_eff[nrow(segs$segments)]
    expect_lt(last, 7.5)
  }
})

test_that("segmentation is reproducible under a seed", {
  dat <- straight_line(n = 61, step = 0.01)
  a <- segment_survey(dat, seg_length = 4, seed = 42)
  b <- segment_survey(dat, seg_length = 4, seed = 42)
  expect_equal(a$segments, b$segments)

  c <- segment_survey(dat, seg_length = 4, seed = 43)
  # Different seeds should not, in general, give the same cuts.
  expect_false(isTRUE(all.equal(a$segments$seg_eff, c$segments$seg_eff)))
})

test_that("segmenting does not disturb the caller's RNG stream", {
  dat <- straight_line(n = 41)
  set.seed(99)
  before <- runif(3)
  set.seed(99)
  invisible(segment_survey(dat, seg_length = 5, seed = 1))
  after <- runif(3)
  expect_equal(before, after)
})

test_that("both over- and under-shooting cuts occur", {
  dat <- straight_line(n = 201, step = 0.005)
  effs <- unlist(lapply(1:20, function(s) {
    segment_survey(dat, seg_length = 5, seed = s)$segments$seg_eff
  }))
  expect_true(any(effs > 5))
  expect_true(any(effs < 5))
})

test_that("short tracks and short segments are dropped", {
  dat <- dplyr::bind_rows(
    straight_line(n = 21, lat0 = 43.0, legno = 1), # 22.2 km
    # 0.56 km, under min_track_km
    straight_line(n = 2, step = 0.005, lat0 = 44.0, legno = 2)
  )
  dat$EVENTNO <- seq_len(nrow(dat))
  dat$TIME <- 120000 + seq_len(nrow(dat)) * 25
  segs <- segment_survey(dat, seg_length = 5, seed = 1)
  expect_equal(nrow(segs$tracks), 1)
})

test_that("empty and single-record inputs do not error", {
  empty <- straight_line(n = 5)[0, ]
  expect_silent(segs <- segment_survey(empty, seg_length = 5, seed = 1))
  expect_equal(nrow(segs$segments), 0)

  one <- straight_line(n = 2)[1, ]
  segs <- segment_survey(one, seg_length = 5, seed = 1)
  expect_equal(nrow(segs$segments), 0)
})

test_that("seg_length must be a single positive number", {
  dat <- straight_line(n = 11)
  expect_error(segment_survey(dat, seg_length = -1))
  expect_error(segment_survey(dat, seg_length = c(1, 2)))
})
