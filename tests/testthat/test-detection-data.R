segs_fx <- function(...) {
  segment_survey(example_data(), seg_length = 5, seed = 1, ...)
}
flat <- function(...) suppressMessages(detection_data(...))

test_that("sources are tried in precedence order and recorded", {
  dat <- flag_effort(make_leg_id(example_data()))

  out <- sighting_distances(dat)
  expect_true(all(c("distance", "distbegin", "distend", "side",
                    "distance_source") %in% names(out)))

  # The fixture records an angle on every eligible sighting, so angles win.
  expect_setequal(stats::na.omit(out$distance_source), rep("angle", 8))

  # Reversing the order hands the three exact positions to `exact`.
  rev <- sighting_distances(dat, sources = c("exact", "angle", "strip"))
  expect_equal(sum(rev$distance_source == "exact", na.rm = TRUE), 3)
  expect_equal(sum(rev$distance_source == "angle", na.rm = TRUE), 5)
})

test_that("angle and exact agree where both exist", {
  # They are independent measurements of the same quantity, so the precedence
  # order must not change the numbers, only their provenance.
  dat <- flag_effort(make_leg_id(example_data()))
  a <- sighting_distances(dat)
  e <- sighting_distances(dat, sources = c("exact", "angle", "strip"))

  both <- which(e$distance_source == "exact")
  expect_length(both, 3)
  expect_equal(a$distance[both], e$distance[both])
})

test_that("STRIP fills in where no angle or position exists", {
  dat <- flag_effort(make_leg_id(example_data()))
  dat$ANGLEL <- NULL
  dat$ANGLER <- NULL
  dat$S_LAT <- NULL
  dat$S_LONG <- NULL

  out <- sighting_distances(dat, units = "nmi")
  got <- which(out$distance_source == "strip")
  expect_gt(length(got), 0)

  # An interval, not a point.
  expect_true(all(is.na(out$distance[got])))
  expect_true(all(!is.na(out$distbegin[got])))
  expect_true(all(out$distend[got] > out$distbegin[got]))

  # The fixture is 2024, so the NLPSC book applies: code 3 is 1/8 to 1/4 nmi.
  code3 <- got[out$distbegin[got] == 1 / 8]
  expect_gt(length(code3), 0)
  expect_true(all(dat$STRIP[code3] == 3))
})

test_that("the two STRIP code books give different answers for one code", {
  dat <- flag_effort(make_leg_id(example_data()))
  dat$ANGLEL <- NULL
  dat$ANGLER <- NULL

  nlpsc <- sighting_distances(dat, units = "nmi", strip_scheme = "nlpsc")
  cetap <- sighting_distances(dat, units = "nmi", strip_scheme = "cetap")
  i <- which(!is.na(dat$STRIP) & dat$STRIP == 5 & nlpsc$distance_source == "strip")
  expect_gt(length(i), 0)
  expect_equal(unique(nlpsc$distbegin[i]), 1 / 4)
  expect_equal(unique(cetap$distbegin[i]), 1 / 8)
})

test_that("circling is opt-in", {
  dat <- flag_effort(flag_circling(make_leg_id(example_data())))
  expect_false("circling" %in% sighting_distances(dat)$distance_source)

  with_c <- sighting_distances(dat, sources = c("angle", "exact", "strip",
                                                "circling"))
  expect_equal(sum(with_c$distance_source == "circling", na.rm = TRUE), 1)
})

test_that("an unknown source is refused", {
  expect_error(sighting_distances(example_data(), sources = "psychic"),
               "circling")
})

test_that("the flatfile keeps every segment, including empty ones", {
  segs <- segs_fx()
  out <- flat(segs, area = 5811)

  expect_setequal(unique(out$Sample.Label), segs$segments$seg_id)
  expect_gt(sum(is.na(out$distance)), 0)

  # Effort is per segment and must not be duplicated away or lost.
  eff <- unique(out[, c("Sample.Label", "Effort")])
  expect_equal(sum(eff$Effort), sum(segs$segments$seg_eff))
})

test_that("the flatfile has the columns Distance expects", {
  out <- flat(segs_fx(), area = 5811)
  expect_true(all(c("Region.Label", "Area", "Sample.Label", "Effort",
                    "object", "distance", "size") %in% names(out)))
  expect_equal(unique(out$Area), 5811)
  expect_equal(unique(out$Region.Label), "all")
  expect_equal(attr(out, "distance_units"), "m")
})

