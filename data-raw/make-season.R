# Synthetic full survey seasons, for profiling.
#
# Not part of the package and not used by any test: this exists so the
# performance numbers in docs/04-verification.md can be reproduced, and so a
# future change can be checked against them.
#
# Run with:  Rscript -e 'source("data-raw/make-season.R"); ...'

# A synthetic survey season, shaped like the fixture but arbitrarily large.
#
# days x lines x points_per_line records, with sightings and circling
# excursions at realistic-ish rates. Generated vectorised so that making the
# data is not what is being timed.

make_season <- function(days = 20, lines = 12, points = 400,
                        sighting_rate = 0.01, circle_rate = 0.15, seed = 1) {
  set.seed(seed)

  n_line <- days * lines
  # One line: LEGSTAGE 1, then 2s, then 5.
  stage <- c(1, rep(2, points - 2), 5)

  lat0 <- 42.5
  rec <- data.frame(
    day = rep(seq_len(days), each = lines * points),
    line = rep(rep(seq_len(lines), each = points), times = days),
    k = rep(seq_len(points), times = n_line)
  )
  rec$FILEID <- sprintf("AA%04d", rec$day)
  rec$DATE <- as.Date("2024-01-01") + rec$day - 1
  rec$YEAR <- 2024L
  rec$MONTH <- as.integer(format(rec$DATE, "%m"))
  rec$DAY <- as.integer(format(rec$DATE, "%d"))
  rec$TIME <- 120000 + rec$k
  rec$EVENTNO <- seq_len(nrow(rec))
  rec$LEGNO <- rec$line
  rec$LEGTYPE <- 2
  rec$LEGSTAGE <- rep(stage, times = n_line)
  # Alternate lines run north and south, 0.02 degrees apart in longitude.
  north <- rec$line %% 2 == 1
  rec$LATITUDE <- ifelse(north, lat0 + rec$k * 0.005, lat0 + (points - rec$k) * 0.005)
  rec$LONGITUDE <- -69 - rec$line * 0.02
  rec$ALT <- 229
  rec$BEAUFORT <- 2
  rec$VISIBLTY <- 5
  rec$SPECCODE <- NA_character_
  rec$IDREL <- NA_real_
  rec$NUMBER <- NA_real_
  rec$SIGHTNO <- NA_real_
  rec$ANGLEL <- NA_real_
  rec$ANGLER <- NA_real_
  rec$STRIP <- NA_real_
  rec$S_LAT <- NA_real_
  rec$S_LONG <- NA_real_

  # Sightings on a fraction of on-effort records, with a declination angle.
  is_sight <- rec$LEGSTAGE == 2 & runif(nrow(rec)) < sighting_rate
  n_s <- sum(is_sight)
  rec$SPECCODE[is_sight] <- sample(c("RIWH", "FIWH", "HUWH"), n_s, TRUE)
  rec$IDREL[is_sight] <- 3
  rec$NUMBER[is_sight] <- sample(1:4, n_s, TRUE)
  rec$SIGHTNO[is_sight] <- seq_len(n_s)
  rec$ANGLER[is_sight] <- runif(n_s, 15, 80)

  # A fraction of sightings trigger a circling excursion: break off (3), a few
  # LEGTYPE 4 records, resume (4). These are what
  # attach_circling_sightings() loops over.
  circling <- which(is_sight)[runif(n_s) < circle_rate]
  extra <- do.call(rbind, lapply(circling, function(i) {
    base <- rec[rep(i, 5), ]
    base$LEGTYPE <- c(2, 4, 4, 4, 2)
    base$LEGSTAGE <- c(3, NA, NA, NA, 4)
    base$SPECCODE <- c(NA, NA, rec$SPECCODE[i], NA, NA)
    base$IDREL <- c(NA, NA, 3, NA, NA)
    base$NUMBER <- c(NA, NA, 1, NA, NA)
    base$SIGHTNO <- NA_real_
    base$ANGLER <- NA_real_
    base$LATITUDE <- base$LATITUDE + c(0, 0.002, 0.003, 0.001, 0.004)
    base$EVENTNO <- rec$EVENTNO[i] + seq(0.1, 0.5, by = 0.1)
    base
  }))

  out <- rbind(rec, extra)
  out <- out[order(out$DATE, out$FILEID, out$EVENTNO), ]
  out$EVENTNO <- seq_len(nrow(out))
  out[, setdiff(names(out), c("day", "line", "k"))]
}

time_it <- function(label, expr) {
  t <- system.time(force(expr))[["elapsed"]]
  cat(sprintf("  %-34s %7.2f s\n", label, t))
  invisible(t)
}
