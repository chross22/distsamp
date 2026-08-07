# Build inst/extdata/narwc-example.csv
#
# A synthetic aerial line-transect survey in NARWC format, modelled on the
# hypothetical survey in Figure 2 of the NARWC user's guide (Kenney 2021,
# section 4.2). It exercises every branch of the segmentation pipeline:
#
#   * a transit with an off-effort sighting          (LEGTYPE 1)
#   * survey lines with begin/continue/end stages    (LEGTYPE 2, LEGSTAGE 1/2/5)
#   * two sightings sharing one EVENTNO              (handbook events 5 and 11)
#   * a pilot sighting                               (LEGSTAGE 6)
#   * a cross-leg with a sighting                    (LEGTYPE 3)
#   * a break-off, multi-record circling, and resume (LEGSTAGE 3, LEGTYPE 4, LEGSTAGE 4)
#   * a sighting detected in a vertical photograph   (LEGSTAGE 7)
#   * a survey line abandoned and re-flown later     (exercises LEGNO3)
#   * a high sea state that puts records off effort  (BEAUFORT > 3)
#
# Geometry is deliberately simple: every line runs due north along a constant
# meridian in 0.01-degree steps, so one step is 1.112 km and expected segment
# lengths can be worked out by hand.
#
# Run with:  Rscript data-raw/make-fixture.R

set.seed(20240401)

KM_PER_DEG <- 60 * 1.852 # 111.12 km, as used by gc_distance()

rows <- list()
add <- function(...) {
  rows[[length(rows) + 1L]] <<- data.frame(..., stringsAsFactors = FALSE)
}

# One survey record. Everything not supplied defaults to a plain on-effort
# routine position with no sighting.
rec <- function(fileid, eventno, date, time, lat, lon,
                legtype = 2, legstage = 2, legno = NA,
                beaufort = 2, visiblty = 5, alt = 229,
                speccode = NA, idrel = NA, number = NA, sightno = NA,
                strip = NA) {
  d <- as.Date(date)
  add(
    FILEID = fileid,
    EVENTNO = eventno,
    YEAR = as.integer(format(d, "%Y")),
    MONTH = as.integer(format(d, "%m")),
    DAY = as.integer(format(d, "%d")),
    TIME = time,
    LAT_DD = lat,
    LONG_DD = lon,
    LEGTYPE = legtype,
    LEGSTAGE = legstage,
    LEGNO = legno,
    ALT = alt,
    BEAUFORT = beaufort,
    VISIBLTY = visiblty,
    CLOUD = 2,
    GLAREL = 0,
    GLARER = 1,
    SPECCODE = speccode,
    IDREL = idrel,
    NUMBER = number,
    NUMCALF = NA,
    SIGHTNO = sightno,
    STRIP = strip,
    STRATUM = "0",
    PLATFORM = 210
  )
}

# hhmmss arithmetic: advance a clock time by whole seconds.
bump_time <- function(t0, seconds) {
  t0 <- as.numeric(t0)
  h <- t0 %/% 10000
  m <- (t0 %% 10000) %/% 100
  s <- t0 %% 100
  total <- h * 3600 + m * 60 + s + seconds
  sprintf("%02d%02d%02d", (total %/% 3600) %% 24, (total %% 3600) %/% 60, total %% 60)
}

# A straight survey line of `n` positions running north from `lat0`.
# Returns the event number and time to carry on from.
fly_line <- function(fileid, date, eventno, time, legno, lat0, lon, n,
                     beaufort = 2, sightings = list(), step = 0.01,
                     seconds_per_step = 25, end_stage = 5) {
  for (i in seq_len(n)) {
    lat <- lat0 + (i - 1) * step
    stage <- if (i == 1) 1 else if (i == n) end_stage else 2
    sight <- sightings[[as.character(i)]]
    t <- bump_time(time, (i - 1) * seconds_per_step)

    rec(fileid, eventno, date, t, lat, lon,
        legtype = 2, legstage = stage, legno = legno, beaufort = beaufort)
    eventno <- eventno + 1

    # Sightings sit at their own event, immediately after the routine position,
    # at the same location (handbook 4.2: sightings must not share an event
    # with a begin- or end-line record).
    if (!is.null(sight)) {
      for (s in seq_along(sight$speccode)) {
        rec(fileid, eventno, date, t, lat, lon,
            legtype = 2, legstage = sight$legstage[s], legno = legno,
            beaufort = beaufort,
            speccode = sight$speccode[s], idrel = sight$idrel[s],
            number = sight$number[s], sightno = sight$sightno[s],
            strip = sight$strip[s])
      }
      # Groups seen together share one event number (handbook events 5, 11).
      eventno <- eventno + 1
    }
  }
  list(eventno = eventno, time = bump_time(time, n * seconds_per_step))
}

