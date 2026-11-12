# Build a flatfile for `Distance::ds()`

Assembles segments and detections into the single "flatfile" data frame
the `Distance` package accepts directly, with effort, area, and region
alongside each distance.

## Usage

``` r
detection_data(
  x,
  area,
  region = NULL,
  truncation = NULL,
  include_circling = FALSE,
  covariates = character(),
  mixed = c("error", "warn"),
  quiet = FALSE
)
```

## Arguments

- x:

  A `distsamp_segments` object from
  [`segment_survey()`](https://camilleross.org/distsamp/reference/segment_survey.md).

- area:

  Study area, in the units your density estimate should use — usually
  km². A single number, or a vector named by region label
  (`c(GOM = 5811, CCB = 1500)`). Required: there is no sensible default,
  and a wrong one scales abundance directly.

- region:

  Region labels, one per segment, or a single string. `NULL` (default)
  uses the `STRATUM` column if the segments carry one, and otherwise
  puts everything in one region called `"all"`.

- truncation:

  Drop detections beyond this distance, in the same units as
  `x$settings$distance_units`. `NULL` (default) keeps everything.

- include_circling:

  Keep detections logged while circling. Default `FALSE`.

- covariates:

  Character vector of segment columns to carry onto every row, for
  detection-function covariates. `wt_beaufort` is usually the one you
  want.

- mixed:

  What to do when point and interval distances both appear: `"error"`
  (default) or `"warn"`.

- quiet:

  Suppress the report of what was dropped. Default `FALSE`.

## Value

A tibble in `Distance` flatfile shape, with a `distance_units`
attribute. It has a `distance` column for exact distances, or
`distbegin`/`distend` for binned ones, never both:
[`Distance::ds()`](https://rdrr.io/pkg/Distance/man/ds.html) treats the
presence of the bin columns as binned data.

## The shape

`Distance` accepts one table carrying both the sampling units and the
detections, keyed by `Sample.Label`:

|                        |                                           |
|------------------------|-------------------------------------------|
| column                 | from                                      |
| `Region.Label`         | `region`, or the `STRATUM` column         |
| `Area`                 | the `area` argument                       |
| `Sample.Label`         | `seg_id`                                  |
| `Effort`               | `seg_eff`                                 |
| `object`               | one id per detection                      |
| `distance`             | the resolved right-angle distance         |
| `distbegin`, `distend` | interval bounds, for `STRIP`-derived rows |
| `size`                 | group size                                |

**Every segment appears, including those with no detections**, carrying
a missing `distance`. This is how the flatfile records effort that
produced no sightings. Dropping those rows would remove effort from the
denominator and inflate density.

## Truncation applies to two things

`truncation` drops detections beyond the given distance, and leaves
their segment in place with its effort intact. The effort was searched
whether or not anything was seen within the truncation distance.
Removing the segment too would remove effort from the denominator and
bias density upward.

The number of truncated detections is reported. The value must match the
truncation passed to [`ds()`](https://rdrr.io/pkg/Distance/man/ds.html);
otherwise the model is fitted to one set of detections and abundance is
scaled by another.

## Binned distances cannot be mixed with exact ones

`STRIP` gives an interval, not a point, so those rows carry `distbegin`
and `distend` and no `distance`. A single
[`ds()`](https://rdrr.io/pkg/Distance/man/ds.html) call cannot fit both,
because the likelihoods differ. A table containing both spans a survey
era boundary. `mixed = "error"` (the default) refuses it;
`mixed = "warn"` lets it through for inspection. Split on
`distance_source` and fit each era separately.

The top bin of every `STRIP` scheme is open-ended (`>1`, `>2`, `>4`
nmi), so `distend` is infinite and no detection function can be fitted
to it. Those rows are dropped, and counted in the report.

## Circling detections

Excluded by default. Under the default
`segment_survey(circling_distance = "with_group")` there are none to
exclude: the animals were added to the on-effort group they were counted
with, which is already a row here. Under `"break_off"` a circling
detection's `distance` is either a perpendicular distance from a
position fixed minutes after the detection
(`distance_source == "circling"`), or, with no exact position, a
great-circle distance from the break-off that is not perpendicular at
all (`"break_off"`). Neither is measured at the moment of detection.
`include_circling = TRUE` keeps them; state that choice in the methods.

This is independent of whether circling sightings count towards
abundance in a density surface model, which is controlled by
`segment_survey(circling = )`. Excluding them here does not remove them
from `segs$sightings` or `segs$detections`. A surface fitted from this
flatfile alone will miss them; build its observation table from the
detections instead.

## This assumes g(0) = 1, and it almost certainly is not

Nothing in this table corrects for animals that were submerged when the
aircraft passed, or that surfaced and were missed. A detection function
fitted to it treats detection on the track-line as certain. For a
deep-diving species this biases density low, by a large amount.

`distsamp` does not estimate `g(0)`. It cannot be estimated from a
standard NARWC extract, which records neither dive data nor the
double-observer structure mark-recapture needs. Apply a correction from
external sources at the abundance step, propagate its standard error,
and state which components it covers.

## References

Miller, D.L., Rexstad, E., Thomas, L., Marshall, L. and Laake, J.L.
(2019) Distance sampling in R. *Journal of Statistical Software*
89(1):1-28.
[doi:10.18637/jss.v089.i01](https://doi.org/10.18637/jss.v089.i01)

Buckland, S.T., Anderson, D.R., Burnham, K.P., Laake, J.L., Borchers,
D.L. and Thomas, L. (2001) *Introduction to Distance Sampling.* Oxford
University Press.

## See also

[`sighting_distances()`](https://camilleross.org/distsamp/reference/sighting_distances.md)
for where the distances come from,
[`segment_survey()`](https://camilleross.org/distsamp/reference/segment_survey.md),
[`segments_wide()`](https://camilleross.org/distsamp/reference/segments_wide.md)
for the density-surface side.

## Examples

``` r
path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
segs <- segment_survey(read_narwc(path), seg_length = 5, seed = 1)
#> `read_narwc()` renamed 2 columns:
#>   LAT_DD  -> LATITUDE
#>   LONG_DD -> LONGITUDE
#> All matched an exact entry in the alias table; `narwc_column_mapping()` returns this, and `quiet = TRUE` silences it.

# Area is required and is yours to supply - it scales abundance directly
flat <- detection_data(segs, area = 5811)
#> `detection_data()`: 20 segments, 8 detections (m).
#>   g(0) = 1 is assumed; see `?detection_data`.
head(flat)
#> # A tibble: 6 × 8
#>   Region.Label  Area Sample.Label   Effort object distance  size distance_source
#>   <chr>        <dbl> <chr>           <dbl>  <int>    <dbl> <dbl> <chr>          
#> 1 all           5811 2024-04-01_2_1   7.78      1     229      1 angle          
#> 2 all           5811 2024-04-01_2_2   5.56      2     132.     2 angle          
#> 3 all           5811 2024-04-01_2_2   5.56      3     397.     1 angle          
#> 4 all           5811 2024-04-01_2_2   5.56      4     629.     3 angle          
#> 5 all           5811 2024-04-01_2_3   3.33     NA      NA     NA NA             
#> 6 all           5811 2024-04-01_2_4   5.56     NA      NA     NA NA             

# Segments with no detections are kept, carrying their effort
sum(is.na(flat$distance))
#> [1] 15

# Truncation drops detections but never the effort that searched for them
nrow(detection_data(segs, area = 5811, truncation = 500))
#> `detection_data()`: 20 segments, 6 detections (m).
#>   dropped 2 beyond the truncation distance; their segments keep their effort
#>   g(0) = 1 is assumed; see `?detection_data`.
#> [1] 21

# With a detection covariate
head(detection_data(segs, area = 5811, covariates = "wt_beaufort"))
#> `detection_data()`: 20 segments, 8 detections (m).
#>   g(0) = 1 is assumed; see `?detection_data`.
#> # A tibble: 6 × 9
#>   Region.Label  Area Sample.Label   Effort object distance  size distance_source
#>   <chr>        <dbl> <chr>           <dbl>  <int>    <dbl> <dbl> <chr>          
#> 1 all           5811 2024-04-01_2_1   7.78      1     229      1 angle          
#> 2 all           5811 2024-04-01_2_2   5.56      2     132.     2 angle          
#> 3 all           5811 2024-04-01_2_2   5.56      3     397.     1 angle          
#> 4 all           5811 2024-04-01_2_2   5.56      4     629.     3 angle          
#> 5 all           5811 2024-04-01_2_3   3.33     NA      NA     NA NA             
#> 6 all           5811 2024-04-01_2_4   5.56     NA      NA     NA NA             
#> # ℹ 1 more variable: wt_beaufort <dbl>
```
