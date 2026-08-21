# Split survey lines at breaks in effort

Assigns `new_trackno`, an identifier for each stretch of *continuous*
effort. These stretches, not the designated survey lines, are what get
chopped into segments.

## Usage

``` r
split_tracks(dat)
```

## Arguments

- dat:

  A data frame with `LEGNO3` (see
  [`make_leg_id()`](https://rdrr.io/pkg/narwcr/man/make_leg_id.html)),
  `OnOff.Effort` (see
  [`flag_effort()`](https://rdrr.io/pkg/narwcr/man/flag_effort.html)),
  and `DATE`, in survey order.

## Value

`dat` with a character `new_trackno` column added.

## The rule

Walking through a survey day's records in order, a new track begins when
either

- the line occupation changes (`LEGNO3` differs from the previous
  record), or

- effort breaks — this record and the next are both off effort.

Otherwise the record continues the current track. A *single* off-effort
record between two on-effort ones is not treated as a break, so a
momentary excursion logged as one point does not fragment the track,
while a sustained break — circling for photographs, transiting around
fog — does. This is the rule from the original `create_new_track_nos()`.

A sustained break yields three tracks, not two: the effort before it,
the break itself, and the effort after. The middle one carries no effort
and is dropped by
[`track_effort()`](https://camilleross.org/distsamp/reference/track_effort.md).
The original incremented the track number on *every* record of a break,
so a five-record circling excursion produced four spurious tracks and
left the first two off-effort records attached to the track that resumed
afterwards. Grouping the break into one track leaves each on-effort
track containing only on-effort records.

One consequence is worth knowing: a circling excursion logged as a
single record (as in handbook Figure 2, event 13) does **not** split the
track, because the record after it is back on effort. Computer-logged
surveys record many positions while circling, so in modern data the
break is seen and the track does split.

Track numbers restart at 1 on each survey date.

## References

Becker, E.A., Forney, K.A., Ferguson, M.C., Foley, D.G., Smith, R.C.,
Barlow, J. and Redfern, J.V. (2010) Comparing California Current
cetacean-habitat models developed using in situ and remotely sensed sea
surface temperature data. *Marine Ecology Progress Series* 413:163-183.
[doi:10.3354/meps08696](https://doi.org/10.3354/meps08696)

## See also

[`make_leg_id()`](https://rdrr.io/pkg/narwcr/man/make_leg_id.html),
[`flag_effort()`](https://rdrr.io/pkg/narwcr/man/flag_effort.html),
[`segment_survey()`](https://camilleross.org/distsamp/reference/segment_survey.md)

## Examples

``` r
path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
dat <- split_tracks(flag_effort(make_leg_id(read_narwc(path))))
#> `read_narwc()` renamed 2 columns:
#>   LAT_DD  -> LATITUDE
#>   LONG_DD -> LONGITUDE
#> All matched an exact entry in the alias table; `narwc_column_mapping()` returns this, and `quiet = TRUE` silences it.
table(dat$DATE, dat$new_trackno)
#>             
#>               1  2  3  4  5  6
#>   2024-04-01  3 26  2 11  5  9
#>   2024-04-02 34  4  2  8  9  0
```
