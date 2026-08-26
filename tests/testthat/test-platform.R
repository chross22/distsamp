test_that("\"ship\" and \"vessel\" are one platform, not two", {
  expect_identical(platform_defaults("ship"), platform_defaults("vessel"))
  expect_identical(platform_defaults("vessel")$platform, "vessel")
  # The name it resolves to is the PLATFORM_KIND level the filter compares
  # against, so nothing is translated on the way through.
  expect_identical(platform_defaults("ship")$kind, "vessel")
})

test_that("the platform decides effort criteria and distance sources together", {
  air <- platform_defaults("aerial")
  sea <- platform_defaults("vessel")

  expect_identical(air$effort_args, list())
  expect_identical(air$distance_sources, c("angle", "exact", "strip"))

  # NULL, not Inf: a missing ALT fails any ceiling.
  expect_true("max_alt_m" %in% names(sea$effort_args))
  expect_null(sea$effort_args$max_alt_m)
  expect_identical(sea$distance_sources, "exact")
})

test_that("an unknown platform is named rather than silently defaulted", {
  expect_error(platform_defaults("boat"), "boat")
  expect_error(platform_defaults("boat"), "aerial")
  expect_error(prepare_survey(straight_line(), platform = "submarine"),
               "submarine")
})


# --- prepare_survey() -------------------------------------------------------

test_that("a vessel line survives effort, where the aerial criteria erase it", {
  # The regression this whole option exists for. A vessel carries no ALT, a
  # missing value fails a criterion, so under the aerial ceiling every one of
  # these records is off effort - reported as though the ship had flown too
  # high.
  sea <- vessel_line(n = 21)

  air_rules <- suppressMessages(prepare_survey(sea, platform = "all"))
  expect_equal(sum(air_rules$OnOff.Effort), 0)

  out <- suppressMessages(prepare_survey(sea, platform = "vessel"))
  expect_equal(nrow(out), 21)
  expect_true(all(out$PLATFORM_KIND == "vessel"))
  expect_equal(sum(out$OnOff.Effort), 21)
})

test_that("the platform filter keeps its own kind and drops the other", {
  mixed <- mixed_platforms(n = 21)

  air <- suppressMessages(prepare_survey(mixed, platform = "aerial"))
  sea <- suppressMessages(prepare_survey(mixed, platform = "vessel"))

  expect_true(all(air$PLATFORM_KIND == "aerial"))
  expect_true(all(sea$PLATFORM_KIND == "vessel"))
  expect_equal(nrow(air) + nrow(sea), nrow(mixed))
})

test_that("\"all\" classifies without filtering and keeps the aerial criteria", {
  # Nothing has been filtered, so no platform's criteria are the right ones.
  # Changing them is what the filter licenses.
  mixed <- mixed_platforms(n = 21)
  out <- suppressMessages(prepare_survey(mixed, platform = "all"))
  expect_equal(nrow(out), nrow(mixed))
  expect_setequal(as.character(unique(out$PLATFORM_KIND)),
                  c("aerial", "vessel"))
  expect_equal(sum(out$OnOff.Effort), 21) # the aerial half only
})

test_that("effort_args wins over the platform's defaults", {
  sea <- vessel_line(n = 21, beaufort = 4)
  expect_equal(
    sum(suppressMessages(prepare_survey(sea, platform = "vessel"))$OnOff.Effort),
    0
  )
  expect_equal(
    sum(suppressMessages(prepare_survey(
      sea, platform = "vessel", effort_args = list(max_beaufort = 4)
    ))$OnOff.Effort),
    21
  )

  # And an explicit max_alt_m puts the ceiling back, rather than being
  # overwritten by the platform default.
  sea$ALT <- 500
  expect_equal(
    sum(suppressMessages(prepare_survey(
      sea, platform = "vessel", effort_args = list(max_alt_m = 366)
    ))$OnOff.Effort),
    0
  )
})

test_that("prepare_aerial() is prepare_survey() under its old name", {
  dat <- straight_line(n = 21)
  expect_equal(
    suppressMessages(prepare_aerial(dat)),
    suppressMessages(prepare_survey(dat))
  )
  # It kept its platform argument, so code passing "all" still works.
  expect_equal(
    nrow(suppressMessages(prepare_aerial(dat, platform = "all"))),
    21
  )
})


# --- sighting_distances() ---------------------------------------------------

vessel_sightings <- function(n = 11) {
  dat <- vessel_line(n = n)
  dat$OnOff.Effort <- 1L
  dat$SPECCODE <- NA_character_
  dat$SPECCODE[c(4, 8)] <- "RIWH"
  dat$NUMBER <- NA_real_
  dat$NUMBER[c(4, 8)] <- 1
  # 0.5 km to the right of a due-north track, and an angle that would give a
  # different answer if anything read it.
  off <- gc_destination(dat$LATITUDE[c(4, 8)], dat$LONGITUDE[c(4, 8)],
                        bearing = 90, distance_km = 0.5)
  dat$S_LAT <- NA_real_
  dat$S_LONG <- NA_real_
  dat$S_LAT[c(4, 8)] <- off$lat
  dat$S_LONG[c(4, 8)] <- off$lon
  # Both angle columns, as an extract carries them: `diagnose_pipeline()`
  # counts the pair and a half-present pair is not one.
  dat$ANGLEL <- NA_real_
  dat$ANGLER <- NA_real_
  dat$ANGLER[c(4, 8)] <- 45
  dat$STRIP <- NA_real_
  dat
}

