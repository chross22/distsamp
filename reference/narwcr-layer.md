# Functions re-exported from narwcr

Reading and standardising a NARWC extract used to live in this package.
It now lives in narwcr, which `msomgom` and any other analysis of the
same archive share, so that there is one vocabulary and one set of
handbook code books rather than one per package.

## Details

They are re-exported here so that
[`library(distsamp)`](https://github.com/chross22/distsamp) still gives
you a working pipeline from a file to a set of segments, and so that
existing code and examples keep running unchanged. They are the same
functions: documented, tested and versioned in narwcr.

## Where each one is documented

- Reading:

  [`narwcr::read_narwc()`](https://rdrr.io/pkg/narwcr/man/read_narwc.html),
  [`narwcr::standardize_narwc_columns()`](https://rdrr.io/pkg/narwcr/man/standardize_narwc_columns.html),
  [`narwcr::narwc_column_mapping()`](https://rdrr.io/pkg/narwcr/man/narwc_column_mapping.html)

- Filling:

  [`narwcr::fill_narwc()`](https://rdrr.io/pkg/narwcr/man/fill_narwc.html),
  [`narwcr::narwc_fill_columns()`](https://rdrr.io/pkg/narwcr/man/narwc_fill_columns.html),
  [`narwcr::narwc_never_fill()`](https://rdrr.io/pkg/narwcr/man/narwc_fill_columns.html)

- Validating:

  [`narwcr::narwc_checks()`](https://rdrr.io/pkg/narwcr/man/narwc_checks.html),
  [`narwcr::narwc_finding()`](https://rdrr.io/pkg/narwcr/man/narwc_finding.html).
  [`validate_narwc()`](https://camilleross.org/distsamp/reference/validate_narwc.md)
  is *not* re-exported: this package defines its own wrapper so that
  [`distsamp_checks()`](https://camilleross.org/distsamp/reference/distsamp_checks.md)
  run by default. See
  [`validate_narwc()`](https://camilleross.org/distsamp/reference/validate_narwc.md).

- Handbook code books:

  [`narwcr::narwc_codes()`](https://rdrr.io/pkg/narwcr/man/narwc_codes.html),
  [`narwcr::narwc_schema()`](https://rdrr.io/pkg/narwcr/man/narwc_schema.html),
  [`narwcr::narwc_strip_bins()`](https://rdrr.io/pkg/narwcr/man/narwc_strip_bins.html),
  [`narwcr::narwc_profiles()`](https://rdrr.io/pkg/narwcr/man/narwc_profiles.html)

- Effort:

  [`narwcr::flag_effort()`](https://rdrr.io/pkg/narwcr/man/flag_effort.html),
  [`narwcr::visibility_ok()`](https://rdrr.io/pkg/narwcr/man/visibility_ok.html),
  [`narwcr::make_leg_id()`](https://rdrr.io/pkg/narwcr/man/make_leg_id.html),
  [`narwcr::on_effort_census_rows()`](https://rdrr.io/pkg/narwcr/man/on_effort_census_rows.html)

- Cloud storage:

  [`narwcr::narwc_fetch()`](https://rdrr.io/pkg/narwcr/man/narwc_fetch.html),
  [`narwcr::narwc_cloud_roots()`](https://rdrr.io/pkg/narwcr/man/narwc_cloud_roots.html)
