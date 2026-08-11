test_that("bearings point where they should", {
  expect_equal(gc_bearing(43, -69, 44, -69), 0)
  expect_equal(gc_bearing(44, -69, 43, -69), 180)

  # A great circle between two points at the same latitude bulges towards the
  # pole, so it leaves slightly north of due east - the bearing is initial,
  # not constant. Construct a genuinely due-east departure to check the value.
  expect_equal(gc_bearing(43, -69, 43, -68), 89.6588, tolerance = 1e-4)
  east <- gc_destination(43, -69, bearing = 90, distance_km = 80)
  expect_equal(gc_bearing(43, -69, east$lat, east$lon), 90)

  # Always in [0, 360)
  b <- gc_bearing(43, -69, c(43.01, 42.99, 43, 43), c(-69, -69, -68.9, -69.1))
  expect_true(all(b >= 0 & b < 360))
})

test_that("a position has no bearing to itself", {
  # atan2(0, 0) is 0, so the naive answer would be a confident 'due north'.
  expect_true(is.na(gc_bearing(43, -69, 43, -69)))
  expect_true(is.na(gc_bearing(43, NA, 44, -69)))
})

test_that("gc_destination inverts distance and bearing", {
  p <- gc_destination(43, -69, bearing = 37, distance_km = 12)
  expect_equal(gc_distance(43, -69, p$lat, p$lon), 12)
  expect_equal(gc_bearing(43, -69, p$lat, p$lon), 37)
})

test_that("cross-track distance is the perpendicular one", {
  # Leaving a meridian due east departs it at a right angle, so the whole
  # distance travelled is cross-track and none of it is along-track.
  p <- gc_destination(43, -69, bearing = 90, distance_km = 0.5)
  out <- cross_track_distance(43, -69, bearing = 0, p$lat, p$lon, units = "km")
  expect_equal(out$distance, 0.5)
  expect_equal(out$along, 0)
  expect_equal(out$side, "right")

  # The mirror image is the same distance to the left.
  q <- gc_destination(43, -69, bearing = 270, distance_km = 0.5)
  left <- cross_track_distance(43, -69, bearing = 0, q$lat, q$lon, units = "km")
  expect_equal(left$distance, 0.5)
  expect_equal(left$side, "left")
})

test_that("an along-track offset does not inflate the distance", {
  # A whale 0.2 km off the track, logged 1 km before the aircraft drew level.
  abeam <- gc_destination(43, -69, bearing = 0, distance_km = 1)
  whale <- gc_destination(abeam$lat, abeam$lon, bearing = 90, distance_km = 0.2)

  out <- cross_track_distance(43, -69, bearing = 0, whale$lat, whale$lon,
                              units = "km")
  expect_equal(out$distance, 0.2)
  expect_equal(out$along, 1)

  # The radial distance the original scripts used is much larger, and wrong.
  radial <- gc_distance(43, -69, whale$lat, whale$lon)
  expect_equal(radial, sqrt(1^2 + 0.2^2), tolerance = 1e-4)
  expect_gt(radial, 5 * out$distance)
})

test_that("a sighting behind the aircraft has a negative along-track offset", {
  behind <- gc_destination(43, -69, bearing = 180, distance_km = 1)
  whale <- gc_destination(behind$lat, behind$lon, bearing = 90, distance_km = 0.2)
  out <- cross_track_distance(43, -69, bearing = 0, whale$lat, whale$lon,
                              units = "km")
  expect_equal(out$distance, 0.2)
  expect_equal(out$along, -1)
})

test_that("a sighting at the event position is on the track", {
  out <- cross_track_distance(43, -69, bearing = 0, 43, -69)
  expect_equal(out$distance, 0)
  expect_equal(out$along, 0)
  expect_equal(out$side, "on-track")
})

test_that("cross_track_distance propagates missingness and converts units", {
  out <- cross_track_distance(43, -69, bearing = c(0, NA), 43.01, c(-68.99, -68.99))
  expect_true(is.na(out$distance[2]))
  expect_true(is.na(out$side[2]))

  no_target <- cross_track_distance(43, -69, 0, NA, -68.99)
  expect_true(is.na(no_target$distance))

  km <- cross_track_distance(43, -69, 0, 43, -68.99, units = "km")
  m <- cross_track_distance(43, -69, 0, 43, -68.99, units = "m")
  nmi <- cross_track_distance(43, -69, 0, 43, -68.99, units = "nmi")
  expect_equal(km$distance * 1000, m$distance)
  expect_equal(km$distance / 1.852, nmi$distance)
})