sighting <- function(speccode, number, idrel = 3, legstage = 2, sightno = 1,
                     strip = 7) {
  list(speccode = speccode, number = number, idrel = idrel,
       legstage = legstage, sightno = sightno, strip = strip)
}

## ---------------------------------------------------------------------------
## Day 1 - 2024-04-01
## ---------------------------------------------------------------------------
fid <- "AA240401"
d1 <- "2024-04-01"

# Transit out to the first line, with an off-effort sighting (group a).
rec(fid, 1, d1, "120000", 42.90, -69.00, legtype = 1, legstage = NA)
rec(fid, 2, d1, "120200", 42.95, -69.00, legtype = 1, legstage = NA)
rec(fid, 3, d1, "120200", 42.95, -69.00, legtype = 1, legstage = NA,
    speccode = "HUWH", idrel = 3, number = 2, sightno = 1)

# Line 1: 21 positions, 22.224 km. Sightings of groups b, then c/d/e sharing an
# event, then a pilot sighting (group f, LEGSTAGE 6).
st <- fly_line(
  fid, d1, eventno = 4, time = 120400, legno = 1,
  lat0 = 43.00, lon = -69.00, n = 21,
  sightings = list(
    "5"  = sighting("RIWH", 1, sightno = 2),
    "10" = list(speccode = c("RIWH", "RIWH", "FIWH"),
                number   = c(2, 1, 3),
                idrel    = c(3, 3, 2),
                legstage = c(2, 2, 2),
                sightno  = c(3, 4, 5),
                strip    = c(5, 5, 9)),
    "16" = sighting("FIWH", 1, legstage = 6, sightno = 6)
  )
)

# Cross-leg to line 2, with a sighting (group g).
rec(fid, st$eventno, d1, st$time, 43.21, -69.05, legtype = 3, legstage = NA)
rec(fid, st$eventno + 1, d1, bump_time(st$time, 60), 43.23, -69.08,
    legtype = 3, legstage = NA, speccode = "MIWH", idrel = 2, number = 1,
    sightno = 7)
ev <- st$eventno + 2

# Line 2, first half: 8 positions from 43.25, then break off to circle. The
# line does not end here, so the last position stays at "continue line" (2)
# rather than "end line" (5).
st <- fly_line(fid, d1, eventno = ev, time = 123000, legno = 2,
               lat0 = 43.25, lon = -69.10, n = 8, end_stage = 2,
               sightings = list(
                 "6" = list(speccode = c("RIWH", "RIWH"),
                            number = c(3, 1), idrel = c(3, 3),
                            legstage = c(2, 2), sightno = c(8, 9),
                            strip = c(3, 3))
               ))
ev <- st$eventno

# Break off the census line to circle the sightings (handbook event 12).
rec(fid, ev, d1, st$time, 43.32, -69.10, legtype = 2, legstage = 3, legno = 2)
ev <- ev + 1

# Circling: several logged positions, one with an off-effort sighting (group j).
# Two or more consecutive off-effort records is what starts a new track.
circ_t <- bump_time(st$time, 60)
for (i in 1:5) {
  lat <- 43.32 + c(0.004, 0.006, 0.003, -0.001, 0.001)[i]
  lon <- -69.10 + c(0.003, -0.002, -0.005, -0.003, 0.001)[i]
  spec <- if (i == 3) "RIWH" else NA
  rec(fid, ev, d1, bump_time(circ_t, (i - 1) * 40), lat, lon,
      legtype = 4, legstage = NA, legno = 2,
      speccode = spec, idrel = if (i == 3) 3 else NA,
      number = if (i == 3) 1 else NA, sightno = if (i == 3) 10 else NA)
  ev <- ev + 1
}

