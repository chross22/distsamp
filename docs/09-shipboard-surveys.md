# Shipboard surveys

*C. H. Ross. 2026-11-12. Distributed with the package source.*

## 1. Scope

`distsamp` was aerial by construction. It is now aerial by default and segments
a shipboard survey when told to. This chapter states what that changes and what
it does not.

In short:

```r
sea  <- prepare_survey(dat, platform = "vessel")     # or "ship"
segs <- segment_survey(sea, seg_length = 10, platform = "vessel")
```

`platform_defaults("vessel")` prints everything the argument decides.

## 2. Why one argument and not three

A platform changes three things. They must move together, and each fails
silently on its own:

| | aerial | vessel |
|---|---|---|
| effort criteria | the handbook's, altitude ceiling included | the same, minus the altitude ceiling |
| distance sources | `angle`, `exact`, `strip` | `exact` |
| `PLATFORM_KIND` kept | `aerial` | `vessel` |

If a file is filtered to its vessel records and the criteria are left alone,
the survey has **no effort at all**, reported as though every ship record had
flown too high. If the criteria are changed and the sources are left alone, the
detection function is fitted to `NA`, or to whatever the aircraft columns
happened to contain. `platform` therefore sets all three from one place
(`R/02-platform.R`). `effort_args` or `distance_sources` still override it name by
name.

## 3. The altitude criterion is dropped, not raised

This error is easy to make and cannot be seen in the output. `flag_effort()`
fails a record whose criterion value is missing. A vessel record with no `ALT`
therefore fails the ceiling **at any height**, and `max_alt_m = Inf` rescues
nothing. `narwcr::flag_effort()` now accepts `max_alt_m = NULL`, meaning the
criterion does not apply. The vessel defaults pass that.

**Measure the cost on each file rather than assuming it.** Not every vessel
record has an empty `ALT`. Some programmes write the observer's eye height
there: a few metres, well under an aircraft's 366 m ceiling. Most of the
shipboard survey then passes, and the problem stays hidden until the empty
records are noticed to be missing. On one real extract of 1,037,180 vessel
records, the median `ALT` was 9.7 m and 338,562 were `NA`. Dropping the
criterion recovered 32% of the vessel effort and raised eligible sightings from
464 to 741.

`na_action = "pass"` would also let those records through, but it is the wrong
tool. It lets *every* missing criterion through, so a record with no sea state
and no visibility also becomes on-effort. Dropping only the criterion that
cannot apply keeps the rest strict.

## 4. Two of the four distance sources are aircraft measurements

`"angle"` is \eqn{h/\tan\theta}: an altitude divided by a tangent (8.A.2). The
`"strip"` code books are the Skymaster's and the AT-11's (8.A.31). Neither
applies to a ship. Requesting either with `platform = "vessel"` is therefore an
**error**, not a column of `NA`, because a silent drop would not report why the
detections vanished.

That leaves `"exact"`: `S_LAT`/`S_LONG` projected onto the track bearing. It
depends on geometry, not platform, and it is the source a shipboard survey in
this archive actually has. `"circling"` is a break-off from the census line. It
applies to either platform and is opt-in for both.

The archive does **not** carry the reticle-and-bearing measurements a dedicated
shipboard programme would normally use; no handbook variable exists for them.
If a file has them in extra columns, compute the perpendicular distance
separately and pass the frame in with a `distance` column already present.
`segment_survey()` leaves an existing `distance` column unchanged.

## 5. `LEGTYPE` 5 and 6 are still off effort

These codes mark shipboard records, but they mark a **platform of opportunity
(POP)**: a ship that recorded what it saw while travelling elsewhere. That is
not a designed line-transect survey. Counting it as effort puts unsearched track
into the denominator of a density estimate. The vessel defaults therefore keep
`legtype_on_effort = 2`, a designated census line, as the aerial defaults do.

A dedicated shipboard line-transect survey codes its lines `LEGTYPE = 2` and
needs nothing here. A POP file is not a distance sampling dataset, and no
argument to this package makes it one.

## 6. Segmentation itself did not change

Great-circle distance between consecutive fixes, splitting a line where effort
breaks, and cutting a continuous track into lengths are geometry. A ship's track
segments the same way a plane's does. `test-platform.R` asserts this: the same
positions under both platforms give identical `seg_eff` and midpoints.

## 7. Detecting the wrong platform

Nothing in a NARWC file reliably states the platform, so speed remains the
check, and it now runs in both directions. `segment_survey()` warns when the
records are not moving at the speed the named platform implies.
`diagnose_pipeline(platform = )` reports the median speed in knots and names the
argument that matches what it found.

## 8. Naming

`"vessel"` is the documented spelling, because it is the `PLATFORM_KIND` level
the filter compares against; nothing is translated on the way through. `"ship"`
is accepted everywhere `"vessel"` is.
