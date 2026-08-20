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

test_that("the same-species rule is applied per segment, not per day", {
  # The sharp case: the same species is present on the day, but in an earlier
  # segment than the one the break-off closes. A per-day test would attach
  # these; the CETAP rule is per segment, so it must not.
  p <- prep(scenario(sighting_at = 5))
  same <- attach_circling_sightings(p$chopped, p$dat, mode = "same_species")
  all_of <- attach_circling_sightings(p$chopped, p$dat, mode = "all")

  expect_equal(sum(all_of$case %in% "circling"), 2)
  expect_equal(sum(same$case %in% "circling"), 0)
})

test_that("a species the segment does not hold is refused", {
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
    "with_group"
  )
  expect_error(
    segment_survey(example_data(), seg_length = 5, seed = 1,
                   circling_distance = "inherit"),
    "with_group"
  )
})
