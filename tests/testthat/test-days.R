test_that("all three NULL leaves the data alone, undated rows included", {
  d <- example_data()
  d$DATE[1] <- NA
  expect_identical(filter_days(d), d)
})

test_that("days can be named outright", {
  d <- example_data()
  expect_setequal(filter_days(d, dates = "2024-04-01")$DATE,
                  as.Date("2024-04-01"))
  expect_setequal(filter_days(d, dates = as.Date("2024-04-02"))$DATE,
                  as.Date("2024-04-02"))
})

test_that("years and months take numbers or names", {
  d <- example_data()
  expect_equal(nrow(filter_days(d, years = 2024)), nrow(d))
  expect_equal(nrow(filter_days(d, months = 4)), nrow(d))
  expect_equal(nrow(filter_days(d, months = "April")), nrow(d))
  expect_equal(nrow(filter_days(d, months = "apr")), nrow(d))
})

test_that("the three narrow rather than accumulate", {
  # years = 2024, months = 1 is January 2024 - not all of 2024 and every
  # January. The intersection is the useful reading and the surprising one, so
  # it is the one pinned down.
  d <- example_data()
  expect_error(filter_days(d, years = 2024, months = 1), "No records fall")
  expect_equal(nrow(filter_days(d, years = 2024, months = 4)), nrow(d))
})

test_that("a record with no date is in no month", {
  d <- example_data()
  d$DATE[seq_len(5)] <- NA
  expect_equal(nrow(filter_days(d, years = 2024)), nrow(d) - 5)
})

test_that("matching nothing says what the data actually covers", {
  d <- example_data()
  expect_error(filter_days(d, years = 1999), "2024-04-01 to 2024-04-02")
  expect_error(filter_days(d, years = 1999), "2 survey days")
})

test_that("unreadable selections say which value could not be read", {
  d <- example_data()
  expect_error(filter_days(d, dates = "last tuesday"), "last tuesday")
  expect_error(filter_days(d, months = "Smarch"), "Smarch")
  expect_error(filter_days(d, months = 13), "between 1 and 12")
})

test_that("a DATE column is required once a selection is asked for", {
  d <- example_data()
  d$DATE <- NULL
  expect_silent(filter_days(d))                  # nothing asked, nothing needed
  expect_error(filter_days(d, years = 2024), "DATE")
})

test_that("levels sort as numbers where they are numbers", {
  # Order of appearance is what gave a LEGSTAGE legend reading 1, 2, 4, 3.
  expect_equal(sort_levels(c("2", "10", "1")), c("1", "2", "10"))
  expect_equal(sort_levels(c("b", "a")), c("a", "b"))
  expect_equal(sort_levels(c(NA, "1")), "1")
})
