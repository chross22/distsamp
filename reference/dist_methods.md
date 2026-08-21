# Distance methods available

The method names
[`gc_distance()`](https://camilleross.org/distsamp/reference/gc_distance.md)
and
[`segment_survey()`](https://camilleross.org/distsamp/reference/segment_survey.md)
accept, and what each one means.

## Usage

``` r
dist_methods()
```

## Value

A tibble with columns `method`, `aliases`, and `description`.

## References

Kenney, R.D. and Winn, H.E. (1986) Cetacean high-use habitats of the
northeast United States continental shelf. *Fishery Bulletin*
84(2):345-357.

Sinnott, R.W. (1984) Virtues of the haversine. *Sky and Telescope*
68(2):159.

## Examples

``` r
dist_methods()
#> # A tibble: 3 × 3
#>   method    aliases description                                                 
#>   <chr>     <chr>   <chr>                                                       
#> 1 haversine ""      Haversine on a 111.12 km/degree sphere; stable at short ran…
#> 2 becker    "eab"   Becker's segchopr fn.grcirclkm: spherical law of cosines, 6…
#> 3 kenney    "rdk"   Kenney and Winn (1986): spherical law of cosines, 111.12 km…
```
