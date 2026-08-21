# Attach sightings made while circling to the segment they came from

A group sighted from the census track is often circled for photographs,
and the position recorded for it is the one taken during circling, off
effort. Dropping those records loses detections that genuinely arose
from on-effort search. This function attributes them back to the segment
that was in progress when the aircraft broke off.

## Usage

``` r
attach_circling_sightings(
  chopped,
  dat,
  mode = c("same_species", "all", "none"),
  distance = c("with_group", "break_off")
)
```

## Arguments

- chopped:

  Point-level segmented data from
  [`cut_segments()`](https://camilleross.org/distsamp/reference/cut_segments.md).

- dat:

  The full point-level data, including the off-effort records that
  segmentation left out, with `CIRCLE` from
  [`flag_circling()`](https://camilleross.org/distsamp/reference/flag_circling.md).

- mode:

  `"same_species"` (default), `"all"`, or `"none"`; see Details.

- distance:

  What an attached record carries.

  `"inherit"` (default) gives it the perpendicular distance of the
  on-effort group these animals were counted with, marked
  `distance_source == "circling"`. `"break_off"` gives it the measured
  great-circle distance from the point on the line where the aircraft
  broke off, marked `distance_source == "break_off"`. Both make it an
  observation of its own on a density surface.

  `"with_group"` makes it no observation at all: the animals are added
  to the `NUMBER` of the on-effort sighting they were counted with, and
  the record is marked `circling_counted = FALSE` so
  [`segment_sightings()`](https://camilleross.org/distsamp/reference/segment_sightings.md)
  does not count them twice. Nothing is inherited or constructed.

  `break_off_distance` is computed under all three, so the size of the
  disagreement is visible whichever is chosen. No option puts a circling
  record into a detection function —
  [`detection_data()`](https://camilleross.org/distsamp/reference/detection_data.md)
  excludes them all.

## Value

`chopped` with the attachable circling records appended, carrying the
`seg_id`, `seg_no`, and `seg_eff` of the segment they were attached to
and `case = "circling"`. Their `pt2pt.effort` is set to `0` so that
attaching them cannot change any segment's length.

## What the protocol says

Handbook 4.2 (event 11) sets out the CETAP rule: counted with the
original on-effort group are any further individuals *of the same
species* seen while circling that can reasonably be called associated,
plus one further unassociated group of the same species. Groups of
*other* species, not originally seen from the track-line, are new
off-effort sightings and do not belong to the segment.

`mode = "same_species"` implements that rule: a circling sighting is
attached only when the preceding segment already holds an on-effort
sighting of the same species. It is the default.

## Which distance

"Counted with the original on-effort group" is also a statement about
distance, and `distance = "inherit"` reads it as one: the animals take
that group's perpendicular distance, which was measured from the line at
the moment of break-off.

`distance = "break_off"` reads the sighting as its own: the great-circle
distance from where the aircraft left the line to where the animals were
logged. That is a real measurement of a real thing, and it is the honest
answer to "how far off the track were they" — but it is a slant distance
from an off-effort position minutes after the fact, not a perpendicular
distance, and a group circled twice before logging is further from the
break-off than it ever was from the line.

The two will not agree, and which is nearer the truth depends on how the
circle was actually flown, which the records do not record.

`distance = "with_group"` declines the question. If these animals are
counted with the original group then they *are* that group, and a group
has one distance, one detection probability and one row — so the animals
are added to its `NUMBER` and no second observation is made. That
removes the objection to inheriting, which is that a row appears
carrying a distance it was never seen at. What it does not remove is the
judgement underneath: it is right only where the animals really are that
group or associated with it, which is what `mode = "same_species"` is
testing.

Run them and compare if it matters to your estimate;
`break_off_distance` is on every attached record whichever is chosen, so
the comparison needs no re-segmentation to see the size of it.

The original processing code instead hard-coded right whales, attaching
every circling right whale and discarding circling sightings of
everything else.

## References

Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database:
A Guide for Users and Contributors, Version 8*, section 4.2 (event 11).
NARWC Reference Document 2023-01.

CETAP (1982) *A Characterization of Marine Mammals and Turtles in the
Mid- and North-Atlantic Areas of the U.S. Outer Continental Shelf, Final
Report.* Cetacean and Turtle Assessment Program, University of Rhode
Island. Bureau of Land Management, Washington, DC.

## See also

[`flag_circling()`](https://camilleross.org/distsamp/reference/flag_circling.md),
[`segment_sightings()`](https://camilleross.org/distsamp/reference/segment_sightings.md)

## Examples

``` r
path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
dat <- point_to_point_effort(flag_effort(make_leg_id(read_narwc(path))))
#> `read_narwc()` renamed 2 columns:
#>   LAT_DD  -> LATITUDE
#>   LONG_DD -> LONGITUDE
#> All matched an exact entry in the alias table; `narwc_column_mapping()` returns this, and `quiet = TRUE` silences it.
dat <- split_tracks(dat)
chopped <- cut_segments(
  plan_segments(track_effort(dat), seg_length = 5, seed = 1), dat, seed = 1
)

# Circling records are off effort, so cut_segments() left them out. This
# puts the sightings among them back onto the segment that was in progress
# when the aircraft broke off.
full <- flag_circling(dat)
with_circling <- attach_circling_sightings(chopped, full)
nrow(with_circling) - nrow(chopped)
#> [1] 1

# The CETAP same-species rule is the default; "all" ignores it
nrow(attach_circling_sightings(chopped, full, mode = "all")) - nrow(chopped)
#> [1] 1

# Attaching a record never changes a segment's length
identical(
  tapply(chopped$pt2pt.effort, chopped$seg_id, sum),
  tapply(with_circling$pt2pt.effort, with_circling$seg_id, sum)
)
#> [1] TRUE
```
