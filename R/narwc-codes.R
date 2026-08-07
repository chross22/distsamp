#' NARWC database code books
#'
#' Lookup tables for the coded variables in the North Atlantic Right Whale
#' Consortium (NARWC) sightings database, transcribed from Kenney (2021),
#' *The North Atlantic Right Whale Consortium Database: A Guide for Users and
#' Contributors*, Version 7 (NARWC Reference Document 2021-01), Chapter 8.
#'
#' These tables are the single source of truth for the package: validation,
#' effort determination, and sighting filtering all read their permitted values
#' from here rather than hard-coding numeric literals.
#'
#' @param variable Name of a coded NARWC variable. One of `"LEGTYPE"`,
#'   `"LEGSTAGE"`, `"IDREL"`, `"TAXCODE"`, `"STRATUM"`, or `"VISIBLTY"`. If
#'   `NULL` (the default), the whole code book is returned.
#'
#' @return A named character vector mapping codes to their meanings, or, when
#'   `variable` is `NULL`, a named list of such vectors.
#'
#' @section Handbook sections:
#' `LEGTYPE` 8.A.20, `LEGSTAGE` 8.A.19, `IDREL` 8.A.15, `TAXCODE` 8.A.35,
#' `STRATUM` 8.A.29, `VISIBLTY` 8.A.37.
#'
#' @references
#' Kenney, R.D. (2021) *The North Atlantic Right Whale Consortium Database: A
#' Guide for Users and Contributors, Version 7*. North Atlantic Right Whale
#' Consortium Reference Document 2021-01. University of Rhode Island, Graduate
#' School of Oceanography, Narragansett, Rhode Island.
#'
#' @examples
#' narwc_codes("LEGSTAGE")
#' names(narwc_codes("LEGTYPE"))
#'
#' @export
narwc_codes <- function(variable = NULL) {
  if (is.null(variable)) {
    return(narwc_code_book)
  }
  variable <- toupper(variable)
  if (!variable %in% names(narwc_code_book)) {
    cli_abort_bad_arg(
      "variable", variable, names(narwc_code_book)
    )
  }
  narwc_code_book[[variable]]
}

# Handbook 8.A.20. Note that codes 0-4 describe line-transect (and "relaxed"
# line-transect) aerial surveys, 5-6 shipboard platforms-of-opportunity, and
# 7/9 aerial platforms-of-opportunity. Only LEGTYPE 2 is a census track that
# can contribute effort to a density estimate.
narwc_legtype <- c(
  "0" = "line-transect aerial, off-watch during transit, cross-leg, or circling",
  "1" = "line-transect aerial, transit",
  "2" = "line-transect aerial, survey line",
  "3" = "line-transect aerial, cross-leg",
  "4" = "line-transect aerial, other (circling)",
  "5" = "POP ship, underway",
  "6" = "POP ship, not underway",
  "7" = "POP aerial",
  "9" = "POP aerial, restricted data-recording"
)

# Handbook 8.A.19. For dedicated aerial surveys LEGSTAGE is recorded only
# during census lines (LEGTYPE == 2), with the exception of code 7.
narwc_legstage <- c(
  "1" = "begin line",
  "2" = "continue line",
  "3" = "break off line to circle",
  "4" = "resume line",
  "5" = "end line",
  "6" = "sighting by anyone other than an on-duty observer",
  "7" = "sighting detected in a vertical photograph"
)

# Handbook 8.A.15.
narwc_idrel <- c(
  "1" = "unsure / possible",
  "2" = "probable",
  "3" = "definite / sure",
  "9" = "unknown / not recorded"
)

# Handbook 8.A.35.
narwc_taxcode <- c(
  "0" = "vessel, gear, human activity, debris/pollution",
  "1" = "large cetacean",
  "2" = "medium cetacean",
  "3" = "small cetacean",
  "4" = "other marine mammal",
  "5" = "sea turtle",
  "6" = "shark",
  "7" = "other fish",
  "8" = "bird",
  "9" = "other / unknown"
)

# Handbook 8.A.29.
narwc_stratum <- c(
  "X" = "0-20 fathoms",
  "Y" = "20-50 fathoms",
  "Z" = ">50 fathoms",
  "0" = "non-stratified aerial survey block",
  "A" = "Scotian Shelf block half",
  "B" = "Scotian Shelf block half",
  "I" = "Florida, inshore",
  "O" = "Florida, offshore",
  "M" = "NLPSC year 2+, Martha's Vineyard",
  "R" = "NLPSC year 2+, Rhode Island"
)

