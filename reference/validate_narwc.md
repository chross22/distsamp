# Check survey data against the handbook and against distance sampling

[`narwcr::validate_narwc()`](https://rdrr.io/pkg/narwcr/man/validate_narwc.html)
with this package's checks added to the default, so that
`validate_narwc(dat)` reports everything it reported before the reading
layer was split into narwcr.

## Usage

``` r
validate_narwc(dat, checks = c(narwcr::narwc_checks(), distsamp_checks()))
```

## Arguments

- dat:

  A data frame of NARWC survey data, ideally from
  [`narwcr::read_narwc()`](https://rdrr.io/pkg/narwcr/man/read_narwc.html).

- checks:

  A named list of check functions. Defaults to the handbook-general set
  plus
  [`distsamp_checks()`](https://camilleross.org/distsamp/reference/distsamp_checks.md).

## Value

A tibble with one row per problem found, and columns:

- `check`:

  Name of the check, as listed above.

- `severity`:

  `"error"`, `"warning"`, or `"note"`.

- `column`:

  The column involved, or `NA`.

- `n`:

  Number of records affected.

- `rows`:

  List column of affected row indices (capped at 100).

- `message`:

  Human-readable description.

A zero-row tibble means every check passed.

## Why this wrapper exists

The handbook-general checks live in narwcr, and calling its
`validate_narwc()` directly runs only those. Silently dropping four
checks from a function people already call would be a regression, so
this package keeps its own default. To run only the handbook rules, call
[`narwcr::validate_narwc()`](https://rdrr.io/pkg/narwcr/man/validate_narwc.html).

## See also

[`distsamp_checks()`](https://camilleross.org/distsamp/reference/distsamp_checks.md)
for what this package adds,
[`narwcr::narwc_checks()`](https://rdrr.io/pkg/narwcr/man/narwc_checks.html)
for the handbook-general set.

## Examples

``` r
path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
issues <- validate_narwc(read_narwc(path, quiet = TRUE))
issues[, c("check", "severity", "n")]
#> # A tibble: 1 × 3
#>   check                    severity     n
#>   <chr>                    <chr>    <int>
#> 1 legstage_line_not_closed note         1

# The handbook rules on their own
narwcr::validate_narwc(read_narwc(path, quiet = TRUE))
#> # A tibble: 1 × 6
#>   check                    severity column       n rows      message            
#>   <chr>                    <chr>    <chr>    <int> <list>    <chr>              
#> 1 legstage_line_not_closed note     LEGSTAGE     1 <int [1]> A line occupation …
```
