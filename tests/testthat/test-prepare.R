test_that("it produces everything segment_survey() needs", {
  air <- prepare_aerial(example_data(), quiet = TRUE)
  expect_true(all(c("LEGNO3", "PLATFORM_KIND", "OnOff.Effort") %in% names(air)))
  expect_s3_class(segment_survey(air, seg_length = 5, seed = 1),
                  "distsamp_segments")
})

test_that("the same steps by hand give the same result", {
  by_hand <- narwcr::flag_effort(
    narwcr::fill_legstage(narwcr::make_leg_id(example_data(), quiet = TRUE),
                          quiet = TRUE)
  )
  by_hand$PLATFORM_KIND <- narwcr::classify_platform(by_hand)
  by_hand <- by_hand[!is.na(by_hand$PLATFORM_KIND) &
                       by_hand$PLATFORM_KIND == "aerial", ]

  auto <- prepare_aerial(example_data(), quiet = TRUE)
  expect_equal(nrow(auto), nrow(by_hand))
  expect_equal(auto$LEGNO3, by_hand$LEGNO3)
  expect_equal(auto$OnOff.Effort, by_hand$OnOff.Effort)
})

test_that("the platform filter happens after occupations are built", {
  # Filtering first makes two occupations of one line adjacent, and they merge.
  a <- straight_line(n = 10, lat0 = 43, legno = 1)
  sea <- straight_line(n = 10, step = 5.3 / 111120, lat0 = 43.5, legno = 2)
  sea$TIME <- 120000 + seq_len(10) - 1
  sea$EVENTNO <- sea$EVENTNO + 100
  b <- straight_line(n = 10, lat0 = 44, legno = 1)
  b$EVENTNO <- b$EVENTNO + 200

  air <- prepare_aerial(dplyr::bind_rows(a, sea, b), quiet = TRUE)
  # The two occupations of line 1 must stay apart despite the vessel leg going.
  expect_equal(length(unique(air$LEGNO3)), 2)
})

test_that("platform = all classifies without filtering", {
  out <- prepare_aerial(example_data(), platform = "all", quiet = TRUE)
  expect_equal(nrow(out), nrow(example_data()))
  expect_true("PLATFORM_KIND" %in% names(out))
})

test_that("fill_legstage can be turned off", {
  with <- prepare_aerial(example_data(), quiet = TRUE)
  without <- prepare_aerial(example_data(), fill_legstage = FALSE, quiet = TRUE)
  expect_true("LEGSTAGE_FILLED" %in% names(with))
  expect_false("LEGSTAGE_FILLED" %in% names(without))
  expect_gte(sum(narwcr::on_effort_census_rows(with)),
             sum(narwcr::on_effort_census_rows(without)))
})

test_that("effort_args reach flag_effort", {
  strict <- prepare_aerial(example_data(), quiet = TRUE,
                           effort_args = list(max_beaufort = 0))
  expect_lt(sum(strict$OnOff.Effort == 1),
            sum(prepare_aerial(example_data(), quiet = TRUE)$OnOff.Effort == 1))
})

test_that("an existing OnOff.Effort is respected, not recomputed", {
  # Flagged with a stricter cutoff than the default. If prepare_aerial() were
  # to re-run flag_effort(), the count would rise back to the default's.
  strict <- narwcr::flag_effort(example_data(), max_beaufort = 0)
  out <- prepare_aerial(strict, quiet = TRUE)

  expect_equal(nrow(out), nrow(strict))          # the fixture is all aerial
  expect_equal(sum(out$OnOff.Effort == 1), sum(strict$OnOff.Effort == 1))
  expect_lt(sum(out$OnOff.Effort == 1),
            sum(prepare_aerial(example_data(), quiet = TRUE)$OnOff.Effort == 1))
})

test_that("it says what it did", {
  msg <- capture_messages(prepare_aerial(example_data()))
  expect_match(paste(msg, collapse = ""), "Platform, from the speed")
  expect_match(paste(msg, collapse = ""), "records on effort")
})

test_that("no clock means no silent platform assumption", {
  d <- example_data()
  d$TIME <- NULL
  expect_warning(prepare_aerial(d, quiet = TRUE), "No platform check")
})

test_that("correct runs after the filter and before the effort flags", {
  # An altitude in feet fails the ceiling; corrected in `correct`, it passes.
  d <- example_data()
  d$ALT <- d$ALT / 0.3048                       # pretend the file is in feet

  none <- prepare_aerial(d, quiet = TRUE)
  expect_equal(sum(none$OnOff.Effort == 1), 0)

  fixed <- prepare_aerial(d, quiet = TRUE, correct = function(x) {
    x$ALT <- x$ALT * 0.3048
    x
  })
  expect_gt(sum(fixed$OnOff.Effort == 1), 0)
  expect_equal(sum(fixed$OnOff.Effort == 1),
               sum(prepare_aerial(example_data(), quiet = TRUE)$OnOff.Effort == 1))
})

test_that("correct cannot quietly drop records", {
  expect_error(
    prepare_aerial(example_data(), quiet = TRUE,
                   correct = function(x) x[1:5, ]),
    "nrow"
  )
})
