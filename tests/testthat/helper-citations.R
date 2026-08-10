# Where the project sources live, as seen from a running test.
#
# `devtools::test()` runs from tests/testthat with the source tree two levels
# up, so `../..` finds it. `R CMD check` does not: it runs from
# `<pkg>.Rcheck/tests/testthat`, where the sources are not above the working
# directory at all but unpacked alongside it, in `00_pkg_src/<pkg>`. Without
# that last candidate every citation check skips under check - and a skipped
# test is reported the same way as a passing one, so the gap is invisible.
citation_root <- function() {
  candidates <- c(".", "..", "../..", "../../..",
                  Sys.glob("../../00_pkg_src/*"))
  for (p in candidates) {
    if (file.exists(file.path(p, "tools", "citations.csv"))) return(p)
  }
  NA_character_
}
