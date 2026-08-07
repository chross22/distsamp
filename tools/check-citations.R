#!/usr/bin/env Rscript
#
# Check that the citations in this package are still correct and current.
#
#   Rscript tools/check-citations.R
#
# Runs four checks:
#
#   1. Registry coverage - every DOI appearing anywhere in the package is
#      listed in tools/citations.csv, and every registry DOI is actually used.
#      Offline.
#   2. CrossRef metadata - for each registry entry with a DOI, the first
#      author, year, title, journal, and volume still match what we print.
#      Catches a citation we transcribed wrongly, and a paper that was
#      subsequently corrected.
#   3. URL liveness - registry URLs still resolve.
#   4. NARWC handbook version - the Consortium's sightings-database page still
#      offers the version we cite. This is the check most likely to fire:
#      Kenney revises the handbook every year or two, and a new version can
#      change variable definitions the package depends on.
#
# Exits 1 if any check fails, so it can gate CI.

suppressPackageStartupMessages({
  ok <- requireNamespace("jsonlite", quietly = TRUE)
})
if (!ok) {
  stop("This script needs the `jsonlite` package: install.packages(\"jsonlite\")")
}

# Run from the package root, or from tools/.
root <- if (file.exists(file.path(".", "DESCRIPTION"))) {
  "."
} else if (file.exists(file.path("..", "DESCRIPTION"))) {
  ".."
} else {
  stop("Run this from the package root: Rscript tools/check-citations.R")
}

failures <- character()
notes <- character()

fail <- function(...) failures <<- c(failures, paste0(...))
note <- function(...) notes <<- c(notes, paste0(...))

say <- function(...) cat(..., "\n", sep = "")
rule <- function(title) say("\n== ", title, " ", strrep("=", max(0, 60 - nchar(title))))

`%||%` <- function(x, y) if (is.null(x)) y else x

# Normalise a title or journal name for comparison: lowercase, strip markup,
# collapse punctuation and whitespace. Publishers are inconsistent about
# en-dashes, italics markup, and trailing periods.
norm <- function(x) {
  x <- tolower(as.character(x))
  x <- gsub("<[^>]+>", " ", x)          # HTML/JATS markup in CrossRef titles
  x <- gsub("[‐-―]", "-", x)  # dash variants
  x <- gsub("&amp;", "&", x, fixed = TRUE)
  x <- gsub("[^a-z0-9]+", " ", x)
  trimws(gsub("\\s+", " ", x))
}

registry <- utils::read.csv(file.path(root, "tools", "citations.csv"),
                            stringsAsFactors = FALSE, na.strings = "")

## ---------------------------------------------------------------------------
## 1. Registry coverage
## ---------------------------------------------------------------------------
rule("1. Registry coverage")

sources <- c(
  list.files(file.path(root, "R"), "\\.R$", full.names = TRUE),
  list.files(file.path(root, "docs"), "\\.md$", full.names = TRUE),
  list.files(file.path(root, "vignettes"), "\\.Rmd$", full.names = TRUE),
  file.path(root, c("README.md", "NEWS.md", "DESCRIPTION"))
)
sources <- sources[file.exists(sources)]

text <- unlist(lapply(sources, function(f) readLines(f, warn = FALSE)))
found <- regmatches(text, gregexpr("10\\.[0-9]{4,9}/[^\\s\"'<>)\\]},;`*_]+", text, perl = TRUE))
found <- unique(unlist(found))
found <- sub("[.,;:>`)\\]]+$", "", found)
# tools/citations.csv is itself excluded, so the registry cannot vouch for itself.

reg_dois <- stats::na.omit(registry$doi)

unregistered <- setdiff(tolower(found), tolower(reg_dois))
if (length(unregistered)) {
  fail("DOI cited but not in tools/citations.csv: ",
       paste(unregistered, collapse = ", "))
} else {
  say("  all ", length(found), " cited DOIs are registered")
}

unused <- setdiff(tolower(reg_dois), tolower(found))
if (length(unused)) {
  note("Registry DOI never cited in the package: ",
       paste(unused, collapse = ", "))
}

## ---------------------------------------------------------------------------
## 2. CrossRef metadata
## ---------------------------------------------------------------------------
rule("2. CrossRef metadata")

crossref <- function(doi) {
  url <- paste0("https://api.crossref.org/works/", utils::URLencode(doi, TRUE))
  out <- tryCatch(
    jsonlite::fromJSON(url, simplifyVector = FALSE),
    error = function(e) NULL
  )
  out$message
}

to_check <- registry[!is.na(registry$doi) &
                       grepl("crossref", registry$checks %||% ""), , drop = FALSE]

