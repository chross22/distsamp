# The DOI scanner in tools/citation-checks.R.
#
# It is the one part of the shared engine that parses free text. Everything
# else reads the registry, where the fields have already been separated for it.
# That makes the scanner the only piece that can quietly go wrong: a matcher
# too loose reports a healthy repository whatever the state of its references,
# which is worse than not running the check at all, and one too tight fails on
# a reference that is perfectly fine.
#
# These moved here from taupatch, where they covered the bespoke checker this
# engine replaced. They are written against `cc_scan_dois()` itself rather than
# against a copy of its regex, so they cannot drift from what CI runs.

engine <- function() {
  root <- citation_root()
  skip_if(is.na(root), "project sources not available")

  path <- file.path(root, "tools", "citation-checks.R")
  skip_if_not(file.exists(path), "citation-checks.R not in this build")

  # `sys.source()` takes the definitions without running anything: the file is
  # all function definitions, and the driver lives in tools/check-citations.R.
  env <- new.env()
  sys.source(path, envir = env)
  env
}

# The scanner reads files, so give it one.
scan_text <- function(env, text) {
  f <- tempfile(fileext = ".md")
  on.exit(unlink(f), add = TRUE)
  writeLines(text, f)
  env$cc_scan_dois(f)
}

test_that("DOIs are found in every style the docs write them in", {
  env <- engine()

  text <- paste(
    "markdown: [doi:10.3354/meps14204](https://doi.org/10.3354/meps14204).",
    "roxygen: \\doi{10.1093/biomet/87.4.954}",
    "bare in a bibentry: doi = \"10.1214/aos/1013203451\",",
    "dataset: \\doi{10.48670/moi-00021}",
    sep = "\n"
  )

  expect_setequal(
    scan_text(env, text),
    c("10.3354/meps14204", "10.1093/biomet/87.4.954",
      "10.1214/aos/1013203451", "10.48670/moi-00021")
  )
})

test_that("trailing punctuation is not read as part of the identifier", {
  env <- engine()

  # A DOI inside a roxygen macro, and one closing a parenthesis and a sentence.
  # Each closing character belongs to the prose, not the identifier.
  expect_equal(scan_text(env, "see \\doi{10.1214/ss/1177013604}"),
               "10.1214/ss/1177013604")
  expect_equal(scan_text(env, "(https://doi.org/10.1023/A:1010933404324)."),
               "10.1023/A:1010933404324")
})

test_that("a citation template is not counted as a citation", {
  env <- engine()

  # Documentation shows readers how to cite a dataset as well as citing it.
  # The placeholder is not a reference, and registering it would be impossible:
  # it resolves nowhere. Only the real DOI on the second line should be found.
  text <- paste(
    "Cite as: DOI: 10.48670/moi-xxxxx (Accessed on DD MMM YYYY)",
    "We used \\doi{10.48670/moi-00021}.",
    sep = "\n"
  )

  expect_equal(scan_text(env, text), "10.48670/moi-00021")
})
