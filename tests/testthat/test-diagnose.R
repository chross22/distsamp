two_days_one_fileid <- function() {
  d1 <- straight_line(n = 21, lat0 = 43, legno = 5, date = "2024-04-01")
  d2 <- straight_line(n = 21, lat0 = 40, legno = 5, date = "2024-04-02")
  d2$EVENTNO <- d2$EVENTNO + 100
  dat <- dplyr::bind_rows(d1, d2)
  dat$FILEID <- "F"
  # No begin-line records, so DATE in the grouping is the only thing that can
  # keep the two days apart — which is what these tests are about.
  dat$LEGSTAGE <- NA_real_
  dat
}

test_that("a clean file reports nothing needing attention", {
  out <- capture.output(res <- diagnose_pipeline(example_data(), seg_length = 5))
  expect_true(any(grepl("Nothing above needs attention", out)))
  expect_false(any(grepl("^  (WARN|FAIL)", out)))
  expect_named(res, c("dat", "findings", "segments"))
})

test_that("a constant FILEID across several days is reported", {
  out <- capture.output(diagnose_pipeline(two_days_one_fileid(), seg_length = 5))
  expect_true(any(grepl("WARN.*FILEID is the same value", out)))
})

test_that("the days do not merge, and the report says so", {
  # `make_leg_id()` bounds occupations by DATE, so dropping DATE from the
  # grouping no longer changes the total. The check still runs, and reporting
  # that it found nothing is the point — it is what tells you the file is not
  # in the state that produced a 38x effort overstatement.
  out <- capture.output(diagnose_pipeline(two_days_one_fileid(), seg_length = 5))
  expect_true(any(grepl("ok.*grouping without DATE gives the same total", out)))
  expect_false(any(grepl("WARN.*grouping without DATE", out)))
})

test_that("an altitude in feet is named as the reason nothing is on effort", {
  dat <- two_days_one_fileid()
  dat$ALT <- 751
  out <- capture.output(diagnose_pipeline(dat, seg_length = 5))
  expect_true(any(grepl("WARN.*above the 366 m ceiling", out)))
  expect_true(any(grepl("Read as feet it would be 229 m", out)))
  expect_true(any(grepl("ALT above 366 m: 42", out)))
  expect_true(any(grepl("FAIL.*0 on-effort", out)))
})

test_that("a second platform is reported as a silent exclusion", {
  dat <- two_days_one_fileid()
  dat$PLATFORM <- c(rep(210, 21), rep(310, 21))
  out <- capture.output(diagnose_pipeline(dat, seg_length = 5))
  expect_true(any(grepl("WARN.*more than one platform", out)))
})

test_that("an empty file stops at reading and says so", {
  out <- capture.output(res <- diagnose_pipeline(example_data()[0, ]))
  expect_true(any(grepl("FAIL.*0 records", out)))
  expect_named(res, "dat")
})

test_that("it reads a path as well as a data frame", {
  out <- capture.output(diagnose_pipeline(example_path(), seg_length = 5))
  expect_true(any(grepl("113 records", out)))
})

test_that("it reports nothing back into the data it was given", {
  dat <- example_data()
  before <- names(dat)
  invisible(capture.output(diagnose_pipeline(dat, seg_length = 5)))
  expect_equal(names(dat), before)
})

test_that("days = 1 diagnoses one survey day and says the totals are partial", {
  out <- capture.output(
    res <- diagnose_pipeline(two_days_one_fileid(), days = 1, seg_length = 5)
  )
  expect_true(any(grepl("first 1 of 2 survey days", out)))
  expect_equal(length(unique(res$dat$DATE)), 1)
  # One day cannot merge with another, so the hazard is not warned about.
  expect_false(any(grepl("WARN.*grouping without DATE", out)))
  expect_true(any(grepl("ok.*grouping without DATE gives the same total", out)))
})

test_that("days larger than the file is not an error", {
  out <- capture.output(
    diagnose_pipeline(two_days_one_fileid(), days = 99, seg_length = 5)
  )
  expect_false(any(grepl("survey days \\(", out)))
})

test_that("days without a DATE column warns rather than subsetting blindly", {
  dat <- two_days_one_fileid()
  dat$DATE <- NULL
  out <- capture.output(diagnose_pipeline(dat, days = 1, seg_length = 5))
  expect_true(any(grepl("WARN.*needs a DATE column", out)))
})

test_that("subsetting keeps the column mapping readable", {
  out <- capture.output(diagnose_pipeline(example_path(), days = 1, seg_length = 5))
  expect_true(any(grepl("survey days", out)))
})

test_that("TRKDIST is compared against the computed total when present", {
  dat <- two_days_one_fileid()
  dat$TRKDIST <- 0.01 * KM_PER_DEG * 1000
  out <- capture.output(diagnose_pipeline(dat, seg_length = 5))
  expect_true(any(grepl("TRKDIST gives", out)))
})

test_that("a recorded total far above the computed one is warned about", {
  dat <- two_days_one_fileid()
  dat$TRKDIST <- 0.01 * KM_PER_DEG * 1000 * 2   # the track wandered
  out <- capture.output(diagnose_pipeline(dat, seg_length = 5))
  expect_true(any(grepl("WARN.*the receiver recorded", out)))
})