test_that("area is required, because it scales abundance directly", {
  expect_error(detection_data(segs_fx()), "`area` is required")
  expect_error(detection_data(segs_fx(), area = "big"), "must be numeric")
  expect_error(detection_data(list(), area = 1), "distsamp_segments")
})

test_that("truncation drops detections but never their effort", {
  segs <- segs_fx()
  full <- flat(segs, area = 5811)
  cut <- flat(segs, area = 5811, truncation = 500)

  expect_lt(sum(!is.na(cut$object)), sum(!is.na(full$object)))
  expect_true(all(stats::na.omit(cut$distance) <= 500))

  # Same segments, same total effort: the denominator is untouched.
  expect_setequal(unique(cut$Sample.Label), unique(full$Sample.Label))
  expect_equal(
    sum(unique(cut[, c("Sample.Label", "Effort")])$Effort),
    sum(unique(full[, c("Sample.Label", "Effort")])$Effort)
  )
})

test_that("a segment whose only detection is truncated survives as empty", {
  segs <- segs_fx()
  # Truncate below everything: every segment should remain, none with a distance.
  cut <- flat(segs, area = 5811, truncation = 1)
  expect_setequal(unique(cut$Sample.Label), segs$segments$seg_id)
  expect_true(all(is.na(cut$distance)))
})

test_that("circling detections are excluded by default and can be kept", {
  segs <- segs_fx()
  without <- flat(segs, area = 5811)
  with_c <- flat(segs, area = 5811, include_circling = TRUE)
  expect_gte(sum(!is.na(with_c$object)), sum(!is.na(without$object)))

  # Excluding them here must not touch the abundance side.
  expect_gt(sum(segs$sightings$n_animals), 0)
})

test_that("what was dropped is reported, not silent", {
  msg <- tryCatch(detection_data(segs_fx(), area = 5811, truncation = 500),
                  message = conditionMessage)
  expect_match(msg, "circling detection")
  expect_match(msg, "beyond the truncation distance")
  expect_match(msg, "g\\(0\\) = 1 is assumed")
})

test_that("point and interval distances are refused in one table", {
  dat <- example_data()
  # Leave an angle on one sighting only, so the rest fall through to STRIP.
  keep <- which(!is.na(dat$ANGLER))[1]
  dat$ANGLEL <- NA_real_
  ang <- dat$ANGLER
  dat$ANGLER <- NA_real_
  dat$ANGLER[keep] <- ang[keep]

  segs <- segment_survey(dat, seg_length = 5, seed = 1,
                         distance_sources = c("angle", "strip"))
  expect_error(detection_data(segs, area = 5811), "cannot fit both")
  expect_warning(
    suppressMessages(detection_data(segs, area = 5811, mixed = "warn")),
    "cannot fit both"
  )
})

test_that("an open top STRIP bin is dropped as unfittable", {
  dat <- example_data()
  dat$ANGLEL <- NULL
  dat$ANGLER <- NULL
  dat$S_LAT <- NULL
  dat$S_LONG <- NULL
  # Code 13 is the open top bin under the NLPSC book: 4 nmi to infinity.
  dat$STRIP[!is.na(dat$STRIP)][1] <- 13

  segs <- segment_survey(dat, seg_length = 5, seed = 1)
  msg <- tryCatch(detection_data(segs, area = 5811), message = conditionMessage)
  expect_match(msg, "open top STRIP bin")

  out <- flat(segs, area = 5811)
  expect_true(all(is.finite(stats::na.omit(out$distend))))
})

test_that("region comes from an argument or STRATUM", {
  segs <- segs_fx()
  named <- flat(segs, area = 5811, region = "GOM")
  expect_equal(unique(named$Region.Label), "GOM")
})

test_that("covariates are carried onto every row", {
  out <- flat(segs_fx(), area = 5811, covariates = "wt_beaufort")
  expect_true("wt_beaufort" %in% names(out))
  expect_false(any(is.na(out$wt_beaufort)))
  expect_error(flat(segs_fx(), area = 5811, covariates = "nope"), "nope")
})

test_that("distance_source travels through to the flatfile", {
  out <- flat(segs_fx(), area = 5811)
  expect_true("distance_source" %in% names(out))
  expect_setequal(stats::na.omit(unique(out$distance_source)), "angle")
})
