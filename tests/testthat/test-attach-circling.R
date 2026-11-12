# Two survey days, each with a line long enough to give several segments, and
# a circling excursion partway along. Built so that the *choice* of segment
# matters: attaching to any segment on the day would pass a weaker test.
# `sighting_at` places the on-effort sighting, which decides whether the
# same-species rule can find it in the target segment. Record 24 falls in the
# segment the break-off closes; record 5 falls in an earlier one.
scenario <- function(sighting_at = 24) {
  one_day <- function(date, first_event, spec) {
    n <- 30
    d <- data.frame(
      FILEID = paste0("F", substr(date, 9, 10)),
      EVENTNO = first_event + seq_len(n) - 1,
      YEAR = 2024L, MONTH = 4L, DAY = as.integer(substr(date, 9, 10)),
      TIME = 120000 + seq_len(n),
      LATITUDE = 43 + seq_len(n) * 0.01, LONGITUDE = -69,
      LEGTYPE = 2, LEGSTAGE = c(1, rep(2, n - 2), 5), LEGNO = 1,
      ALT = 229, BEAUFORT = 2, VISIBLTY = 5,
      SPECCODE = NA_character_, IDREL = NA_real_, NUMBER = NA_real_,
      DATE = as.Date(date), stringsAsFactors = FALSE
    )
    d$SPECCODE[sighting_at] <- spec
    d$IDREL[sighting_at] <- 3
    d$NUMBER[sighting_at] <- 2

    # Break off near the end, circle, and resume.
    circ <- d[rep(25, 4), ]
    circ$LEGTYPE <- c(2, 4, 4, 2)
    circ$LEGSTAGE <- c(3, NA, NA, 4)
    circ$SPECCODE <- c(NA, spec, NA, NA)
    circ$IDREL <- c(NA, 3, NA, NA)
    circ$NUMBER <- c(NA, 1, NA, NA)
    circ$EVENTNO <- d$EVENTNO[25] + c(0.1, 0.2, 0.3, 0.4)
    rbind(d[1:25, ], circ, d[26:n, ])
  }
  rbind(one_day("2024-04-01", 1, "RIWH"), one_day("2024-04-02", 1000, "FIWH"))
}

prep <- function(dat) {
  d <- point_to_point_effort(flag_effort(flag_circling(make_leg_id(dat))))
  d <- split_tracks(d)
  list(dat = d,
       chopped = cut_segments(
         plan_segments(track_effort(d), seg_length = 5, seed = 1), d, seed = 1
       ))
}

test_that("a circling sighting joins the segment in progress before the break-off", {
  p <- prep(scenario())
  out <- attach_circling_sightings(p$chopped, p$dat)
  added <- out[out$case %in% "circling", ]
  expect_equal(nrow(added), 2)

  # Each attaches to a segment whose last event precedes the sighting, and to
  # the latest such segment - not merely to some segment on the same day.
  bounds <- tapply(p$chopped$EVENTNO, p$chopped$seg_id, max)
  for (i in seq_len(nrow(added))) {
    same_day <- p$chopped$seg_id[p$chopped$DATE == added$DATE[i]]
    eligible <- bounds[unique(same_day)]
    eligible <- eligible[eligible <= added$EVENTNO[i]]
    expect_equal(added$seg_id[i], names(eligible)[which.max(eligible)])
  }
})

test_that("a sighting never attaches across a day boundary", {
  p <- prep(scenario())
  out <- attach_circling_sightings(p$chopped, p$dat)
  added <- out[out$case %in% "circling", ]

  seg_day <- tapply(as.character(p$chopped$DATE), p$chopped$seg_id,
                    function(x) x[1])
  expect_equal(as.vector(seg_day[added$seg_id]), as.character(added$DATE))
})

test_that("the same-species rule refuses a group seen too far back", {
  # The same species is on the line, but 20 records (~22 km) before the
  # break-off. A per-day or per-occupation test would attach these; the
  # aircraft did not turn back 22 km for that group, so it must not.
  p <- prep(scenario(sighting_at = 5))
  same <- attach_circling_sightings(p$chopped, p$dat, mode = "same_species")
  all_of <- attach_circling_sightings(p$chopped, p$dat, mode = "all")

  expect_equal(sum(all_of$case %in% "circling"), 2)
  expect_equal(sum(same$case %in% "circling"), 0)

  # Widening the limit is a choice the caller can make.
  wide <- attach_circling_sightings(p$chopped, p$dat, mode = "same_species",
                                    max_gap_km = 25)
  expect_equal(sum(wide$case %in% "circling"), 2)
})