# Resume the census line as close as possible to the break-off point.
resume_t <- bump_time(circ_t, 300)
rec(fid, ev, d1, resume_t, 43.33, -69.10, legtype = 2, legstage = 4, legno = 2)
ev <- ev + 1

# Line 2, second half: 8 more positions, ending the line.
for (i in 1:8) {
  lat <- 43.34 + (i - 1) * 0.01
  stage <- if (i == 8) 5 else 2
  rec(fid, ev, d1, bump_time(resume_t, i * 25), lat, -69.10,
      legtype = 2, legstage = stage, legno = 2)
  ev <- ev + 1
}

## ---------------------------------------------------------------------------
## Day 2 - 2024-04-02
## ---------------------------------------------------------------------------
fid <- "AA240402"
d2 <- "2024-04-02"

# Line 3: 31 positions, 33.336 km. Long enough for several segments. Includes a
# sighting found afterwards in a vertical photograph (LEGSTAGE 7).
st <- fly_line(
  fid, d2, eventno = 1, time = 133000, legno = 3,
  lat0 = 43.00, lon = -68.80, n = 31,
  sightings = list(
    "8"  = sighting("RIWH", 4, sightno = 1, strip = 5),
    "20" = sighting("SEWH", 2, idrel = 2, sightno = 2, strip = 11),
    "26" = sighting("LOTU", 1, legstage = 7, sightno = 3, strip = NA)
  )
)
ev <- st$eventno

# Line 4, first occupation: abandoned after 6 positions when the sea state
# rises. BEAUFORT 5 puts these records off effort.
for (i in 1:6) {
  rec(fid, ev, d2, bump_time(st$time, i * 25), 43.35 + (i - 1) * 0.01, -68.70,
      legtype = 2, legstage = if (i == 1) 1 else 2, legno = 4,
      beaufort = if (i <= 4) 2 else 5)
  ev <- ev + 1
}
t_now <- bump_time(st$time, 200)

# Line 5, flown while conditions on line 4 were poor: 8 positions, 7.778 km.
for (i in 1:8) {
  rec(fid, ev, d2, bump_time(t_now, i * 25), 43.35 + (i - 1) * 0.01, -68.60,
      legtype = 2, legstage = if (i == 1) 1 else if (i == 8) 5 else 2,
      legno = 5)
  ev <- ev + 1
}
t_now <- bump_time(t_now, 250)

# Line 4, second occupation: the same LEGNO returned to later in the day. This
# must not be joined to the first occupation, or the distance between them
# would be counted as effort.
for (i in 1:9) {
  rec(fid, ev, d2, bump_time(t_now, i * 25), 43.45 + (i - 1) * 0.01, -68.70,
      legtype = 2, legstage = if (i == 1) 1 else if (i == 9) 5 else 2,
      legno = 4,
      speccode = if (i == 5) "RIWH" else NA,
      idrel = if (i == 5) 1 else NA, # "possible" - excluded by default
      number = if (i == 5) 1 else NA,
      sightno = if (i == 5) 4 else NA)
  ev <- ev + 1
}

## ---------------------------------------------------------------------------
out <- do.call(rbind, rows)

dir.create("inst/extdata", recursive = TRUE, showWarnings = FALSE)
write.csv(out, "inst/extdata/narwc-example.csv", row.names = FALSE, na = "")

cat("wrote", nrow(out), "records to inst/extdata/narwc-example.csv\n")
cat("dates:", paste(unique(paste(out$YEAR, out$MONTH, out$DAY, sep = "-")),
                    collapse = ", "), "\n")
cat("species:", paste(sort(unique(stats::na.omit(out$SPECCODE))), collapse = ", "), "\n")
