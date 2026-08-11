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
