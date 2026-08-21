# Write segmentation results to CSV

Writes the tables from a
[`segment_survey()`](https://camilleross.org/distsamp/reference/segment_survey.md)
result to a directory. Nothing else in the package writes to disk, so
output is always something you asked for.

## Usage

``` r
write_segments(
  x,
  dir,
  prefix = "segments",
  tables = c("segments", "sightings", "detections", "tracks", "points")
)
```

## Arguments

- x:

  A `distsamp_segments` object.

- dir:

  Directory to write to. Created if it does not exist.

- prefix:

  Filename prefix. Default `"segments"`.

- tables:

  Which tables to write. Default all four.

## Value

The paths written, invisibly.

## Examples

``` r
path <- system.file("extdata", "narwc-example.csv", package = "distsamp")
segs <- segment_survey(read_narwc(path), seg_length = 5, seed = 1)
#> `read_narwc()` renamed 2 columns:
#>   LAT_DD  -> LATITUDE
#>   LONG_DD -> LONGITUDE
#> All matched an exact entry in the alias table; `narwc_column_mapping()` returns this, and `quiet = TRUE` silences it.
out <- file.path(tempdir(), "segout")
write_segments(segs, out)
list.files(out)
#> [1] "segments_detections.csv" "segments_points.csv"    
#> [3] "segments_segments.csv"   "segments_sightings.csv" 
#> [5] "segments_tracks.csv"    
```