test_that("track bearings follow the survey lines", {
  dat <- flag_effort(make_leg_id(example_data()))
  b <- track_bearing(dat)

  # Every line in the fixture runs due north.
  expect_equal(unique(stats::na.omit(b)), 0)

  # Census records get a bearing; circling and transits do not.
  census <- !is.na(dat$LEGTYPE) & dat$LEGTYPE == 2
  expect_true(all(!is.na(b[census])))
  expect_true(all(is.na(b[!census])))
})

test_that("a sighting logged at the position before it gets that line's bearing", {
  # Sighting records repeat the preceding position, so a naive consecutive
  # difference would be a bearing between two identical points.
  dat <- flag_effort(make_leg_id(example_data()))
  sight <- !is.na(dat$SPECCODE) & !is.na(dat$LEGTYPE) & dat$LEGTYPE == 2
  expect_gt(sum(sight), 0)
  expect_true(all(track_bearing(dat)[sight] == 0))
})

test_that("bearings do not leak across line occupations", {
  # Two lines an hour apart on the same day, the second running due south.
  north <- straight_line(n = 5, legno = 1)
  south <- straight_line(n = 5, legno = 2)
  south$LATITUDE <- rev(south$LATITUDE)
  south$EVENTNO <- south$EVENTNO + 100
  dat <- make_leg_id(dplyr::bind_rows(north, south))

  b <- track_bearing(dat)
  expect_equal(unique(b[dat$LEGNO == 1]), 0)
  expect_equal(unique(b[dat$LEGNO == 2]), 180)
})

test_that("a line with a single distinct position has no bearing", {
  dat <- straight_line(n = 3, step = 0)
  expect_true(all(is.na(track_bearing(make_leg_id(dat)))))
})

test_that("exact positions reproduce the distances their angles imply", {
  dat <- flag_effort(make_leg_id(example_data()))
  d <- exact_distance(dat)
  has <- which(!is.na(d$distance))
  expect_length(has, 3)

  # Each fixture position was placed at the distance its declination angle
  # gives, so the two independent sources must agree.
  angle <- ifelse(is.na(dat$ANGLEL[has]), dat$ANGLER[has], dat$ANGLEL[has])
  expect_equal(d$distance[has], perp_distance(angle, dat$ALT[has]))

  # And on the side the angle column says.
  expect_equal(d$side[has], ifelse(is.na(dat$ANGLEL[has]), "right", "left"))
})

test_that("the sighting logged before it came abeam keeps its true distance", {
  dat <- flag_effort(make_leg_id(example_data()))
  d <- exact_distance(dat)

  offset <- which(!is.na(d$along) & abs(d$along) > 1)
  expect_length(offset, 1)
  expect_equal(d$along[offset], 300)

  # The radial distance the original scripts computed is far larger.
  radial <- gc_distance(dat$LATITUDE[offset], dat$LONGITUDE[offset],
                        dat$S_LAT[offset], dat$S_LONG[offset]) * 1000
  expect_equal(radial, sqrt(300^2 + d$distance[offset]^2), tolerance = 1e-6)
  expect_gt(radial, 2 * d$distance[offset])
})

test_that("a circling sighting gets no perpendicular distance", {
  dat <- flag_effort(make_leg_id(example_data()))
  circling <- which(!is.na(dat$S_LAT) & dat$LEGTYPE == 4)
  expect_length(circling, 1)

  # It has an exact position, so the geometry would happily return a number.
  expect_true(is.na(exact_distance(dat)$distance[circling]))

  # Off effort there is no track-line, so it stays NA even when the on-effort
  # restriction is lifted: the bearing itself is undefined.
  loose <- exact_distance(dat, on_effort_only = FALSE)
  expect_true(is.na(loose$distance[circling]))
})

test_that("exact_distance converts units", {
  dat <- flag_effort(make_leg_id(example_data()))
  m <- exact_distance(dat)
  km <- exact_distance(dat, units = "km")
  expect_equal(m$distance / 1000, km$distance)
  expect_equal(m$along / 1000, km$along)
})

test_that("data without exact positions still gets the columns", {
  dat <- flag_effort(make_leg_id(example_data()))
  dat$S_LAT <- NULL
  dat$S_LONG <- NULL

  d <- exact_distance(dat)
  expect_named(d, c("distance", "along", "side", "bearing"))
  expect_equal(nrow(d), nrow(dat))
  expect_true(all(is.na(d$distance)))
  # The bearings are still there; only the sighting positions were missing.
  expect_true(any(!is.na(d$bearing)))
})

