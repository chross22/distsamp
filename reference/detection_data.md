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
  km². A single number, or one per region. Required: there is no
  sensible default, and a wrong one scales abundance directly.

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
attribute.

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
a missing `distance`. That is not padding: it is how the flatfile
records effort that produced no sightings, and dropping those rows would
inflate density by removing the denominator.

## Truncation applies to two things

`truncation` drops detections beyond the given distance — and leaves
their segment in place, with its effort intact. That is the whole point:
effort searched is effort searched whether or not anything was seen
within the truncation distance, so removing the segment as well would
remove the denominator along with the numerator and bias density upward.

Truncation is reported rather than silent. It also has to match what you
pass to `ds()`; passing `truncation` here and a different value there
fits the model to one set of detections and scales abundance by another.

## Binned distances cannot be mixed with exact ones

`STRIP` gives an interval, not a point, so those rows carry `distbegin`
and `distend` and no `distance`. A single `ds()` call cannot fit both —
the likelihoods differ — so a table containing both is a survey era
boundary rather than a model set. `mixed = "error"` (the default)
refuses it; `mixed = "warn"` lets it through for inspection. Split on
`distance_source` and fit each era separately.

The top bin of every `STRIP` scheme is open-ended (`>1`, `>2`, `>4`
nmi), so `distend` is infinite and no detection function can be fitted
to it. Those rows are dropped, and counted in the report.

## Circling detections

Excluded by default, and the reason is stronger than "the position is
off the track". A circling detection's `distance` is not measured at
all: it is inherited from the on-effort sighting these animals were
counted with, which is already a row in this table. Keeping both puts
the same perpendicular distance into the detection function twice and
weights it twice. `include_circling = TRUE` does keep them — a choice
worth stating in a methods section rather than making silently — but it
is a choice about double-counting, not about which positions are
trustworthy.

Note that this is independent of whether circling sightings count
towards abundance in a density surface model, which they should and do;
that is controlled by `segment_survey(circling = )`. Excluding them here
does not remove them from `segs$sightings` or `segs$detections`, and a
surface fitted from this flatfile alone will miss them — build its
observation table from the detections instead.

## This assumes g(0) = 1, and it almost certainly is not

Nothing in this table corrects for animals that were submerged when the
aircraft passed, or that surfaced and were missed. A detection function
fitted to it estimates detection *given that the animal was available
and seen*, and treats the track-line as certain. For a deep-diving
species that biases density low, and not slightly.

`distsamp` does not estimate `g(0)` — it cannot be estimated from a
standard NARWC extract, which records neither dive data nor the
double-observer structure mark-recapture needs — but it must not be
assumed away either. Apply a correction from external sources at the
abundance step, with its standard error propagated, and say which
components it covers.

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
#> # A tibble: 6 × 10
#>   Region.Label  Area Sample.Label Effort object distance distbegin distend  size
#>   <chr>        <dbl> <chr>         <dbl>  <int>    <dbl>     <dbl>   <dbl> <dbl>
#> 1 all           5811 2024-04-01_…   7.78      1     229         NA      NA     1
#> 2 all           5811 2024-04-01_…   5.56      2     132.        NA      NA     2
#> 3 all           5811 2024-04-01_…   5.56      3     397.        NA      NA     1
#> 4 all           5811 2024-04-01_…   5.56      4     629.        NA      NA     3
#> 5 all           5811 2024-04-01_…   3.33     NA      NA         NA      NA    NA
#> 6 all           5811 2024-04-01_…   5.56     NA      NA         NA      NA    NA
#> # ℹ 1 more variable: distance_source <chr>

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
#> # A tibble: 6 × 11
#>   Region.Label  Area Sample.Label Effort object distance distbegin distend  size
#>   <chr>        <dbl> <chr>         <dbl>  <int>    <dbl>     <dbl>   <dbl> <dbl>
#> 1 all           5811 2024-04-01_…   7.78      1     229         NA      NA     1
#> 2 all           5811 2024-04-01_…   5.56      2     132.        NA      NA     2
#> 3 all           5811 2024-04-01_…   5.56      3     397.        NA      NA     1
#> 4 all           5811 2024-04-01_…   5.56      4     629.        NA      NA     3
#> 5 all           5811 2024-04-01_…   3.33     NA      NA         NA      NA    NA
#> 6 all           5811 2024-04-01_…   5.56     NA      NA         NA      NA    NA
#> # ℹ 2 more variables: distance_source <chr>, wt_beaufort <dbl>
```