# Handbook 8.A.37. Negative values are the pre-2004 OLDVIZ codes, folded into
# VISIBLTY during the 2021 archive update. Non-negative values are an actual
# clear-visibility distance in nautical miles.
narwc_visiblty <- c(
  "-1" = "clear visibility for at least 2 nautical miles",
  "-2" = "visibility less than 2 miles, fog",
  "-3" = "visibility less than 2 miles, haze",
  "-4" = "visibility less than 2 miles, rain",
  "-5" = "visibility less than 2 miles, snow"
)

narwc_code_book <- list(
  LEGTYPE  = narwc_legtype,
  LEGSTAGE = narwc_legstage,
  IDREL    = narwc_idrel,
  TAXCODE  = narwc_taxcode,
  STRATUM  = narwc_stratum,
  VISIBLTY = narwc_visiblty
)

#' NARWC columns recognised by distsamp
#'
#' The subset of the NARWC variable list (handbook Table 1) that this package
#' reads, together with the alternative spellings accepted on input.
#'
#' `required` names the columns without which no segmentation is possible.
#' `optional` names columns that are carried through and used when present.
#' `aliases` maps input column names onto the internal name.
#'
#' @section Coordinate naming:
#' The handbook's canonical event-position columns are `LAT_DD` and `LONG_DD`
#' (8.A.17, 8.A.21). Data extracts distributed by the NARWC database manager,
#' and the upstream Maine DMR processing, instead use `LATITUDE` and
#' `LONGITUDE`. This package standardises internally on `LATITUDE`/`LONGITUDE`
#' and accepts either spelling on input. `S_LAT`/`S_LONG` (8.A.32, 8.A.33) are
#' the *exact sighting* position and are kept distinct from the event position.
#'
#' @references
#' Kenney, R.D. (2021) *The North Atlantic Right Whale Consortium Database: A
#' Guide for Users and Contributors, Version 7*, Table 1. NARWC Reference Document
#' 2021-01.
#'
#' @return A named list with elements `required`, `optional`, and `aliases`.
#'
#' @examples
#' narwc_schema()$required
#'
#' @export
narwc_schema <- function() {
  list(
    required = c(
      "FILEID", "EVENTNO", "YEAR", "MONTH", "DAY", "TIME",
      "LATITUDE", "LONGITUDE", "LEGTYPE"
    ),
    optional = c(
      "LEGSTAGE", "LEGNO", "ALT", "BEAUFORT", "VISIBLTY", "WX", "CLOUD",
      "GLAREL", "GLARER", "SURFTEMP", "HEADING", "PLATFORM", "STRATUM",
      "BLOCK", "SPECCODE", "TAXCODE", "IDREL", "NUMBER", "NUMCALF",
      "SIGHTNO", "STRIP", "S_LAT", "S_LONG", "S_TIME", "PHOTOS",
      "DDSOURCE", "IDSOURCE"
    ),
    aliases = c(
      LAT_DD    = "LATITUDE",
      LONG_DD   = "LONGITUDE",
      LON_DD    = "LONGITUDE",
      LATDD     = "LATITUDE",
      LONGDD    = "LONGITUDE",
      LAT       = "LATITUDE",
      LON       = "LONGITUDE",
      LONG      = "LONGITUDE",
      LEGTYPE_BK = "LEGTYPE",
      VISIBILITY = "VISIBLTY",
      VISIBLITY  = "VISIBLTY",
      SPECIES    = "SPECCODE",
      EVENT      = "EVENTNO",
      YR         = "YEAR",
      MO         = "MONTH"
    )
  )
}

# Columns that are numeric in the NARWC schema. Everything else recognised is
# read as character.
narwc_numeric_columns <- c(
  "EVENTNO", "YEAR", "MONTH", "DAY", "TIME", "LATITUDE", "LONGITUDE",
  "LEGTYPE", "LEGSTAGE", "LEGNO", "ALT", "BEAUFORT", "VISIBLTY", "CLOUD",
  "GLAREL", "GLARER", "SURFTEMP", "HEADING", "PLATFORM", "TAXCODE", "IDREL",
  "NUMBER", "NUMCALF", "SIGHTNO", "STRIP", "S_LAT", "S_LONG", "S_TIME",
  "PHOTOS"
)
