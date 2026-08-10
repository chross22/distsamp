# Every message a call emits, not just the first - read_narwc() can report
# renames, dropped columns, and dropped records in one call.
all_messages <- function(expr) {
  msgs <- character(0)
  withCallingHandlers(
    force(expr),
    message = function(m) {
      msgs <<- c(msgs, conditionMessage(m))
      invokeRestart("muffleMessage")
    }
  )
  paste(msgs, collapse = "\n")
}

messy <- function(...) {
  base <- data.frame(
    FileID = "A", Event = 1:3, Year = 2024, Month = 4, Day = 1,
    stringsAsFactors = FALSE
  )
  cbind(base, data.frame(..., stringsAsFactors = FALSE))
}

test_that("case and separators do not have to match", {
  d <- suppressMessages(read_narwc(messy(
    Lat_DD = 43, Long_DD = -69, LegType = 2, leg_no = 1, Sea_State = 3
  )))
  expect_true(all(c("FILEID", "EVENTNO", "YEAR", "MONTH", "DAY",
                    "LATITUDE", "LONGITUDE", "LEGTYPE", "LEGNO",
                    "BEAUFORT") %in% names(d)))
})

test_that("a column already correctly named always wins", {
  d <- suppressMessages(read_narwc(data.frame(
    FILEID = "A", EVENTNO = 1, YEAR = 2024, MONTH = 4, DAY = 1,
    LATITUDE = 43, Lat_DD = 99, LONGITUDE = -69, LEGTYPE = 2,
    stringsAsFactors = FALSE
  )))
  expect_equal(d$LATITUDE, 43)
})

test_that("only inferred matches are reported, not documented aliases", {
  # LAT_DD is the handbook's own name for LATITUDE. Announcing it on every
  # read would bury the matches that deserve a second look.
  expect_silent(read_narwc(system.file("extdata", "narwc-example.csv",
                                       package = "distsamp")))

  msg <- all_messages(read_narwc(messy(LAT_DD = 43, LONG_DD = -69, LegType = 2)))
  expect_match(msg, "LegType -> LEGTYPE")
  expect_no_match(msg, "LAT_DD")
})

test_that("time is taken from whichever zone the file records", {
  for (nm in c("TIME_UTC", "TIME_LOC", "Time_Local", "GMT", "gmt", "Time_GMT")) {
    raw <- messy(LAT_DD = 43, LONG_DD = -69, LegType = 2)
    raw[[nm]] <- "120000"
    d <- suppressMessages(read_narwc(raw))
    expect_true("TIME" %in% names(d), info = nm)
    expect_equal(d$TIME[1], 120000, info = nm)
  }
})

test_that("when two zones are present UTC is preferred, and TIME beats both", {
  raw <- messy(LAT_DD = 43, LONG_DD = -69, LegType = 2,
               TIME_LOC = "080000", TIME_UTC = "120000")
  expect_equal(suppressMessages(read_narwc(raw))$TIME[1], 120000)

  raw$TIME <- "999999"
  expect_equal(suppressMessages(read_narwc(raw))$TIME[1], 999999)
})

test_that("GMT is the same clock as UTC and outranks local", {
  raw <- messy(LAT_DD = 43, LONG_DD = -69, LegType = 2,
               TIME_LOC = "080000", GMT = "120000")
  expect_equal(suppressMessages(read_narwc(raw))$TIME[1], 120000)
})

test_that("records with no position are dropped, and said so", {
  raw <- messy(LAT_DD = c(43, 43.1, NA), LONG_DD = c(-69, NA, -69), LegType = 2)
  expect_match(all_messages(read_narwc(raw)), "Dropped 2 records")

  d <- suppressMessages(read_narwc(raw))
  expect_equal(nrow(d), 1)
  expect_false(anyNA(d$LATITUDE))

  kept <- suppressMessages(read_narwc(raw, drop_missing_position = FALSE))
  expect_equal(nrow(kept), 3)
})

test_that("a file with no missing positions says nothing about them", {
  expect_no_match(
    all_messages(read_narwc(messy(LAT_DD = 43, LONG_DD = -69, LegType = 2))),
    "Dropped"
  )
})

test_that("extra_columns takes glob patterns", {
  raw <- messy(LAT_DD = 43, LONG_DD = -69, LegType = 2,
               Trk_Speed = 1, Trk_Head = 2, Other = 3)
  d <- suppressMessages(read_narwc(raw, extra_columns = "Trk*"))
  expect_true(all(c("Trk_Speed", "Trk_Head") %in% names(d)))
  expect_false("Other" %in% names(d))

  # A plain name still works, and mixing the two is fine.
  d2 <- suppressMessages(read_narwc(raw, extra_columns = c("Trk*", "Other")))
  expect_true("Other" %in% names(d2))
})

test_that("nothing is matched by edit distance", {
  # `EVENTN0` with a zero is not `EVENTNO`, and guessing it would be worse
  # than leaving it alone.
  raw <- messy(LAT_DD = 43, LONG_DD = -69, LegType = 2)
  names(raw)[names(raw) == "Event"] <- "EVENTN0"
  d <- suppressMessages(read_narwc(raw, extra_columns = "EVENTN0"))
  expect_false("EVENTNO" %in% names(d))
  expect_true("EVENTN0" %in% names(d))
})

test_that("two inputs cannot both claim one canonical name", {
  raw <- messy(Lat_DD = 43, latitude = 44, LONG_DD = -69, LegType = 2)
  d <- suppressMessages(read_narwc(raw))
  expect_equal(sum(names(d) == "LATITUDE"), 1)
})
