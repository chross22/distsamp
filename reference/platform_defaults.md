# The platforms this package can segment

`distsamp` was aerial by construction and is now aerial by default. A
shipboard survey differs in three ways that matter, and this is where
all three are written down.

## Usage

``` r
platform_defaults(platform = c("aerial", "vessel", "ship"))
```

## Arguments

- platform:

  `"aerial"` (default), `"vessel"`, or `"ship"` as a synonym for
  `"vessel"`.

## Value

A list with `platform`, `kind` (the `PLATFORM_KIND` level to keep),
`effort_args` (for
[`narwcr::flag_effort()`](https://camilleross.org/narwcr/reference/flag_effort.html)),
and `distance_sources` (for
[`sighting_distances()`](https://camilleross.org/distsamp/reference/sighting_distances.md)).

## What changes with the platform

- Effort criteria:

  The handbook's altitude ceiling (8.A.1) is an aircraft criterion, and
  it cannot be widened into one that applies to a ship — a record with
  no `ALT` fails it at any height, because a missing value fails a
  criterion, so `max_alt_m = Inf` rescues nothing. The vessel defaults
  drop it instead (`narwcr::flag_effort(max_alt_m = NULL)`). Sea state
  and visibility apply to both, and are left alone.

  How much this costs depends on the file, so measure it rather than
  assume it. Some programmes leave `ALT` empty on their vessel records
  and every one of them is excluded; others write the observer's eye
  height there, which passes an aircraft's ceiling comfortably and hides
  the problem until the records that *are* empty go missing. On one real
  extract of 1,037,180 vessel records, 338,562 had no `ALT` — 32% of the
  vessel effort, and 277 of 741 eligible sightings.

- Right-angle distance sources:

  `"angle"` is \\h/\tan\theta\\ from an aircraft altitude, and the
  `"strip"` code books are the Skymaster's and the AT-11's (8.A.31).
  Neither means anything on a vessel, so the vessel default is `"exact"`
  alone — a sighting position projected onto the track, which is
  geometry rather than platform. See
  [`sighting_distances()`](https://camilleross.org/distsamp/reference/sighting_distances.md).

- Which records are kept:

  [`narwcr::classify_platform()`](https://camilleross.org/narwcr/reference/classify_platform.html)
  labels each stretch from its median speed. The platform names the
  label to keep.

## What does not change

`LEGTYPE` 5 and 6 mark shipboard records (8.A.21), but they mark a
*platform of opportunity* — a ship that recorded what it saw while going
somewhere. That is not a designed line-transect, and counting it as
effort would put unsearched track into the denominator of a density
estimate. So the vessel defaults keep `legtype_on_effort = 2`, a
designated census line, exactly as the aerial ones do. A dedicated
shipboard line-transect survey codes its lines `LEGTYPE = 2` and needs
nothing here; a POP file is not a distance sampling dataset and no
argument to this package makes it one.

Segmentation itself is platform-free. Great-circle distance between
consecutive fixes, splitting at breaks in effort, and cutting a track
into lengths are all geometry, and a ship's track segments the same way
a plane's does.

## Naming

`"vessel"` is the documented spelling, because it is the `PLATFORM_KIND`
level the filter actually compares against — nothing is translated on
the way through. `"ship"` is accepted everywhere `"vessel"` is, and
resolves to it.

## See also

[`prepare_survey()`](https://camilleross.org/distsamp/reference/prepare_survey.md),
[`segment_survey()`](https://camilleross.org/distsamp/reference/segment_survey.md),
[`sighting_distances()`](https://camilleross.org/distsamp/reference/sighting_distances.md),
[`narwcr::classify_platform()`](https://camilleross.org/narwcr/reference/classify_platform.html)

## Examples

``` r
platform_defaults("aerial")
#> $platform
#> [1] "aerial"
#> 
#> $kind
#> [1] "aerial"
#> 
#> $effort_args
#> list()
#> 
#> $distance_sources
#> [1] "angle" "exact" "strip"
#> 

# A vessel drops the altitude ceiling and loses the aircraft distance
# sources
platform_defaults("vessel")
#> $platform
#> [1] "vessel"
#> 
#> $kind
#> [1] "vessel"
#> 
#> $effort_args
#> $effort_args$max_alt_m
#> NULL
#> 
#> 
#> $distance_sources
#> [1] "exact"
#> 

# "ship" is the same thing
identical(platform_defaults("ship"), platform_defaults("vessel"))
#> [1] TRUE
```
