#!/usr/bin/env Rscript
#
# Check that the citations in this package are still correct and current.
#
#   Rscript tools/check-citations.R
#
# The generic checks live in tools/citation-checks.R and know nothing about this
# project; the project-specific ones live in tools/citation-hooks.R. That split
# is deliberate, so the engine can be shared across repositories while each one
# keeps its own hooks.
#
# Exits 1 if any check fails, so it can gate CI.

if (!requireNamespace("jsonlite", quietly = TRUE)) {
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

source(file.path(root, "tools", "citation-checks.R"))
source(file.path(root, "tools", "citation-hooks.R"))

sources <- c(
  list.files(file.path(root, "R"), "[.]R$", full.names = TRUE),
  list.files(file.path(root, "docs"), "[.]md$", full.names = TRUE),
  list.files(file.path(root, "vignettes"), "[.]Rmd$", full.names = TRUE),
  file.path(root, c("README.md", "NEWS.md", "DESCRIPTION"))
)

ok <- run_citation_checks(
  registry_path = file.path(root, "tools", "citations.csv"),
  sources = sources,
  root = root,
  hooks = citation_hooks()
)

if (!ok) quit(status = 1L)
