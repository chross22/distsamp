test_that("odd codes are port and even codes are starboard", {
  for (sc in c("cetap", "nlpsc")) {
    b <- narwc_strip_bins(sc)
    real <- b[b$code > 0, ]
    expect_true(all(real$side[real$code %% 2 == 1] == "left"))
    expect_true(all(real$side[real$code %% 2 == 0] == "right"))
  }
})

test_that("code 0 is on-track and only exists for the AT-11 scheme", {
  cetap <- narwc_strip_bins("cetap", "at-11")
  expect_true(0 %in% cetap$code)
  expect_equal(cetap$side[cetap$code == 0], "on-track")
  # The Skymaster cannot see beneath itself, so NLPSC has no zero code.
  expect_false(0 %in% narwc_strip_bins("nlpsc")$code)
})

test_that("bins are ordered and non-overlapping within a scheme", {
  b <- narwc_strip_bins("nlpsc", units = "nmi")
  left <- b[b$side == "left", ]
  expect_false(is.unsorted(left$distbegin))
  # Each bin starts where the previous ended.
  expect_equal(left$distbegin[-1], left$distend[-nrow(left)])
})

test_that("the CETAP scheme keeps the unsplit closest interval", {
  # Handbook 8.A.31: 1,2 was originally 0-1/4, later split into 3,4 and 5,6.
  # Both forms are in the archive, so 1,2 must not be silently merged away.
  b <- narwc_strip_bins("cetap", units = "nmi")
  expect_equal(b$distend[b$code == 1], 0.25)
  expect_equal(b$distend[b$code == 3], 0.125)
  expect_equal(b$distbegin[b$code == 5], 0.125)
})

test_that("CETAP top bins differ by aircraft", {
  at <- narwc_strip_bins("cetap", "at-11", units = "nmi")
  sky <- narwc_strip_bins("cetap", "skymaster", units = "nmi")
  # AT-11: one open bin above 1 nmi. Skymaster: split at 2.
  expect_equal(max(at$code), 14)
  expect_equal(max(sky$code), 16)
  expect_equal(at$distend[at$code == 13], Inf)
  expect_equal(sky$distend[sky$code == 13], 2)
  expect_equal(sky$distend[sky$code == 15], Inf)
})

test_that("the same code means different distances in the two schemes", {
  # This is the whole reason the scheme matters: reading a CETAP-era code with
  # the NLPSC book doubles the distance.
  cet <- strip_distance(5, scheme = "cetap", units = "nmi")
  nlp <- strip_distance(5, scheme = "nlpsc", units = "nmi")
  expect_equal(cet$distbegin, 0.125)
  expect_equal(nlp$distbegin, 0.25)
  expect_false(isTRUE(all.equal(cet$distend, nlp$distend)))
})

test_that("auto scheme switches at the October 2011 boundary", {
  before <- strip_distance(5, scheme = "auto", date = "2011-09-30")
  after <- strip_distance(5, scheme = "auto", date = "2011-10-01")
  expect_equal(before$scheme, "cetap")
  expect_equal(after$scheme, "nlpsc")
})

test_that("auto scheme refuses to guess without a date", {
  expect_error(strip_distance(5, scheme = "auto"), "date")
})

test_that("units convert", {
  m <- strip_distance(5, scheme = "nlpsc", units = "m")
  km <- strip_distance(5, scheme = "nlpsc", units = "km")
  nmi <- strip_distance(5, scheme = "nlpsc", units = "nmi")
  expect_equal(m$distbegin / 1000, km$distbegin)
  expect_equal(nmi$distbegin * 1852, m$distbegin)
})

test_that("the Skymaster blind spot shifts the inner bins", {
  # 8.A.31: CETAP Skymaster distances are measured from about 1/8 nmi out.
  out <- strip_distance(c(1, 3), scheme = "nlpsc", units = "nmi",
                        left_truncation = TRUE)
  # Code 1 covers 0-1/8, which lies entirely inside the unsearched strip.
  expect_true(is.na(out$distbegin[1]))
  # Code 3 already starts at 1/8, so it is unchanged.
  expect_equal(out$distbegin[2], 0.125)

  # The AT-11 could see beneath itself, so nothing shifts.
  at <- strip_distance(1, scheme = "cetap", platform = "at-11",
                       units = "nmi", left_truncation = TRUE)
  expect_equal(at$distbegin, 0)
})

test_that("top bins are open-ended and say so", {
  for (sc in c("cetap", "nlpsc")) {
    b <- narwc_strip_bins(sc)
    expect_true(any(is.infinite(b$distend)))
  }
})

test_that("unknown codes give NA rather than a wrong distance", {
  out <- strip_distance(c(99, 5), scheme = "nlpsc")
  expect_true(is.na(out$distbegin[1]))
  expect_false(is.na(out$distbegin[2]))
})

test_that("strip_distance is vectorised over codes and dates", {
  out <- strip_distance(c(5, 5, 7), scheme = "auto",
                        date = c("2005-01-01", "2015-01-01", "2015-01-01"))
  expect_equal(nrow(out), 3)
  expect_equal(out$scheme, c("cetap", "nlpsc", "nlpsc"))
})