test_that("a segment boundary between sighting and break-off loses nothing", {
  # Sighting at record 19 sits in the segment before the one the break-off
  # closes (record 25). Searching only that segment found no group and
  # dropped the circled animal. 6 records is ~6.7 km, inside a 10 km limit.
  p <- prep(scenario(sighting_at = 19))
  ch <- p$chopped[p$chopped$DATE == as.Date("2024-04-01"), ]
  sight_seg <- ch$seg_id[ch$SPECCODE %in% "RIWH"]
  out <- attach_circling_sightings(p$chopped, p$dat, max_gap_km = 10)
  o1 <- out[out$DATE == as.Date("2024-04-01"), ]
  circ <- o1[o1$case %in% "circling", ]
  grp <- o1[o1$SPECCODE %in% "RIWH" & !(o1$case %in% "circling"), ]

  expect_equal(nrow(circ), 1)
  expect_false(identical(circ$seg_id, sight_seg))   # boundary really between
  expect_equal(grp$NUMBER, 3)                       # 2 seen + 1 circled
  expect_false(circ$circling_counted)
})

test_that("a group circled before the last resume collects nothing more", {
  # Two circles on one line: the second's animals must not join the group the
  # first circle was for.
  dat <- scenario(sighting_at = 24)
  d1 <- dat[dat$DATE == as.Date("2024-04-01"), ]
  later <- d1[rep(28, 4), ]
  later$EVENTNO <- d1$EVENTNO[28] + c(0.1, 0.2, 0.3, 0.4)
  later$LEGTYPE <- c(2, 4, 4, 2)
  later$LEGSTAGE <- c(3, NA, NA, 4)
  later$SPECCODE <- c(NA, "RIWH", NA, NA)
  later$IDREL <- c(NA, 3, NA, NA)
  later$NUMBER <- c(NA, 4, NA, NA)
  dat <- rbind(dat, later)
  dat <- dat[order(dat$DATE, dat$EVENTNO), ]
  p <- prep(dat)
  out <- attach_circling_sightings(p$chopped, p$dat, max_gap_km = 10)
  o1 <- out[out$DATE == as.Date("2024-04-01"), ]
  grp <- o1[o1$SPECCODE %in% "RIWH" & !(o1$case %in% "circling"), ]
  # Only the first circle's single animal is added; the 4 are not.
  expect_equal(grp$NUMBER, 3)
})

test_that("a species not seen from the line is refused", {
  dat <- scenario()
  # Make the circling animal a different species from the on-effort sighting.
  i <- which(dat$LEGTYPE == 4 & !is.na(dat$SPECCODE))
  dat$SPECCODE[i] <- "SEWH"
  p <- prep(dat)

  same <- attach_circling_sightings(p$chopped, p$dat, mode = "same_species")
  expect_equal(sum(same$case %in% "circling"), 0)
  # But "all" still takes them.
  expect_equal(sum(attach_circling_sightings(p$chopped, p$dat,
                                             mode = "all")$case %in% "circling"), 2)
})

test_that("attaching never changes any segment's effort", {
  p <- prep(scenario())
  out <- attach_circling_sightings(p$chopped, p$dat)
  expect_equal(
    tapply(p$chopped$pt2pt.effort, p$chopped$seg_id, sum),
    tapply(out$pt2pt.effort, out$seg_id, sum)
  )
})

test_that("mode none and no candidates return the input untouched", {
  p <- prep(scenario())
  expect_identical(attach_circling_sightings(p$chopped, p$dat, mode = "none"),
                   p$chopped)

  bare <- p$dat
  bare$CIRCLE <- 0L
  expect_identical(attach_circling_sightings(p$chopped, bare), p$chopped)
})

test_that("a sighting before any segment ends is left unattached", {
  dat <- scenario()
  # Move the circling excursion to the very start, before any segment closes.
  dat$EVENTNO[dat$LEGTYPE == 4] <- 0.5
  p <- prep(dat)
  out <- attach_circling_sightings(p$chopped, p$dat)
  expect_lte(sum(out$case %in% "circling"), 2)
})

