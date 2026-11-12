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
  distance = c("with_group", "break_off"),
  units = c("m", "km"),
  max_gap_km = 5
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

  `"with_group"` (default) makes it no observation at all: the animals
  are added to the `NUMBER` of the on-effort sighting they were counted
  with, and the record is marked `circling_counted = FALSE` so
  [`segment_sightings()`](https://camilleross.org/distsamp/reference/segment_sightings.md)
  does not count them twice.

  `"break_off"` makes it an observation of its own on a density surface.
  Its distance is the perpendicular distance of its exact position
  (`S_LAT`/`S_LONG`) from the census line where one exists, marked
  `distance_source == "circling"`, and otherwise the great-circle
  distance from the point on the line where the aircraft broke off,
  marked `distance_source == "break_off"`.

  `break_off_distance` is computed under both, so the size of the
  disagreement is visible whichever is chosen.
  [`detection_data()`](https://camilleross.org/distsamp/reference/detection_data.md)
  excludes circling detections by default.

- units:

  Units of `distance` under `distance = "break_off"`: `"m"` (default) or
  `"km"`, matching
  [`segment_survey()`](https://camilleross.org/distsamp/reference/segment_survey.md)'s
  `distance_units`. `break_off_distance` is always metres.

- max_gap_km:

  Furthest, in km, that the on-effort group may have been seen from the
  point where the aircraft left the line. Default `5`;
  [`segment_survey()`](https://camilleross.org/distsamp/reference/segment_survey.md)
  passes `seg_length`. See "Which group".

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
attached only when an on-effort group of the same species was seen
before the break-off (see "Which group"). It is the default.

## Which group

The group circled animals are counted with is the most recent on-effort
sighting of the same species that is

- in the same line occupation (`DATE`, `FILEID`, `LEGNO3`);

- after the previous resume (`LEGSTAGE == 4`) on that line, so a group
  circled earlier cannot collect animals from a later circle; and

- within `max_gap_km` of the point where the aircraft broke off.

It may sit in an earlier segment than the circling record, because
segment boundaries are placed without regard to circling.

## Which distance

"Counted with the original on-effort group" is also a statement about
distance. `distance = "with_group"` (the default) reads it literally:
the animals *are* that group, and a group has one distance, one
detection probability and one row. The animals are added to its `NUMBER`
and no second observation is made. This is right only where the animals
really are that group or associated with it, which is what
`mode = "same_species"` tests.

`distance = "break_off"` reads the sighting as its own, with a distance
from the census line at the break-off:

- Where the record carries an exact position (`S_LAT`/`S_LONG`), that
  position is projected perpendicularly onto the census line through the
  break-off, by
  [`circling_distance()`](https://camilleross.org/distsamp/reference/circling_distance.md),
  and marked `distance_source == "circling"`. This is a perpendicular
  distance, though the position is fixed minutes after the detection.

- Otherwise it falls back to the great-circle distance from where the
  aircraft left the line to where the record was logged, marked
  `distance_source == "break_off"`. That is a straight-line distance
  from an off-effort position, not a perpendicular one. The logged
  position during a circle is the aircraft's, not the animal's, and a
  group circled twice before logging is further from the break-off than
  it ever was from the line.

`"with_group"` and `"break_off"` will not agree. Which is nearer the
truth depends on how the circle was flown, which the records do not
show. Run both and compare if it matters to your estimate;
`break_off_distance` is on every attached record under either option.

This function sets an attached record's distance itself, replacing any
`distance` it arrived with. The former option `distance = "inherit"` is
no longer accepted; naming it gives an error that explains why.

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
