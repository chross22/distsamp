# Perpendicular distances for sightings made while circling

A group spotted from the census track is often circled for photographs,
identification, and a proper count, and the sighting is logged during
that circle rather than at the moment of detection. This ties each such
sighting back to the point on the track-line where the aircraft broke
off, and measures the distance from there.

## Usage

``` r
circling_distance(
  dat,
  by = NULL,
  units = c("m", "km", "nmi"),
  position = c("exact", "logged")
)
```

## Arguments

- dat:

  A data frame of NARWC survey data in survey order, with `LATITUDE`,
  `LONGITUDE`, `LEGTYPE`, and ideally `CIRCLE` from
  [`flag_circling()`](https://camilleross.org/distsamp/reference/flag_circling.md)
  and `S_LAT`/`S_LONG`. Without `CIRCLE`, `LEGTYPE == 4` is used.

- by:

  Grouping columns identifying one occupation of a survey line, as in
  [`track_bearing()`](https://camilleross.org/distsamp/reference/track_bearing.md).

- units:

  `"m"` (default), `"km"`, or `"nmi"`.

- position:

  Which position to treat as the animal's. `"exact"` (default) uses
  `S_LAT`/`S_LONG` only. `"logged"` falls back to the record's own
  `LATITUDE`/`LONGITUDE` where no exact position exists — but that is
  the *aircraft* orbiting the animal, offset by the radius of the
  circle, which at a few hundred metres is the same size as the
  distances being measured. Use it knowing that, and read
  `position_source` to see which applied.

## Value

A tibble with one row per row of `dat`, populated only for circling
sightings:

- `distance`:

  Perpendicular distance from the census line.

- `along`:

  Signed along-track distance from the break-off point to where the
  animal was abeam; negative means back down the line.

- `side`:

  `"left"`, `"right"`, `"on-track"`, or `NA`.

- `radial`:

  Straight-line distance from the break-off point.

- `bearing`:

  Inbound track bearing at the anchor.

- `anchor_event`:

  `EVENTNO` of the anchor record, or its row number when `EVENTNO` is
  absent.

- `position_source`:

  `"exact"` or `"logged"`.

## Why these detections matter

A circling sighting is usually a genuine on-effort detection: the animal
was seen from the track-line, which is why the aircraft left it. Giving
it no distance drops it from the detection function altogether, and the
dropped detections are not a random sample — they are disproportionately
the close, conspicuous, or high-priority groups that were worth breaking
off for. Losing those thins the near-zero end of the distance
distribution, exactly where a detection function is most sensitive.

## The anchor

The reference point is the last census record before the circling began
— the `LEGSTAGE == 3` break-off record where one exists (handbook
8.A.20), and otherwise the last record still on the line. `anchor_event`
reports which record was used so the choice can be checked.

The bearing is the *inbound* heading: from the previous distinct census
position to the anchor, which is the direction the aircraft was flying
when the animal was detected. It is deliberately not the centred
difference
[`track_bearing()`](https://camilleross.org/distsamp/reference/track_bearing.md)
uses, because the record after a break-off is the resume record, and a
resume point offset from the break-off would swing the bearing by an
amount that has nothing to do with the track being flown.

## Break-off point, or the line through it

The aircraft usually flies past a group before turning, so the break-off
point is beyond the animal rather than abeam of it. `radial` is the
straight-line distance from the break-off point to the animal;
`distance` is that position projected perpendicularly onto the census
line, and `along` is how far back along the line the animal was abeam.
**`distance` is the one a detection function needs** — `radial` will
generally be larger, by exactly the margin `along` records.

## What this cannot fix

The position is recorded some minutes after detection, so the animal has
moved, and the distance is an estimate of where it was when detected
rather than a measurement of it. That error is not quantified here.
Treat circling distances as a distinct and less reliable source — which
is why `distance_source` marks them, and why they should be excluded
from a detection function unless their inclusion is a deliberate, stated
choice.

## References

Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database:
A Guide for Users and Contributors, Version 8*, sections 4.2 (event 12),
8.A.20, and 8.A.21. NARWC Reference Document 2023-01.

## See also

[`flag_circling()`](https://camilleross.org/distsamp/reference/flag_circling.md),
[`attach_circling_sightings()`](https://camilleross.org/distsamp/reference/attach_circling_sightings.md),
[`cross_track_distance()`](https://camilleross.org/distsamp/reference/cross_track_distance.md),
[`exact_distance()`](https://camilleross.org/distsamp/reference/exact_distance.md)

## Examples

``` r
path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
dat <- flag_circling(make_leg_id(read_narwc(path)))
#> `read_narwc()` renamed 2 columns:
#>   LAT_DD  -> LATITUDE
#>   LONG_DD -> LONGITUDE
#> All matched an exact entry in the alias table; `narwc_column_mapping()` returns this, and `quiet = TRUE` silences it.
d <- circling_distance(dat)
d[!is.na(d$distance), ]
#> # A tibble: 1 × 7
#>   distance along side  radial bearing anchor_event position_source
#>      <dbl> <dbl> <chr>  <dbl>   <dbl>        <dbl> <chr>          
#> 1     250. -400. right   472.       0           39 exact          
```
