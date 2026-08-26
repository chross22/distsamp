# Shared fixtures for the test suite.

example_path <- function() {
  system.file("extdata", "narwc-example.csv", package = "distsamp")
}

example_data <- function() {
  # The fixture uses the handbook's own LAT_DD/LONG_DD, so reading it reports a
  # rename. That is correct behaviour and is tested in test-column-matching.R;
  # here it would only crowd out the message each test is actually about.
  read_narwc(example_path(), quiet = TRUE)
}

# A single straight north-running survey line, `n` positions `step` degrees
# apart, entirely on effort. One step is step * 111.12 km, so expected
# distances are exact and checkable by hand.
#
# `secs` is the interval between fixes, which is what decides the platform:
# `classify_platform()` reads speed and nothing else. At the default 25 s a
# 0.01-degree step is 86 knots, an aircraft.
straight_line <- function(n = 21, step = 0.01, lat0 = 43, lon = -69,
                          legno = 1, date = "2024-04-01", beaufort = 2,
                          secs = 25) {
  tibble::tibble(
    FILEID = "TEST",
    EVENTNO = seq_len(n),
    YEAR = 2024L, MONTH = 4L, DAY = as.integer(substr(date, 9, 10)),
    TIME = 120000 + seq_len(n) * secs,
    LATITUDE = lat0 + (seq_len(n) - 1) * step,
    LONGITUDE = lon,
    LEGTYPE = 2,
    LEGSTAGE = c(1, rep(2, n - 2), 5),
    LEGNO = legno,
    ALT = 229, BEAUFORT = beaufort, VISIBLTY = 5,
    SPECCODE = NA_character_, IDREL = NA_real_, NUMBER = NA_real_,
    DATE = as.Date(date)
  )
}

# Seconds since midnight as the HHMMSS integer NARWC records. `straight_line()`
# adds its interval straight onto the number, which is right only while the
# seconds field does not carry; a vessel's intervals are minutes long, so this
# does the carrying.
hhmmss <- function(sec) {
  as.integer(sec %/% 3600) * 10000L +
    as.integer((sec %% 3600) %/% 60) * 100L +
    as.integer(sec %% 60)
}

# The same line surveyed from a ship: 0.01 degrees (1.111 km) every 216 s is
# 10 knots, against the 40-knot threshold `classify_platform()` uses.
#
# `ALT` is NA rather than absent, which is the case that matters - an absent
# column is skipped by `flag_effort()`, a missing value fails the criterion,
# and it is the second that puts a shipboard survey off effort.
vessel_line <- function(n = 21, secs = 216, ...) {
  dat <- straight_line(n = n, ...)
  dat$TIME <- hhmmss(12 * 3600 + seq_len(n) * secs)
  dat$ALT <- NA_real_
  dat
}

# A day flown and a day sailed, in one frame - the file the platform option
# exists for. Separate dates and a running EVENTNO, because `make_leg_id()`
# sorts, and two lines both numbered 1..n interleave into alternating records.
mixed_platforms <- function(n = 21) {
  air <- straight_line(n = n, legno = 1, date = "2024-04-01")
  sea <- vessel_line(n = n, legno = 2, lat0 = 44, date = "2024-04-02")
  out <- rbind(air, sea)
  out$EVENTNO <- seq_len(nrow(out))
  out
}

KM_PER_DEG <- 60 * 1.852