for (i in seq_len(nrow(to_check))) {
  r <- to_check[i, ]
  m <- crossref(r$doi)

  if (is.null(m)) {
    fail(r$key, ": DOI did not resolve at CrossRef (", r$doi, ")")
    next
  }

  problems <- character()

  fam <- if (length(m$author)) m$author[[1]]$family else NA_character_
  if (!is.na(fam) && norm(fam) != norm(r$first_author)) {
    problems <- c(problems, sprintf("first author '%s' vs registry '%s'",
                                    fam, r$first_author))
  }

  yr <- m$issued$`date-parts`[[1]][[1]]
  # Online-first publication can predate the issue year we cite by one.
  if (!is.null(yr) && !(yr %in% c(r$year, r$year - 1L))) {
    problems <- c(problems, sprintf("year %s vs registry %s", yr, r$year))
  }

  ti <- if (length(m$title)) m$title[[1]] else NA_character_
  if (!is.na(ti) && norm(ti) != norm(r$title)) {
    problems <- c(problems, sprintf("title\n        CrossRef: %s\n        registry: %s",
                                    ti, r$title))
  }

  ct <- if (length(m$`container-title`)) m$`container-title`[[1]] else NA_character_
  if (!is.na(ct) && !is.na(r$container) && norm(ct) != norm(r$container)) {
    problems <- c(problems, sprintf("journal '%s' vs registry '%s'", ct, r$container))
  }

  if (!is.na(r$volume) && !is.null(m$volume) &&
      trimws(m$volume) != trimws(as.character(r$volume))) {
    problems <- c(problems, sprintf("volume '%s' vs registry '%s'",
                                    m$volume, r$volume))
  }

  if (length(problems)) {
    fail(r$key, " (", r$doi, "):\n      - ", paste(problems, collapse = "\n      - "))
  } else {
    say("  ok  ", r$key, "  ", r$doi)
  }
}

## ---------------------------------------------------------------------------
## 3. URL liveness
## ---------------------------------------------------------------------------
rule("3. URL liveness")

url_ok <- function(u) {
  code <- tryCatch({
    con <- url(u, open = "rb")
    on.exit(close(con), add = TRUE)
    readBin(con, "raw", 1L)
    200L
  }, error = function(e) {
    # Fall back to curl, which follows redirects and reports the status.
    st <- suppressWarnings(system2(
      "curl", c("-sIL", "-o", "/dev/null", "-w", "%{http_code}",
                "--max-time", "30", shQuote(u)),
      stdout = TRUE, stderr = FALSE
    ))
    suppressWarnings(as.integer(st[length(st)]))
  })
  isTRUE(!is.na(code) && code >= 200 && code < 400)
}

urls <- registry[!is.na(registry$url) & grepl("url", registry$checks %||% ""), , drop = FALSE]
for (i in seq_len(nrow(urls))) {
  r <- urls[i, ]
  if (url_ok(r$url)) {
    say("  ok  ", r$key, "  ", r$url)
  } else {
    fail(r$key, ": URL did not resolve (", r$url, ")")
  }
}

## ---------------------------------------------------------------------------
## 4. NARWC handbook version
## ---------------------------------------------------------------------------
rule("4. NARWC handbook version")

cited_version <- 8L
page <- tryCatch(
  paste(readLines("https://www.narwc.org/sightings-database.html", warn = FALSE),
        collapse = " "),
  error = function(e) NULL
)

if (is.null(page)) {
  note("Could not reach narwc.org to check the handbook version.")
} else {
  # The site exposes the version two ways: in prose ("Version 8"), and in the
  # filename of the linked PDF ("narwc_users_guide__v8_.pdf"). The filename is
  # the reliable one - the prose is often inside a script-rendered block.
  pats <- c("[Vv]ersion\\s*([0-9]+)", "users_guide[^\"']*?v([0-9]+)")
  nums <- integer(0)
  for (p in pats) {
    hits <- regmatches(page, gregexpr(p, page))[[1]]
    nums <- c(nums, suppressWarnings(as.integer(gsub("\\D", "", hits))))
  }
  nums <- nums[!is.na(nums) & nums > 0 & nums < 100]
  newest <- if (length(nums)) max(nums) else NA_integer_

  if (is.na(newest)) {
    note("No version string found on the NARWC sightings-database page; ",
         "the page layout may have changed. Check by hand.")
  } else if (newest > cited_version) {
    fail("NARWC handbook Version ", newest, " is now available; the package ",
         "cites Version ", cited_version, ".\n",
         "      Review the code books in R/narwc-codes.R against the new ",
         "version before updating the citation - variable definitions and ",
         "codes do change between versions.")
  } else {
    say("  ok  handbook still at Version ", cited_version)
  }
}

## ---------------------------------------------------------------------------
rule("Summary")

for (n in notes) say("  note: ", n)

if (length(failures)) {
  say("")
  for (f in failures) say("  FAIL: ", f)
  say("\n", length(failures), " citation check(s) failed.")
  quit(status = 1L)
}

say("  all citation checks passed", if (length(notes)) " (with notes above)" else "")
