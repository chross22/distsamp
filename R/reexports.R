#' Functions re-exported from narwcr
#'
#' Reading and standardising a NARWC extract used to live in this package. It
#' now lives in \pkg{narwcr}, which `msomgom` and any other analysis of the same
#' archive share, so that there is one vocabulary and one set of handbook code
#' books rather than one per package.
#'
#' They are re-exported here so that `library(distsamp)` still gives you a
#' working pipeline from a file to a set of segments, and so that existing code
#' and examples keep running unchanged. They are the same functions: documented,
#' tested and versioned in \pkg{narwcr}.
#'
#' @section Where each one is documented:
#' \describe{
#'   \item{Reading}{[narwcr::read_narwc()],
#'     [narwcr::standardize_narwc_columns()],
#'     [narwcr::narwc_column_mapping()]}
#'   \item{Filling}{[narwcr::fill_narwc()], [narwcr::narwc_fill_columns()],
#'     [narwcr::narwc_never_fill()]}
#'   \item{Validating}{[narwcr::narwc_checks()], [narwcr::narwc_finding()].
#'     `validate_narwc()` is *not* re-exported: this package defines its own
#'     wrapper so that [distsamp_checks()] run by default. See
#'     [validate_narwc()].}
#'   \item{Handbook code books}{[narwcr::narwc_codes()],
#'     [narwcr::narwc_schema()], [narwcr::narwc_strip_bins()],
#'     [narwcr::narwc_profiles()]}
#'   \item{Effort}{[narwcr::flag_effort()], [narwcr::visibility_ok()],
#'     [narwcr::make_leg_id()], [narwcr::on_effort_census_rows()]}
#'   \item{Cloud storage}{[narwcr::narwc_fetch()],
#'     [narwcr::narwc_cloud_roots()]}
#' }
#'
#' @name narwcr-layer
#' @keywords internal
NULL

#' @importFrom narwcr read_narwc
#' @export
narwcr::read_narwc

#' @importFrom narwcr standardize_narwc_columns
#' @export
narwcr::standardize_narwc_columns

#' @importFrom narwcr narwc_column_mapping
#' @export
narwcr::narwc_column_mapping

#' @importFrom narwcr fill_narwc
#' @export
narwcr::fill_narwc

#' @importFrom narwcr narwc_fill_columns
#' @export
narwcr::narwc_fill_columns

#' @importFrom narwcr narwc_never_fill
#' @export
narwcr::narwc_never_fill

#' @importFrom narwcr narwc_checks
#' @export
narwcr::narwc_checks

#' @importFrom narwcr narwc_finding
#' @export
narwcr::narwc_finding

#' @importFrom narwcr narwc_codes
#' @export
narwcr::narwc_codes

#' @importFrom narwcr narwc_schema
#' @export
narwcr::narwc_schema

#' @importFrom narwcr narwc_strip_bins
#' @export
narwcr::narwc_strip_bins

#' @importFrom narwcr narwc_profiles
#' @export
narwcr::narwc_profiles

#' @importFrom narwcr flag_effort
#' @export
narwcr::flag_effort

#' @importFrom narwcr visibility_ok
#' @export
narwcr::visibility_ok

#' @importFrom narwcr make_leg_id
#' @export
narwcr::make_leg_id

#' @importFrom narwcr on_effort_census_rows
#' @export
narwcr::on_effort_census_rows

#' @importFrom narwcr narwc_fetch
#' @export
narwcr::narwc_fetch

#' @importFrom narwcr narwc_cloud_roots
#' @export
narwcr::narwc_cloud_roots