test_that("the two circling distances are both available and differ", {
  # `scenario()` logs the circling records at the break-off position, so the
  # measured distance there is zero by construction and would not tell the two
  # options apart. Moved off the line, which is what circling is.
  moved <- scenario()
  off <- !is.na(moved$LEGTYPE) & moved$LEGTYPE == 4
  moved$LATITUDE[off] <- moved$LATITUDE[off] + 0.02
  moved$LONGITUDE[off] <- moved$LONGITUDE[off] + 0.02
  p <- prep(moved)

  inherited <- attach_circling_sightings(p$chopped, p$dat)   # with_group
  measured <- attach_circling_sightings(p$chopped, p$dat,
                                        distance = "break_off")

  ci <- inherited[!is.na(inherited$case) & inherited$case == "circling", ]
  cm <- measured[!is.na(measured$case) & measured$case == "circling", ]
  expect_gt(nrow(ci), 0)
  expect_equal(nrow(ci), nrow(cm))

  # The measurement is on every attached record whichever option is chosen, so
  # the size of the disagreement can be seen without re-segmenting.
  expect_equal(ci$break_off_distance, cm$break_off_distance)
  expect_false(anyNA(cm$break_off_distance))
  expect_true(all(cm$break_off_distance > 0))

  # "break_off" puts the measured one in `distance`; "inherit" does not.
  expect_equal(cm$distance, cm$break_off_distance)
  expect_true(all(cm$distance_source == "break_off"))

  # `with_group` gives the record no distance at all, because it makes no
  # observation out of it - the animals are counted into the group they were
  # found with, and that group has its own measured distance already.
  expect_true(all(is.na(ci$distance)))
  expect_true(all(is.na(ci$distance_source)))

  # And a break-off distance carries no side: it is not perpendicular to the
  # line, so there is no left or right of the line to be on.
  expect_true(all(is.na(cm$side)))
})

test_that("with_group counts the animals into the group, not as a new one", {
  moved <- scenario()
  off <- !is.na(moved$LEGTYPE) & moved$LEGTYPE == 4
  moved$LATITUDE[off] <- moved$LATITUDE[off] + 0.02
  moved$LONGITUDE[off] <- moved$LONGITUDE[off] + 0.02
  p <- prep(moved)

  sep <- attach_circling_sightings(p$chopped, p$dat, distance = "break_off")
  grp <- attach_circling_sightings(p$chopped, p$dat)   # with_group, the default

  circ <- function(x) x[!is.na(x$case) & x$case == "circling", ]
  expect_equal(nrow(circ(sep)), nrow(circ(grp)))

  # The record still rides along - where the animals were logged is a fact
  # nothing else records - but it is not counted a second time.
  expect_true(all(circ(sep)$circling_counted))
  expect_false(any(circ(grp)$circling_counted))

  # Not one animal more or fewer either way. The circling animals move from a
  # row of their own into the group they were counted with.
  total <- function(x) sum(as.numeric(x$NUMBER), na.rm = TRUE)
  expect_equal(total(sep), total(grp))

  # And they land on the on-effort sighting, whose group is now larger.
  on_line <- function(x) {
    x[(is.na(x$case) | x$case != "circling") &
        !is.na(x$SPECCODE) & x$SPECCODE != "", ]
  }
  expect_gt(total(on_line(grp)), total(on_line(sep)))
  expect_equal(total(on_line(grp)) - total(on_line(sep)), total(circ(sep)))
})

test_that("with_group makes no second detection out of a circling sighting", {
  segs_sep <- segment_survey(example_data(), seg_length = 5, seed = 1,
                             circling = "same_species",
                             circling_distance = "break_off")
  segs_grp <- segment_survey(example_data(), seg_length = 5, seed = 1,
                             circling = "same_species")

  is_circ <- function(d) !is.na(d$circling) & d$circling == 1
  expect_gt(sum(is_circ(segs_sep$detections)), 0)
  expect_equal(sum(is_circ(segs_grp$detections)), 0)

  # One fewer row, and not one fewer animal: the same total, in bigger groups.
  expect_lt(nrow(segs_grp$detections), nrow(segs_sep$detections))
  expect_equal(sum(segs_grp$detections$size, na.rm = TRUE),
               sum(segs_sep$detections$size, na.rm = TRUE))

  # Which is the point: no row carries a distance it was not seen at.
  expect_false(any(segs_grp$detections$distance_source %in%
                     c("circling", "break_off")))
})

