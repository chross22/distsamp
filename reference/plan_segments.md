# Plan how many segments each track carries

Decides, for every continuous track, how many segments to cut and what
target length each should have. This is the planning half of the
segmentation; the cutting half is
[`cut_segments()`](https://camilleross.org/distsamp/reference/cut_segments.md).

## Usage

``` r
plan_segments(tracks, seg_length, seg_tol_frac = 0.5, seed = NULL)
```

## Arguments

- tracks:

  A tibble from
  [`track_effort()`](https://camilleross.org/distsamp/reference/track_effort.md).

- seg_length:

  Target segment length in km.

- seg_tol_frac:

  Tolerance as a fraction of `seg_length`, controlling whether a
  remainder becomes its own segment or is absorbed. Default `0.5`, so
  segments run between `0.5 * seg_length` and `1.5 * seg_length`.

- seed:

  Integer RNG seed, or `NULL` for unseeded.

## Value

A tibble with one row per planned segment: `DATE`, `new_trackno`,
`start_time`, `track_effort`, `seg_no` (position within the track), and
`tgtdist` (target length in km).

## The method

Adapted from Elizabeth Becker's `segchopr` code, which implements the
segmenting approach of Becker et al. (2010): continuous portions of
survey effort are divided into segments of approximately equal length,
sightings are assigned to the segment they fall in, and habitat
covariates are taken at each segment's mid-point. It sits within the
segmented line-transect framework of Hedley and Buckland (2004) and
Miller et al. (2013).

For a track of length `L` and a target segment length `s`:

- `L` shorter than `s` gives a single segment of length `L`.

- Otherwise `floor(L / s)` whole segments fit, leaving a remainder
  `rem = L - floor(L / s) * s`.

- If `rem` is at least the tolerance `seg_tol_frac * s`, it is large
  enough to stand on its own and becomes an extra segment.

- If `rem` is smaller than the tolerance, it is absorbed instead: one
  segment is stretched to `s + rem`.

Either way the leftover is assigned to a **randomly chosen** segment
rather than always the last one, so that the short (or long) segment is
not systematically at the end of every track. The target lengths always
sum to `L`.

## Reproducibility

The random choice makes segmentation non-deterministic. Pass a `seed` to
fix it. The RNG state of the calling session is left unchanged either
way.

## On the published record

Becker et al. (2010) is the citation the literature uses for this
approach — later papers describe their samples as "divided into
approximate 5-km segments of continuous survey effort using the approach
described by Becker et al. (2010)" (Becker et al. 2019). What the
published methods state is the target length and the use of continuous
effort; the specific handling of the leftover distance at the end of a
track — the tolerance test, and assigning the remainder to a randomly
chosen segment rather than the last one — is a property of the
`segchopr` implementation and does not appear to be described in print.
It is documented here instead, and is controlled by `seg_tol_frac`.

## References

Becker, E.A., Forney, K.A., Ferguson, M.C., Foley, D.G., Smith, R.C.,
Barlow, J. and Redfern, J.V. (2010) Comparing California Current
cetacean-habitat models developed using in situ and remotely sensed sea
surface temperature data. *Marine Ecology Progress Series* 413:163-183.
[doi:10.3354/meps08696](https://doi.org/10.3354/meps08696)

Becker, E.A., Forney, K.A., Redfern, J.V., Barlow, J., Jacox, M.G.,
Roberts, J.J. and Palacios, D.M. (2019) Predicting cetacean abundance
and distribution in a changing climate. *Diversity and Distributions*
25:626-643. [doi:10.1111/ddi.12867](https://doi.org/10.1111/ddi.12867)

Hedley, S.L. and Buckland, S.T. (2004) Spatial models for line transect
sampling. *Journal of Agricultural, Biological, and Environmental
Statistics* 9:181-199.
[doi:10.1198/1085711043578](https://doi.org/10.1198/1085711043578)

Miller, D.L., Burt, M.L., Rexstad, E.A. and Thomas, L. (2013) Spatial
models for distance sampling data: recent developments and future
directions. *Methods in Ecology and Evolution* 4:1001-1010.
[doi:10.1111/2041-210X.12105](https://doi.org/10.1111/2041-210X.12105)

## See also

[`cut_segments()`](https://camilleross.org/distsamp/reference/cut_segments.md),
[`segment_survey()`](https://camilleross.org/distsamp/reference/segment_survey.md)

## Examples

``` r
tracks <- tibble::tibble(
  DATE = as.Date("2024-04-01"), new_trackno = "1",
  track_effort = 23, start_time = 120000
)
plan_segments(tracks, seg_length = 5, seed = 1)
#> # A tibble: 5 × 6
#>   DATE       new_trackno start_time track_effort seg_no tgtdist
#>   <date>     <chr>            <dbl>        <dbl>  <int>   <dbl>
#> 1 2024-04-01 1               120000           23      1       3
#> 2 2024-04-01 1               120000           23      2       5
#> 3 2024-04-01 1               120000           23      3       5
#> 4 2024-04-01 1               120000           23      4       5
#> 5 2024-04-01 1               120000           23      5       5
```
