# Flag records made while circling

Marks the records where the aircraft had left the census track to circle
a sighting.

## Usage

``` r
flag_circling(dat)
```

## Arguments

- dat:

  A data frame of NARWC survey data in survey order, with `LEGTYPE` and
  ideally `LEGSTAGE` and `LEGNO3`.

## Value

`dat` with an integer `CIRCLE` column: `1` while circling, `0`
otherwise.

## Details

Two signals are used, either of which is sufficient:

- `LEGTYPE == 4`, the line-transect "other (circling)" code (handbook
  8.A.21); and

- any record between a `LEGSTAGE == 3` (break off line to circle) and
  the following `LEGSTAGE == 4` (resume line) within the same survey
  line occupation (handbook 8.A.20).

The second signal matters because a survey may log positions during
circling without changing `LEGTYPE`, and because the break-off and
resume records themselves stay at `LEGTYPE == 2`.

## References

Kenney, R.D. (2023) *The North Atlantic Right Whale Consortium Database:
A Guide for Users and Contributors, Version 8*, sections 8.A.20 and
8.A.21. NARWC Reference Document 2023-01.

## Examples

``` r
path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
dat <- flag_circling(make_leg_id(read_narwc(path)))
#> `read_narwc()` renamed 2 columns:
#>   LAT_DD  -> LATITUDE
#>   LONG_DD -> LONGITUDE
#> All matched an exact entry in the alias table; `narwc_column_mapping()` returns this, and `quiet = TRUE` silences it.
sum(dat$CIRCLE)
#> [1] 5
```