test_that("no TRKDIST means no comparison line", {
  out <- capture.output(diagnose_pipeline(two_days_one_fileid(), seg_length = 5))
  expect_false(any(grepl("TRKDIST", out)))
})

test_that("an empty criterion column is named as the reason nothing is on effort", {
  dat <- two_days_one_fileid()
  dat$ALT <- NA_real_
  out <- capture.output(diagnose_pipeline(dat, seg_length = 5))
  expect_true(any(grepl("ALT missing: 42", out)))
  expect_true(any(grepl("FAIL.*0 on-effort", out)))
})

test_that("records on no line are counted separately from occupations", {
  dat <- two_days_one_fileid()
  dat$LEGTYPE[1:3] <- 1                    # transit before the first line
  out <- capture.output(diagnose_pipeline(dat, seg_length = 5))
  expect_true(any(grepl("record\\(s\\) on no line", out)))
  # NA must not be counted as an occupation of its own.
  expect_false(any(grepl("3 line occupation\\(s\\)", out)))
})

test_that("days accepts specific dates, not only a count", {
  out <- capture.output(
    res <- diagnose_pipeline(two_days_one_fileid(), days = "2024-04-02",
                             seg_length = 5)
  )
  expect_equal(as.character(unique(res$dat$DATE)), "2024-04-02")
})

test_that("a date not in the data is named", {
  out <- capture.output(
    diagnose_pipeline(two_days_one_fileid(), days = c("2024-04-01", "2020-01-01"),
                      seg_length = 5)
  )
  expect_true(any(grepl("not in the data: 2020-01-01", out)))
})

test_that("selecting no day at all stops rather than diagnosing everything", {
  out <- capture.output(
    res <- diagnose_pipeline(two_days_one_fileid(), days = "2020-01-01",
                             seg_length = 5)
  )
  expect_true(any(grepl("FAIL.*selected no survey day", out)))
})

test_that("a missing ALT says it is only the subset", {
  dat <- two_days_one_fileid()
  dat$ALT <- NA_real_
  out <- capture.output(diagnose_pipeline(dat, days = 1, seg_length = 5))
  expect_true(any(grepl("not necessarily the file", out)))

  whole <- capture.output(diagnose_pipeline(dat, seg_length = 5))
  expect_false(any(grepl("not necessarily the file", whole)))
})

test_that("days = auto skips a day that records no altitude", {
  d1 <- straight_line(n = 21, lat0 = 43, legno = 1, date = "2024-04-01")
  d1$ALT <- NA_real_                      # the day that cannot be on effort
  d2 <- straight_line(n = 21, lat0 = 44, legno = 2, date = "2024-04-02")
  d2$EVENTNO <- d2$EVENTNO + 100
  dat <- dplyr::bind_rows(d1, d2)

  out <- capture.output(res <- diagnose_pipeline(dat, days = "auto",
                                                 seg_length = 5))
  expect_equal(as.character(unique(res$dat$DATE)), "2024-04-02")
  expect_true(any(grepl("the day with the most census records", out)))
  expect_false(any(grepl("FAIL.*0 on-effort", out)))
})

test_that("days = auto falls back when no day has a full criterion set", {
  dat <- two_days_one_fileid()
  dat$ALT <- NA_real_
  out <- capture.output(diagnose_pipeline(dat, days = "auto", seg_length = 5))
  expect_true(any(grepl("WARN.*no day has census records", out)))
})

test_that("a named day is not reported as the first day", {
  out <- capture.output(
    diagnose_pipeline(two_days_one_fileid(), days = "2024-04-02", seg_length = 5)
  )
  expect_true(any(grepl("1 named day: 2024-04-02", out)))
  expect_false(any(grepl("the first 1 of", out)))
})

test_that("a count is still reported as the first days", {
  out <- capture.output(
    diagnose_pipeline(two_days_one_fileid(), days = 1, seg_length = 5)
  )
  expect_true(any(grepl("the first 1 of 2 survey days", out)))
})

test_that("a vessel-speed track is flagged as not an aerial survey", {
  # 1 Hz logging, ~10 knots: 5.3 m between fixes.
  n <- 400
  dat <- straight_line(n = n, step = 5.3 / 111120, lat0 = 43)
  dat$TIME <- 120000 + seq_len(n) - 1        # one second apart
  dat$TIME <- as.numeric(format(as.POSIXct(dat$TIME %/% 10000 * 3600 +
    (dat$TIME %% 10000) %/% 100 * 60 + dat$TIME %% 100,
    origin = "1970-01-01", tz = "UTC"), "%H%M%S"))

  out <- capture.output(diagnose_pipeline(dat, seg_length = 1))
  expect_true(any(grepl("WARN.*knots. That is a vessel", out)))
})

test_that("an aircraft-speed track is reported as consistent", {
  out <- capture.output(diagnose_pipeline(example_data(), seg_length = 5))
  expect_true(any(grepl("consistent with a survey aircraft", out)))
})
