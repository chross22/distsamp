# How much of the survey was re-flown

Counts lines that took more than one attempt, and reports the rate two
ways because they are different numbers and the distinction matters.

## Usage

``` r
reflight_summary(x)
```

## Arguments

- x:

  Point-level survey data, or a `distsamp_segments`; as
  [`line_effort()`](https://camilleross.org/distsamp/reference/line_effort.md).

## Value

A one-row tibble: `n_lines`, `n_occupations`, `n_lines_reflown`,
`prop_lines_reflown`, `prop_occupations_repeat`, `effort_km`,
`effort_km_repeat`.

## Two rates, deliberately both

Suppose ten occupations covered eight lines, because two lines were
flown twice.

- `prop_lines_reflown` is 2/8 = 0.25 — a quarter of the lines needed a
  second attempt. This is what "what fraction of lines were re-flown"
  asks.

- `prop_occupations_repeat` is 2/10 = 0.20 — a fifth of the flying was a
  repeat of something already attempted. This is the one that bears on
  effort.

The scripts this package was rewritten from computed the second and
labelled it the first (`ds_data_dmr.R:229`, carrying the comment "ask
dan about this"). Both are reported here, named for what they measure,
so neither can stand in for the other by accident.

## See also

[`line_effort()`](https://camilleross.org/distsamp/reference/line_effort.md)

## Examples

``` r
path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
dat <- point_to_point_effort(flag_effort(make_leg_id(read_narwc(path))))
#> `read_narwc()` renamed 2 columns:
#>   LAT_DD  -> LATITUDE
#>   LONG_DD -> LONGITUDE
#> All matched an exact entry in the alias table; `narwc_column_mapping()` returns this, and `quiet = TRUE` silences it.
reflight_summary(dat)
#> # A tibble: 1 × 7
#>   n_lines n_occupations n_lines_reflown prop_lines_reflown
#>     <int>         <int>           <int>              <dbl>
#> 1       5             6               1                0.2
#> # ℹ 3 more variables: prop_occupations_repeat <dbl>, effort_km <dbl>,
#> #   effort_km_repeat <dbl>
```