test_that("empty input gives empty output of the right shape", {
  empty <- example_data()[0, ]
  expect_equal(nrow(exact_distance(empty)), 0)
  expect_named(exact_distance(empty), c("distance", "along", "side", "bearing"))
  expect_length(track_bearing(empty), 0)
})

test_that("the grouping columns are chosen most-specific-first", {
  dat <- flag_effort(make_leg_id(example_data()))
  expect_equal(default_track_grouping(dat), c("DATE", "FILEID", "LEGNO3"))

  dat$LEGNO3 <- NULL
  expect_equal(default_track_grouping(dat), c("DATE", "FILEID", "LEGNO"))

  dat$LEGNO <- NULL
  expect_equal(default_track_grouping(dat), c("DATE", "FILEID"))

  dat$FILEID <- NULL
  expect_error(default_track_grouping(dat), "make_leg_id")
})

test_that("DATE is prepended only when it is there to prepend", {
  dat <- flag_effort(make_leg_id(example_data()))
  dat$DATE <- NULL
  expect_equal(default_track_grouping(dat), c("FILEID", "LEGNO3"))
})

test_that("two days sharing a LEGNO get their own bearings", {
  # A constant FILEID leaves DATE as the only thing separating the days.
  day1 <- straight_line(n = 21, lat0 = 43, legno = 5, date = "2024-04-01")
  day2 <- straight_line(n = 21, lat0 = 40, legno = 5, date = "2024-04-02")
  day2$EVENTNO <- day2$EVENTNO + 100
  day2$LATITUDE <- 40                                  # day 2 runs due east
  day2$LONGITUDE <- -69 + (seq_len(21) - 1) * 0.01
  both <- make_leg_id(dplyr::bind_rows(day1, day2))
  both$FILEID <- "F"
  # Forced into a single occupation spanning both days: `make_leg_id()` no
  # longer produces that, but a caller-supplied LEGNO3 can still be in it, and
  # this is the case where getting `by` wrong joins two lines.
  both$LEGNO3 <- "5_1"

  b <- track_bearing(both)
  expect_false(anyNA(b))
  expect_true(all(abs(b[1:21] - 0) < 1))               # day 1 due north
  expect_true(all(abs(b[22:42] - 90) < 1))             # day 2 due east

  # Without DATE the two days are one line, and the junction bearing —
  # pointing down the ferry — belongs to neither.
  merged <- track_bearing(both, by = c("FILEID", "LEGNO3"))
  expect_false(isTRUE(all.equal(merged, b)))
  expect_gt(abs(merged[21] - b[21]), 90)
})

test_that("an implausible exact position is flagged by validation", {
  dat <- example_data()
  i <- which(!is.na(dat$S_LAT))[1]
  # A lost minus sign puts the animal in the eastern hemisphere.
  dat$S_LONG[i] <- -dat$S_LONG[i]
  expect_true("exact_position_far_from_event" %in% validate_narwc(dat)$check)

  expect_false("exact_position_far_from_event" %in%
                 validate_narwc(example_data())$check)
})


test_that("a circling sighting is measured from the break-off point", {
  dat <- flag_circling(make_leg_id(example_data()))
  d <- circling_distance(dat)

  got <- which(!is.na(d$distance))
  expect_length(got, 1)

  # The fixture places the animal 250 m to the right of line 2 and 400 m back
  # down it from the break-off, which is the geometry to recover.
  expect_equal(d$distance[got], 250)
  expect_equal(d$along[got], -400)
  expect_equal(d$side[got], "right")

  # The aircraft flew past before turning, so the straight-line distance from
  # the break-off point is larger, by exactly the along-track margin.
  expect_equal(d$radial[got], sqrt(250^2 + 400^2))
  expect_gt(d$radial[got], d$distance[got])
})

test_that("the anchor is the break-off record itself", {
  dat <- flag_circling(make_leg_id(example_data()))
  d <- circling_distance(dat)
  got <- which(!is.na(d$distance))

  anchor <- dat[dat$EVENTNO == d$anchor_event[got] &
                  dat$DATE == dat$DATE[got], ]
  expect_equal(anchor$LEGSTAGE, 3)   # break off line to circle
  expect_equal(anchor$LEGTYPE, 2)    # still on the census line
  expect_equal(anchor$CIRCLE, 0L)
})

