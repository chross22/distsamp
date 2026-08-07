# Offline citation checks. The network-dependent half — CrossRef metadata, URL
# liveness, and the NARWC handbook version — lives in tools/check-citations.R
# and runs monthly in CI, because it cannot be part of R CMD check.

registry_path <- function() {
  for (p in c("tools/citations.csv", "../../tools/citations.csv",
              "../../../tools/citations.csv")) {
    if (file.exists(p)) return(p)
  }
  NA_character_
}

test_that("every DOI cited in the package is in the citation registry", {
  skip_if(is.na(registry_path()), "citation registry not available")

  reg <- utils::read.csv(registry_path(), stringsAsFactors = FALSE,
                         na.strings = "")
  root <- dirname(dirname(registry_path()))

  sources <- c(
    list.files(file.path(root, "R"), "\\.R$", full.names = TRUE),
    list.files(file.path(root, "docs"), "\\.md$", full.names = TRUE),
    file.path(root, c("README.md", "NEWS.md", "DESCRIPTION"))
  )
  sources <- sources[file.exists(sources)]
  skip_if(!length(sources), "package sources not available")

  text <- unlist(lapply(sources, readLines, warn = FALSE))
  found <- unlist(regmatches(
    text, gregexpr("10\\.[0-9]{4,9}/[^\\s\"'<>)\\]},;`*_]+", text, perl = TRUE)
  ))
  found <- unique(sub("[.,;:>`)\\]]+$", "", found))

  expect_setequal(
    setdiff(tolower(found), tolower(stats::na.omit(reg$doi))),
    character(0)
  )
})

test_that("the package says how to cite itself", {
  skip_if(is.na(registry_path()), "package root not available")
  root <- dirname(dirname(registry_path()))

  # inst/CITATION drives citation("distsamp"); without it R invents a poor one.
  cit <- file.path(root, "inst", "CITATION")
  expect_true(file.exists(cit))

  ver <- read.dcf(file.path(root, "DESCRIPTION"), fields = "Version")[1, 1]
  parsed <- utils::readCitationFile(
    cit, meta = list(Package = "distsamp", Version = ver)
  )
  expect_gte(length(parsed), 1)

  # The version must come from meta$Version, never be hard-coded, or it goes
  # stale the moment DESCRIPTION is bumped.
  txt <- paste(readLines(cit, warn = FALSE), collapse = " ")
  hard <- unique(unlist(regmatches(
    txt, gregexpr("[0-9]+[.][0-9]+[.][0-9]+", txt)
  )))
  expect_setequal(setdiff(hard, ver), character(0))

  # And the README has to tell people.
  rd <- paste(readLines(file.path(root, "README.md"), warn = FALSE), collapse = "\n")
  expect_match(rd, "(?i)#+\\s*citing", perl = TRUE)
})

test_that("the registry is well formed", {
  skip_if(is.na(registry_path()), "citation registry not available")
  reg <- utils::read.csv(registry_path(), stringsAsFactors = FALSE,
                         na.strings = "")

  expect_true(all(c("key", "doi", "url", "first_author", "year", "title",
                    "checks") %in% names(reg)))
  expect_false(anyDuplicated(reg$key) > 0)
  expect_false(any(is.na(reg$key)))
  expect_true(all(reg$year > 1900 & reg$year < 2100))

  # Anything asked to be checked against CrossRef needs a DOI, and anything
  # asked to be checked for liveness needs a URL.
  expect_false(any(grepl("crossref", reg$checks) & is.na(reg$doi)))
  expect_false(any(grepl("url", reg$checks) & is.na(reg$url)))
})

test_that("the handbook version cited is consistent across the package", {
  skip_if(is.na(registry_path()), "citation registry not available")
  root <- dirname(dirname(registry_path()))

  files <- c(
    list.files(file.path(root, "R"), "\\.R$", full.names = TRUE),
    file.path(root, "README.md")
  )
  files <- files[file.exists(files)]
  text <- unlist(lapply(files, readLines, warn = FALSE))

  vers <- unlist(regmatches(
    text, gregexpr("Contributors[^0-9]{0,20}Version ([0-9]+)", text)
  ))
  vers <- unique(as.integer(gsub("\\D", "", vers)))
  skip_if(!length(vers), "no handbook version strings found")

  # One version, cited the same way everywhere.
  expect_length(vers, 1)

  # And the project hooks agree with it.
  hooks <- readLines(file.path(root, "tools", "citation-hooks.R"), warn = FALSE)
  cited <- as.integer(gsub("\\D", "", grep("^cited_version <-", hooks, value = TRUE)))
  expect_equal(cited, vers)
})
