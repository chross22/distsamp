# Accumulate point-to-point survey effort

Computes the along-track distance from each record to the next within a
survey line, counting only the intervals where the aircraft was on
effort at both ends.

## Usage

``` r
point_to_point_effort(
  dat,
  by = c("DATE", "FILEID", "LEGNO3"),
  method = c("haversine", "becker", "kenney", "eab", "rdk"),
  source = c("computed", "recorded")
)
```

## Arguments

- dat:

  A data frame with `LATITUDE`, `LONGITUDE`, `OnOff.Effort`, and the
  grouping columns named in `by`. Records must already be in survey
  order;
  [`read_narwc()`](https://rdrr.io/pkg/narwcr/man/read_narwc.html) does
  not sort, so sort by `DATE`/`FILEID`/`EVENTNO` beforehand if you are
  unsure.

- by:

  Character vector of columns identifying a continuous survey line.
  Defaults to `c("DATE", "FILEID", "LEGNO3")`, the line-occupation
  identifier produced by
  [`make_leg_id()`](https://rdrr.io/pkg/narwcr/man/make_leg_id.html),
  qualified by the survey day.

  `DATE` is in the default because `LEGNO3` only increments when `LEGNO`
  *changes*. If the last line of one day and the first line of the next
  share a `LEGNO`, the two occupations differ in nothing but `FILEID` —
  and some extracts carry a constant `FILEID`, in which case the days
  merge and the ferry between them is counted as on-effort track. That
  failure is silent: no warning, no `NA`, just an effort total that can
  be many times too large, and since effort is the denominator of
  density, a density proportionally too low. Drop `DATE` only for a
  frame you know occupies a single day.

- method:

  Distance method passed to
  [`gc_distance()`](https://camilleross.org/distsamp/reference/gc_distance.md):
  `"haversine"` (default), `"becker"`, or `"kenney"`. Ignored when
  `source = "recorded"`.

- source:

  Where the distance for each interval comes from. `"computed"`
  (default) is the great circle between consecutive positions.
  `"recorded"` uses `TRKDIST`, the distance the receiver itself measured
  since the previous fix, in metres.

  `"recorded"` is the better measure where it exists. The handbook makes
  the point itself (8.A.10): the farther apart the fixes, the less a
  straight line between them reconstructs the track that was actually
  flown. A computed distance is a chord; the recorded one followed the
  aircraft. The two agree closely on a straight line and diverge on a
  turn, so a large gap between them is a sign of coarse fixes rather
  than of an error.

  `TRKDIST` measures *back* to the previous fix, and effort is
  attributed forward to the first record of a pair, so the interval
  takes the next record's reading. Off-effort endpoints and line
  boundaries are handled exactly as for `"computed"`, which means a
  reading that spans the ferry between two lines is discarded rather
  than counted.

## Value

`dat` with two columns added or replaced:

- `pt2pt.effort`:

  Distance in km from this record to the next on-effort record within
  the same line; `0` at line ends and across off-effort gaps.

- `Effort`:

  Total on-effort distance of the line this record belongs to, repeated
  on every record of the line.

## Details

Effort is attributed to the *first* record of each pair, so the last
record of a line has `pt2pt.effort` of `0`. Intervals with an off-effort
endpoint are `0` rather than `NA`, so that segment effort sums are well
defined without needing `na.rm`.

## References

Kenney, R.D. and Winn, H.E. (1986) Cetacean high-use habitats of the
northeast United States continental shelf. *Fishery Bulletin*
84(2):345-357. Effort is accumulated here as they describe it: "for any
pair of successive positions, the length of track line between the
points" summed over the qualifying records.

## See also

[`gc_distance()`](https://camilleross.org/distsamp/reference/gc_distance.md),
[`make_leg_id()`](https://rdrr.io/pkg/narwcr/man/make_leg_id.html)

## Examples

``` r
path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
dat <- flag_effort(make_leg_id(read_narwc(path)))
#> `read_narwc()` renamed 2 columns:
#>   LAT_DD  -> LATITUDE
#>   LONG_DD -> LONGITUDE
#> All matched an exact entry in the alias table; `narwc_column_mapping()` returns this, and `quiet = TRUE` silences it.
dat <- point_to_point_effort(dat)
sum(dat$pt2pt.effort)
#> [1] 92.2296
```
