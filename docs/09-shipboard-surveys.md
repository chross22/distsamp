# Shipboard surveys

`distsamp` was aerial by construction. It is now aerial by default, and will
segment a shipboard survey when told to. This is what that changes, and — more
importantly — what it does not.

## The one-line version

```r
sea  <- prepare_survey(dat, platform = "vessel")     # or "ship"
segs <- segment_survey(sea, seg_length = 10, platform = "vessel")
```

`platform_defaults("vessel")` prints everything the argument decides.

## Why one argument and not three

The three things a platform changes have to move together, and each of them is
silent on its own:

| | aerial | vessel |
|---|---|---|
| effort criteria | the handbook's, altitude ceiling included | the same, minus the altitude ceiling |
| distance sources | `angle`, `exact`, `strip` | `exact` |
| `PLATFORM_KIND` kept | `aerial` | `vessel` |

Filter a file to its vessel records and leave the criteria alone, and you get a
survey with **no effort at all** — reported as though every ship record had
flown too high. Change the criteria and leave the sources alone, and you get a
detection function fitted to `NA`, or worse, to whatever the aircraft columns
happened to contain. So `platform` sets all three, from one place
(`R/platform.R`), and `effort_args` or `distance_sources` still override it
name by name.

## The altitude criterion is dropped, not raised

This is the part that is easy to get wrong and impossible to see. `flag_effort()`
fails a record whose criterion is missing, so a vessel record — which has no
`ALT`, because it has no altitude to have — fails the ceiling **at any height**.
`max_alt_m = Inf` does not rescue it. `narwcr::flag_effort()` now accepts
`max_alt_m = NULL`, meaning the criterion does not apply, and that is what the
vessel defaults pass.

`na_action = "pass"` would also let those records through, and it is the wrong
tool: it lets *every* missing criterion through with them, so a record with no
sea state and no visibility becomes on-effort too. Dropping the one criterion
that cannot apply keeps the rest strict.

## Two of the four distance sources are aircraft measurements

`"angle"` is \eqn{h/\tan\theta} — an altitude divided by a tangent (8.A.2). The
`"strip"` code books are the Skymaster's and the AT-11's (8.A.31). Neither means
anything on a ship, so asking for them with `platform = "vessel"` is an **error**
rather than a column of `NA`: a silent drop would report nothing about why the
detections vanished.

That leaves `"exact"` — `S_LAT`/`S_LONG` projected onto the track bearing. It is
geometry rather than platform, and it is the source a shipboard survey in this
archive actually has. `"circling"` is a break-off from the census line and
applies to either platform, opt-in for both.

The archive does **not** carry the reticle-and-bearing measurements a dedicated
shipboard programme would normally use; there is no handbook variable for them.
If your file has them in extra columns, compute the perpendicular distance
yourself and pass the frame in with a `distance` column already present —
`segment_survey()` leaves it alone when it finds one.

## `LEGTYPE` 5 and 6 are still off effort

They mark shipboard records, but they mark a **platform of opportunity** — a
ship that recorded what it saw while going somewhere. That is not a designed
line-transect, and counting it as effort puts unsearched track into the
denominator of a density estimate. The vessel defaults therefore keep
`legtype_on_effort = 2`, a designated census line, exactly as the aerial ones do.

A dedicated shipboard line-transect survey codes its lines `LEGTYPE = 2` and
needs nothing here. A POP file is not a distance sampling dataset, and no
argument to this package makes it one.

## Segmentation itself did not change

Great-circle distance between consecutive fixes, splitting a line where effort
breaks, and cutting a continuous track into lengths are geometry. A ship's track
segments the same way a plane's does, and `test-platform.R` asserts exactly that:
the same positions under both platforms give identical `seg_eff` and midpoints.

## What still tells you the platform is wrong

Nothing in a NARWC file reliably announces a platform, so speed remains the
check — and it now runs in both directions. `segment_survey()` warns when the
records are not moving at the speed the platform you named implies, and
`diagnose_pipeline(platform = )` reports the median in knots and names the
argument that matches what it found.

## Naming

`"vessel"` is the documented spelling, because it is the `PLATFORM_KIND` level
the filter compares against — nothing is translated on the way through. `"ship"`
is accepted everywhere `"vessel"` is.
