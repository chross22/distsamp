# Convert STRIP codes to distance intervals

Resolves each `STRIP` code to the right-angle distance interval it
stands for, and the side of the track it was on.

## Usage

``` r
strip_distance(
  strip,
  platform = c("skymaster", "at-11"),
  scheme = c("auto", "cetap", "nlpsc"),
  date = NULL,
  units = c("m", "km", "nmi"),
  left_truncation = FALSE
)
```

## Arguments

- strip:

  Integer vector of `STRIP` codes.

- platform:

  `"skymaster"` (default) or `"at-11"`.

- scheme:

  `"auto"`, `"cetap"`, or `"nlpsc"`.

- date:

  Vector of survey dates, used when `scheme = "auto"`.

- units:

  `"m"` (default), `"km"`, or `"nmi"`.

- left_truncation:

  Apply the Skymaster blind-spot offset? Default `FALSE`.

## Value

A tibble with one row per input: `distbegin`, `distend`, `side`,
`scheme`.

## Choosing the scheme

With `scheme = "auto"` (the default) the scheme is chosen from `date`:
the NLPSC / Mass CEC breakpoints for October 2011 onwards, the CETAP
ones before. That is a reasonable default but not a guarantee — a survey
flown after 2011 under the older protocol would be misread — so pass
`scheme` explicitly when you know which applies. With no `date` and no
`scheme`, this errors rather than guess.

## The Skymaster blind spot

Handbook 8.A.31 notes that the Skymaster's restricted downward
visibility means CETAP-era distances from that aircraft "are actually
measured from about 1/8 mile to either side of the survey line". The
strip boundaries do not record this, so distances near zero are not what
they appear: the region under the aircraft was never searched. Set
`left_truncation = TRUE` to shift the innermost bins accordingly, and
see
[`detection_data()`](https://camilleross.org/distsamp/reference/detection_data.md)
(not yet implemented) for fitting with a left truncation, which is the
statistically correct treatment.

## See also

[`narwc_strip_bins()`](https://rdrr.io/pkg/narwcr/man/narwc_strip_bins.html),
[`sighting_distances()`](https://camilleross.org/distsamp/reference/sighting_distances.md)

## Examples

``` r
strip_distance(c(5, 6, 13), scheme = "nlpsc")
#> # A tibble: 3 × 4
#>   distbegin distend side  scheme
#>       <dbl>   <dbl> <chr> <chr> 
#> 1       463     926 left  nlpsc 
#> 2       463     926 right nlpsc 
#> 3      7408     Inf left  nlpsc 

# Same codes, different era, different distances
strip_distance(c(5, 6, 13), scheme = "cetap")
#> # A tibble: 3 × 4
#>   distbegin distend side  scheme
#>       <dbl>   <dbl> <chr> <chr> 
#> 1      232.     463 left  cetap 
#> 2      232.     463 right cetap 
#> 3     1852     3704 left  cetap 
```
