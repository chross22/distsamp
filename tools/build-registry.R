#!/usr/bin/env Rscript
#
# Build a citation registry by scanning a repository for DOIs and URLs and
# looking each one up at CrossRef.
#
#   Rscript build-registry.R <repo-root> [> tools/citations.csv]
#
# Written for migrating a repository onto the shared citation engine. The point
# is that the registry should be generated from what the repository actually
# cites, then read by a human - not hand-transcribed, which is how transcription
# errors get in, and not trusted blindly, which is how CrossRef's occasional
# nonsense gets in.
#
# Rows whose DOI does not resolve are still emitted, with checks=crossref, so
# the first run of the checker reports them rather than silently dropping them.

if (!requireNamespace("jsonlite", quietly = TRUE)) {
  stop("needs jsonlite")
}

args <- commandArgs(trailingOnly = TRUE)
root <- if (length(args)) args[1] else "."

files <- c(
  list.files(file.path(root, "R"), "[.]R$", full.names = TRUE),
  list.files(file.path(root, "docs"), "[.]md$", full.names = TRUE, recursive = TRUE),
  list.files(file.path(root, "vignettes"), "[.]Rmd$", full.names = TRUE),
  list.files(file.path(root, "inst"), "[.](R|md|Rmd)$", full.names = TRUE, recursive = TRUE),
  file.path(root, c("README.md", "NEWS.md", "DESCRIPTION"))
)
files <- files[file.exists(files)]
text <- unlist(lapply(files, readLines, warn = FALSE))

dois <- unique(sub("[.,;:>`)\\]]+$", "", unlist(regmatches(
  text, gregexpr("10\\.[0-9]{4,9}/[^\\s\"'<>)\\]},;`*_]+", text, perl = TRUE)))))
# Documentation sometimes shows a DOI shape rather than a DOI: an ellipsis, or
# an xxxxx placeholder. Those are not citations.
dois <- dois[!grepl("[.]{3}|x{4,}|XXXX", dois)]

# Only URLs that look like a citation target, not every link in a README.
urls <- unique(sub("[.,;:>`)\\]]+$", "", unlist(regmatches(
  text, gregexpr("https?://[^\\s\"'<>)\\]}`]+", text, perl = TRUE)))))
urls <- grep(
  "cran\\.r-project|r-project\\.org|marine\\.copernicus|narwc\\.org|jstatsoft|noaa\\.gov",
  urls, value = TRUE)
urls <- setdiff(urls, grep("badge|shields\\.io|github\\.com/chross22", urls, value = TRUE))

csv_escape <- function(x) {
  x <- ifelse(is.na(x), "", as.character(x))
  ifelse(grepl('[",]', x), paste0('"', gsub('"', '""', x), '"'), x)
}

lookup <- function(doi) {
  u <- paste0("https://api.crossref.org/works/", utils::URLencode(doi, TRUE))
  m <- tryCatch(jsonlite::fromJSON(u, simplifyVector = FALSE)$message,
                error = function(e) NULL)
  if (is.null(m)) {
    # Dataset DOIs are registered with DataCite, not CrossRef.
    u2 <- paste0("https://api.datacite.org/dois/", utils::URLencode(doi, TRUE))
    a <- tryCatch(jsonlite::fromJSON(u2, simplifyVector = FALSE)$data$attributes,
                  error = function(e) NULL)
    if (!is.null(a)) {
      return(list(
        author = if (length(a$creators))
          a$creators[[1]]$familyName %||% a$creators[[1]]$name %||% "" else "",
        year = a$publicationYear %||% "",
        title = if (length(a$titles)) a$titles[[1]]$title else "",
        container = a$publisher %||% "", volume = "", pages = ""))
    }
    return(list(author = "UNKNOWN", year = "", title = "DOI DID NOT RESOLVE - CHECK BY HAND",
                container = "", volume = "", pages = ""))
  }
  list(
    author = if (length(m$author)) m$author[[1]]$family %||% "" else "",
    year = m$issued$`date-parts`[[1]][[1]] %||% "",
    title = if (length(m$title)) gsub("<[^>]+>", "", m$title[[1]]) else "",
    container = if (length(m$`container-title`)) m$`container-title`[[1]] else "",
    volume = m$volume %||% "",
    pages = m$page %||% ""
  )
}
`%||%` <- function(x, y) if (is.null(x)) y else x

key_for <- function(author, year, used) {
  base <- tolower(gsub("[^A-Za-z]", "", author))
  if (!nzchar(base)) base <- "ref"
  k <- paste0(base, year)
  n <- 1
  while (k %in% used) { n <- n + 1; k <- paste0(base, year, letters[n]) }
  k
}

cat("key,doi,url,first_author,year,title,container,volume,pages,checks,note\n")
used <- character()
for (d in dois) {
  m <- lookup(d)
  k <- key_for(m$author, m$year, used); used <- c(used, k)
  cat(paste(c(k, d, "", csv_escape(m$author), m$year, csv_escape(m$title),
              csv_escape(m$container), m$volume, csv_escape(m$pages),
              "crossref", ""), collapse = ","), "\n", sep = "")
  Sys.sleep(0.1)  # be polite to the API
}
for (u in urls) {
  k <- key_for(sub("^https?://(www\\.)?", "", sub("/.*", "", sub("^https?://", "", u))), "", used)
  used <- c(used, k)
  cat(paste(c(k, "", u, "", "", "", "", "", "", "url",
              "Generated from a scanned URL - fill in the fields by hand"),
            collapse = ","), "\n", sep = "")
}