test_that("the anchor bearing is the inbound heading, not a centred difference", {
  # Build a line that turns hard at the break-off: if the resume position were
  # allowed to influence the bearing, it would swing away from the true heading.
  dat <- straight_line(n = 6, legno = 1)
  dat$LEGSTAGE[5] <- 3                 # break off to circle
  dat <- rbind(dat, dat[6, ], dat[6, ])
  dat$LEGTYPE[6:8] <- c(4, 4, 2)
  dat$LEGSTAGE[6:8] <- c(NA, NA, 4)
  dat$EVENTNO <- seq_len(nrow(dat))
  dat$SPECCODE[7] <- "RIWH"
  # The resume position is well to the east of the line.
  dat$LONGITUDE[8] <- -68.9
  dat$LATITUDE[8] <- dat$LATITUDE[5]

  whale <- gc_destination(dat$LATITUDE[5], dat$LONGITUDE[5], 90, 0.3)
  dat$S_LAT <- NA_real_
  dat$S_LONG <- NA_real_
  dat$S_LAT[7] <- whale$lat
  dat$S_LONG[7] <- whale$lon

  d <- circling_distance(flag_circling(make_leg_id(dat)))
  # Due north, taken from the track behind the break-off.
  expect_equal(d$bearing[7], 0)
  expect_equal(d$distance[7], 300)
})

test_that("circling distances need an exact position by default", {
  dat <- flag_circling(make_leg_id(example_data()))
  stripped <- dat
  stripped$S_LAT <- NA_real_
  stripped$S_LONG <- NA_real_

  # The aircraft position is not the animal's, so nothing is returned...
  expect_true(all(is.na(circling_distance(stripped)$distance)))

  # ...unless the fallback is asked for explicitly.
  loose <- circling_distance(stripped, position = "logged")
  got <- which(!is.na(loose$distance))
  expect_length(got, 1)
  expect_equal(loose$position_source[got], "logged")
})

test_that("position_source records which position was used", {
  dat <- flag_circling(make_leg_id(example_data()))
  d <- circling_distance(dat, position = "logged")
  got <- which(!is.na(d$distance))
  # The fixture's circling sighting has an exact position, so the fallback
  # must not displace it.
  expect_equal(d$position_source[got], "exact")
})

test_that("only circling sightings get a circling distance", {
  dat <- flag_circling(make_leg_id(example_data()))
  d <- circling_distance(dat)

  circling_sighting <- !is.na(dat$CIRCLE) & dat$CIRCLE == 1 & !is.na(dat$SPECCODE)
  expect_true(all(is.na(d$distance[!circling_sighting])))

  # Positions logged during the circle that are not sightings get nothing.
  plain <- !is.na(dat$CIRCLE) & dat$CIRCLE == 1 & is.na(dat$SPECCODE)
  expect_gt(sum(plain), 0)
  expect_true(all(is.na(d$distance[plain])))
})

test_that("a circle with no census record before it gets no anchor", {
  dat <- straight_line(n = 4, legno = 1)
  dat$LEGTYPE <- 4          # circling from the very first record
  dat$LEGSTAGE <- NA
  dat$SPECCODE[2] <- "RIWH"
  dat$S_LAT <- 43.02
  dat$S_LONG <- -68.99

  d <- circling_distance(flag_circling(make_leg_id(dat)))
  expect_true(all(is.na(d$distance)))
  expect_true(all(is.na(d$anchor_event)))
})

test_that("circling distances convert units and handle empty input", {
  dat <- flag_circling(make_leg_id(example_data()))
  m <- circling_distance(dat)
  km <- circling_distance(dat, units = "km")
  expect_equal(m$distance / 1000, km$distance)
  expect_equal(m$radial / 1000, km$radial)
  expect_equal(m$along / 1000, km$along)

  expect_equal(nrow(circling_distance(example_data()[0, ])), 0)
})

test_that("circling sightings already reach the segment counts", {
  # The spatial-model side of this: they contribute to abundance per segment,
  # controlled by `circling`, independently of whether they carry a distance.
  with_circ <- segment_survey(example_data(), seg_length = 5, seed = 1,
                              circling = "same_species")
  without <- segment_survey(example_data(), seg_length = 5, seed = 1,
                            circling = "none")
  expect_gt(sum(with_circ$sightings$n_animals),
            sum(without$sightings$n_animals))
})