test_that("a vessel's distances come from the position, not the angle", {
  dat <- vessel_sightings()
  out <- sighting_distances(dat, platform = "vessel", units = "km")

  got <- out[!is.na(out$distance_source), ]
  expect_equal(nrow(got), 2)
  expect_true(all(got$distance_source == "exact"))
  expect_equal(got$distance, c(0.5, 0.5), tolerance = 1e-3)
  expect_true(all(got$side == "right"))
})

test_that("an aircraft source asked for on a vessel errors, not NAs", {
  dat <- vessel_sightings()
  expect_error(
    sighting_distances(dat, sources = c("angle", "exact"), platform = "ship"),
    "no altitude"
  )
  expect_error(
    sighting_distances(dat, sources = "strip", platform = "vessel"),
    "8.A.31"
  )
  # And "circling" is a break-off from the census line, which either platform
  # can do.
  expect_silent(
    sighting_distances(dat, sources = c("exact", "circling"),
                       platform = "vessel")
  )
})

test_that("the aerial default order is unchanged", {
  dat <- vessel_sightings()
  out <- sighting_distances(dat, units = "km")
  got <- out[!is.na(out$distance_source), ]
  # ALT is NA on this fixture, so "angle" yields nothing and "exact" fills in -
  # but the order that was tried is still the aircraft one.
  expect_true(all(got$distance_source == "exact"))
  expect_equal(
    formals(sighting_distances)$platform,
    quote(c("aerial", "vessel", "ship"))
  )
})


# --- segment_survey() -------------------------------------------------------

test_that("a vessel survey segments, and records that it was one", {
  dat <- vessel_sightings()
  dat$OnOff.Effort <- NULL
  segs <- suppressWarnings(
    segment_survey(dat, seg_length = 2, platform = "ship", seed = 1)
  )

  expect_identical(segs$settings$platform, "vessel")
  expect_identical(segs$settings$distance_sources, "exact")
  expect_gt(nrow(segs$segments), 0)
  expect_gt(sum(segs$segments$seg_eff), 0)
  expect_true(all(segs$detections$distance_source == "exact"))
})

test_that("segmentation itself does not depend on the platform", {
  # Great-circle distance between fixes, splitting at breaks in effort and
  # cutting a track into lengths are geometry. A ship's track and a plane's
  # over the same positions must segment identically.
  air <- straight_line(n = 21)
  sea <- vessel_line(n = 21)
  sea$ALT <- 229 # so the aerial criteria keep it, isolating the geometry

  a <- suppressWarnings(segment_survey(air, seg_length = 5, seed = 1))
  s <- suppressWarnings(
    segment_survey(sea, seg_length = 5, platform = "vessel", seed = 1)
  )
  expect_equal(a$segments$seg_eff, s$segments$seg_eff)
  expect_equal(a$segments$mid_lat, s$segments$mid_lat)
})

test_that("the platform gate warns about the other kind, in both directions", {
  expect_warning(
    segment_survey(vessel_line(n = 21), seg_length = 5, seed = 1),
    "not moving at aerial survey speed"
  )
  expect_warning(
    segment_survey(straight_line(n = 21), seg_length = 5, platform = "vessel",
                   seed = 1),
    "not moving at vessel survey speed"
  )
  expect_silent(
    segment_survey(vessel_line(n = 21), seg_length = 5, platform = "vessel",
                   seed = 1)
  )
})

test_that("a vessel run cannot be given an aircraft's distance sources", {
  expect_error(
    segment_survey(vessel_line(n = 21), seg_length = 5, platform = "vessel",
                   distance_sources = c("angle", "exact"), seed = 1),
    "no altitude"
  )
})


# --- diagnose_pipeline() ----------------------------------------------------

test_that("the diagnosis is run against the platform it was told", {
  # Long enough that the speed check has the 20 usable intervals it needs.
  sea <- vessel_sightings(n = 30)
  out <- capture.output(suppressWarnings(suppressMessages(
    diagnose_pipeline(sea, seg_length = 2, platform = "ship")
  )))
  txt <- paste(out, collapse = "\n")

  expect_match(txt, "as a vessel survey")
  expect_match(txt, "not a criterion for a vessel")
  # It must not report the altitude ceiling as the thing that excluded these
  # records, because it was never applied to them.
  expect_false(grepl("ALT missing", txt))
  # And it must say the speed disagrees when it does. Given an altitude, so
  # the run reaches the speed check rather than stopping at 0 records on
  # effort - which is the other half of the same finding.
  sea$ALT <- 229
  air <- capture.output(suppressWarnings(suppressMessages(
    diagnose_pipeline(sea, seg_length = 2, platform = "aerial")
  )))
  expect_match(paste(air, collapse = "\n"), "not a survey aircraft")
})
