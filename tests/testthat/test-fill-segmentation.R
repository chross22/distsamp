# The fill behaviour itself is tested in narwcr. What this package needs to
# know is that a frame recorded once per leg, then filled, segments to the
# same result as one recorded in full.

test_that("a filled frame segments the same as one recorded in full", {
  # The point of filling: a file that omits repeats should behave like one that
  # does not.
  full <- example_data()
  gapped <- full
  n <- nrow(gapped)
  cols <- c("LEGTYPE", "LEGSTAGE", "LEGNO", "BEAUFORT", "VISIBLTY")

  # Blank a value only where it repeats the row above *within the same file and
  # day* - which is what the recording convention actually does. Blanking across
  # a day boundary would delete a value nothing can recover.
  same_group <- c(FALSE, gapped$FILEID[-1] == gapped$FILEID[-n] &
                    gapped$DATE[-1] == gapped$DATE[-n])
  for (nm in cols) {
    repeats <- c(FALSE, gapped[[nm]][-1] == gapped[[nm]][-n])
    repeats[is.na(repeats)] <- FALSE
    gapped[[nm]][same_group & repeats] <- NA
  }
  expect_gt(sum(is.na(gapped$LEGTYPE)), sum(is.na(full$LEGTYPE)))

  restored <- suppressMessages(
    fill_narwc(gapped, columns = cols, direction = "down")
  )
  expect_equal(restored$LEGTYPE, full$LEGTYPE)
  expect_equal(restored$BEAUFORT, full$BEAUFORT)

  a <- segment_survey(full, seg_length = 5, seed = 1)
  b <- segment_survey(restored, seg_length = 5, seed = 1)
  expect_equal(a$segments$seg_eff, b$segments$seg_eff)
  expect_equal(a$sightings, b$sightings)
})