test_that("the removed inherit option says what replaced it and why", {
  # It produced the identical estimate to with_group while adding a row that
  # claimed a distance nothing was detected at. Anything still naming it should
  # be told that, not told it is not one of the choices.
  p <- prep(scenario())
  expect_error(
    attach_circling_sightings(p$chopped, p$dat, distance = "inherit"),
    "was removed"
  )
  expect_error(
    segment_survey(example_data(), seg_length = 5, seed = 1,
                   circling_distance = "inherit"),
    "was removed"
  )
})

test_that("segment_survey() says the circling source has no effect there", {
  # The distance it computes would be replaced when the record is attached,
  # so asking for it used to change nothing and say nothing.
  expect_warning(
    segs <- segment_survey(example_data(), seg_length = 5, seed = 1,
                           distance_sources = c("angle", "circling")),
    "has no effect"
  )
  expect_false("circling" %in% segs$settings$distance_sources)
})

test_that("break_off uses the exact position's perpendicular distance where recorded", {
  dat <- scenario()
  dat$S_LAT <- NA_real_
  dat$S_LONG <- NA_real_
  # Day 1's circling sighting has an exact position 0.01 deg east of the line,
  # which runs due north along -69. Day 2's has none, so it falls back.
  i <- which(dat$LEGTYPE == 4 & !is.na(dat$SPECCODE) &
               dat$DATE == as.Date("2024-04-01"))
  dat$S_LAT[i] <- dat$LATITUDE[i] - 0.02
  dat$S_LONG[i] <- -69 + 0.01
  p <- prep(dat)

  out <- attach_circling_sightings(p$chopped, p$dat, distance = "break_off")
  ci <- out[out$case %in% "circling", ]
  d1 <- ci[ci$DATE == as.Date("2024-04-01"), ]
  d2 <- ci[ci$DATE == as.Date("2024-04-02"), ]

  expect_equal(d1$distance_source, "circling")
  expect_equal(d1$side, "right")
  expected <- 0.01 * 111.12 * cos((dat$S_LAT[i]) * pi / 180) * 1000
  expect_equal(d1$distance, expected, tolerance = 0.01)
  # `break_off_distance` is still carried, and still measured to the logged
  # position - the aircraft's - which in this scenario is the break-off itself.
  expect_equal(d1$break_off_distance, 0)

  expect_equal(d2$distance_source, "break_off")
  expect_equal(d2$distance, d2$break_off_distance)

  km <- attach_circling_sightings(p$chopped, p$dat, distance = "break_off",
                                  units = "km")
  ck <- km[km$case %in% "circling", ]
  expect_equal(ck$distance, ci$distance / 1000)
  expect_equal(ck$break_off_distance, ci$break_off_distance)
})

test_that("segment_survey() passes distance_units through to break_off", {
  # It used to put metres into `distance` whatever `distance_units` said.
  m <- segment_survey(scenario(), seg_length = 5, seed = 1,
                      circling_distance = "break_off")
  k <- segment_survey(scenario(), seg_length = 5, seed = 1,
                      circling_distance = "break_off", distance_units = "km")
  cm <- m$detections[m$detections$circling %in% 1, ]
  ck <- k$detections[k$detections$circling %in% 1, ]
  expect_gt(nrow(cm), 0)
  expect_equal(ck$distance, cm$distance / 1000)
})

one_record_circle <- function(sighting_at = 24) {
  # A circle logged as one record: break-off, the sighting, resume. Track
  # splitting treats a lone off-effort record as on effort, so the track and
  # the segment run straight through the circle.
  d <- scenario(sighting_at)
  d <- d[d$DATE == as.Date("2024-04-01"), ]
  d[-which(d$LEGTYPE == 4 & is.na(d$SPECCODE)), ]
}

test_that("a circling sighting attaches at the break-off, not the segment before", {
  p <- prep(one_record_circle())
  out <- attach_circling_sightings(p$chopped, p$dat, max_gap_km = 10)
  ci <- out[out$case %in% "circling", ]
  brk_seg <- p$chopped$seg_id[p$chopped$LEGSTAGE %in% 3]

  expect_equal(nrow(ci), 1)
  expect_equal(ci$seg_id, brk_seg)
  # The sighting was logged at the break-off position.
  expect_equal(ci$break_off_distance, 0)
})

test_that("a one-record circle's sighting is counted once, and not at all under none", {
  run <- function(mode) {
    s <- suppressWarnings(segment_survey(one_record_circle(), seg_length = 5,
                                         seed = 1, circling = mode,
                                         circling_max_gap_km = 10))
    sum(s$sightings$n_animals[s$sightings$SPECCODE == "RIWH"])
  }
  expect_equal(run("same_species"), 3)   # 2 seen + 1 circled
  expect_equal(run("none"), 2)
})

