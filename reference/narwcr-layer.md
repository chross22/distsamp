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

  [`narwcr::read_narwc()`](https://camilleross.org/narwcr/reference/read_narwc.html),
  [`narwcr::standardize_narwc_columns()`](https://camilleross.org/narwcr/reference/standardize_narwc_columns.html),
  [`narwcr::narwc_column_mapping()`](https://camilleross.org/narwcr/reference/narwc_column_mapping.html)

- Filling:

  [`narwcr::fill_narwc()`](https://camilleross.org/narwcr/reference/fill_narwc.html),
  [`narwcr::narwc_fill_columns()`](https://camilleross.org/narwcr/reference/narwc_fill_columns.html),
  [`narwcr::narwc_never_fill()`](https://camilleross.org/narwcr/reference/narwc_fill_columns.html)

- Validating:

  [`narwcr::narwc_checks()`](https://camilleross.org/narwcr/reference/narwc_checks.html),
  [`narwcr::narwc_finding()`](https://camilleross.org/narwcr/reference/narwc_finding.html).
  [`validate_narwc()`](https://camilleross.org/distsamp/reference/validate_narwc.md)
  is *not* re-exported: this package defines its own wrapper so that
  [`distsamp_checks()`](https://camilleross.org/distsamp/reference/distsamp_checks.md)
  run by default. See
  [`validate_narwc()`](https://camilleross.org/distsamp/reference/validate_narwc.md).

- Handbook code books:

  [`narwcr::narwc_codes()`](https://camilleross.org/narwcr/reference/narwc_codes.html),
  [`narwcr::narwc_schema()`](https://camilleross.org/narwcr/reference/narwc_schema.html),
  [`narwcr::narwc_strip_bins()`](https://camilleross.org/narwcr/reference/narwc_strip_bins.html),
  [`narwcr::narwc_profiles()`](https://camilleross.org/narwcr/reference/narwc_profiles.html)

- Effort:

  [`narwcr::flag_effort()`](https://camilleross.org/narwcr/reference/flag_effort.html),
  [`narwcr::visibility_ok()`](https://camilleross.org/narwcr/reference/visibility_ok.html),
  [`narwcr::make_leg_id()`](https://camilleross.org/narwcr/reference/make_leg_id.html),
  [`narwcr::on_effort_census_rows()`](https://camilleross.org/narwcr/reference/on_effort_census_rows.html)

- Cloud storage:

  [`narwcr::narwc_fetch()`](https://camilleross.org/narwcr/reference/narwc_fetch.html),
  [`narwcr::narwc_cloud_roots()`](https://camilleross.org/narwcr/reference/narwc_cloud_roots.html)
