# Restrict data to a bounding box

Keeps only the records or segments falling inside a rectangular area.

## Usage

``` r
crop_to_bbox(x, bbox, coords = c("LONGITUDE", "LATITUDE"))
```

## Arguments

- x:

  A data frame with longitude and latitude columns, an `sf` object, or a
  `distsamp_segments` object. For a `distsamp_segments` object both the
  `segments` and `points` tables are cropped, the former on its
  midpoint.

- bbox:

  Either a numeric vector with names `xmin`, `xmax`, `ymin`, `ymax`, or
  an object
  [`sf::st_bbox()`](https://r-spatial.github.io/sf/reference/st_bbox.html)
  understands.

- coords:

  Names of the longitude and latitude columns, used for plain data
  frames. Defaults to `c("LONGITUDE", "LATITUDE")`, falling back to the
  midpoint columns for a segment table.

## Value

The input, cropped, with the same class.

## Details

Replaces the `crop_data()` helper that the original scripts called but
never defined.

## Examples

``` r
path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
dat <- read_narwc(path)
#> `read_narwc()` renamed 2 columns:
#>   LAT_DD  -> LATITUDE
#>   LONG_DD -> LONGITUDE
#> All matched an exact entry in the alias table; `narwc_column_mapping()` returns this, and `quiet = TRUE` silences it.
gom <- c(xmin = -71, xmax = -66, ymin = 42, ymax = 45)
nrow(crop_to_bbox(dat, gom))
#> [1] 113
```