test_that("a second survey on the same day does not capture the circling sighting", {
  # EVENTNO restarts in each file, so a lookup by day alone matched the other
  # survey's records: attached 111 km away, and dropped under same_species.
  d <- scenario(24)
  d <- d[d$DATE == as.Date("2024-04-01"), ]
  other <- d
  other$FILEID <- "F99"
  other$LATITUDE <- other$LATITUDE + 1
  other$LEGTYPE[other$LEGTYPE == 4] <- 2
  other$LEGSTAGE[other$LEGSTAGE %in% c(3, 4)] <- 2
  other$SPECCODE <- NA
  other$NUMBER <- NA
  other$IDREL <- NA
  p <- prep(rbind(d, other))

  out <- attach_circling_sightings(p$chopped, p$dat, max_gap_km = 10)
  ci <- out[out$case %in% "circling", ]
  expect_equal(nrow(ci), 1)
  expect_equal(unique(p$chopped$FILEID[p$chopped$seg_id == ci$seg_id]), "F01")
  expect_equal(ci$break_off_distance, 0)
  grp <- out[out$SPECCODE %in% "RIWH" & !(out$case %in% "circling"), ]
  expect_equal(grp$NUMBER, 3)
})

test_that("a bad circling_max_gap_km fails before segmenting, under its own name", {
  expect_error(
    segment_survey(example_data(), seg_length = 5, seed = 1,
                   circling_max_gap_km = "5"),
    "circling_max_gap_km"
  )
})

test_that("attaching a circle never moves a segment midpoint", {
  # Rows were sorted by seg_id text after attaching, which puts segment 19
  # before segment 2; midpoints then interpolated toward the wrong segment.
  n <- 60
  d <- data.frame(
    FILEID = "F01", EVENTNO = 1:n, DATE = as.Date("2024-04-01"), YEAR = 2024L,
    MONTH = 4L, DAY = 1L, TIME = 120000 + 1:n, LATITUDE = 43 + (1:n) * 0.018,
    LONGITUDE = -69, LEGTYPE = 2, LEGSTAGE = c(1, rep(2, n - 2), 5), LEGNO = 1,
    ALT = 229, BEAUFORT = 2, VISIBLTY = 5, SPECCODE = NA_character_,
    IDREL = NA_real_, NUMBER = NA_real_, stringsAsFactors = FALSE
  )
  d$SPECCODE[4] <- "RIWH"
  d$IDREL[4] <- 3
  d$NUMBER[4] <- 2
  circ <- d[rep(5, 4), ]
  circ$LEGTYPE <- c(2, 4, 4, 2)
  circ$LEGSTAGE <- c(3, NA, NA, 4)
  circ$SPECCODE <- c(NA, "RIWH", NA, NA)
  circ$IDREL <- c(NA, 3, NA, NA)
  circ$NUMBER <- c(NA, 1, NA, NA)
  circ$EVENTNO <- 5 + c(0.1, 0.2, 0.3, 0.4)
  d <- rbind(d[1:5, ], circ, d[6:n, ])

  without <- segment_survey(d, seg_length = 5, seed = 1, circling = "none")
  with <- segment_survey(d, seg_length = 5, seed = 1)
  expect_gt(nrow(with$segments), 10)
  m <- merge(without$segments, with$segments, by = "seg_id")
  expect_equal(m$mid_lat.x, m$mid_lat.y)
  expect_equal(m$mid_lon.x, m$mid_lon.y)
})

test_that("without LEGSTAGE a circling sighting is never its own anchor", {
  # A one-record circle stays in its track, so the circling sighting is in
  # `chopped`. With no LEGSTAGE the reference is the sighting's own event, and
  # the anchor must still be the last on-effort record before it.
  d <- one_record_circle()
  i <- which(d$LEGTYPE == 4)
  d$LATITUDE[i] <- d$LATITUDE[i] + 0.01        # logged 1.1 km off the line
  d$LEGSTAGE <- NULL
  p <- prep(d)
  out <- attach_circling_sightings(p$chopped, p$dat, mode = "all")
  ci <- out[out$case %in% "circling", ]
  expect_equal(nrow(ci), 1)
  expect_equal(ci$break_off_distance, 1111.2, tolerance = 1e-3)
})
