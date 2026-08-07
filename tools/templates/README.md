# Shared workflows

Two reusable workflows live in this repository and are called by the other
package repos, so the logic sits in one place and a fix lands everywhere on the
next run.

| workflow | what it does |
|---|---|
| `r-cmd-check-reusable.yaml` | `R CMD check --as-cran` across Ubuntu (devel/release/oldrel-1), macOS and Windows |
| `citation-check-reusable.yaml` | registry coverage, CrossRef metadata, URL liveness, package self-citation, plus any repo-specific hooks |

`R-CMD-check.yaml` and `check-citations.yaml` here are the callers; copy them
from `tools/templates/` into another repo and adjust the inputs.

---

# Adding the citation check to another repository

Three steps.

**1.** Copy `check-citations.yaml` into `.github/workflows/` in the target repo.

**2.** Copy `citations.csv` to `tools/citations.csv` and replace the example rows
with the sources that repo actually cites.

| column | meaning |
|---|---|
| `key` | short identifier, unique within the file |
| `doi` | DOI, or blank |
| `url` | URL to ping for liveness, or blank |
| `first_author`, `year`, `title`, `container`, `volume`, `pages` | what you print, checked against CrossRef |
| `checks` | semicolon-separated: `crossref`, `url`, `none` |
| `note` | free text, for humans |

**3.** Make sure the repo has an `inst/CITATION` and a `## Citing <pkg>` section
in its README — the self-citation check requires both.

That is all. The engine lives in `chross22/distsamp` and is fetched at run time,
so a fix there applies everywhere on the next run.

## What gets checked

1. **Registry coverage** — every DOI cited anywhere in the repo is in the
   registry, and every registry DOI is actually cited. Catches a citation added
   without being registered.
2. **CrossRef metadata** — first author, year, title, journal and volume still
   match what you print. Catches a transcription error and a publisher
   correction.
3. **URL liveness** — registry URLs still resolve.
4. **Package self-citation** — `inst/CITATION` exists and parses, its version
   comes from `meta$Version` rather than being hard-coded, and the README tells
   people how to cite the package.

## Project-specific checks

Add `tools/citation-hooks.R` defining `citation_hooks()`, returning a named list
of functions taking `(registry, ctx)` and returning
`cc_result(failures, notes)`:

```r
check_upstream_version <- function(registry, ctx) {
  # ... look something up ...
  if (newer_exists) {
    return(cc_result(failures = "A newer version of X is available."))
  }
  cc_say("  ok  still current")
  cc_result()
}

citation_hooks <- function() {
  list("5. Upstream version" = check_upstream_version)
}
```

`distsamp`'s hook checks whether the NARWC has published a new handbook version,
because the package's correctness depends on code books in a specific edition.
That is the kind of thing worth a hook: something no generic checker could know.

## Running it locally

```bash
Rscript tools/check-citations.R
```

Needs `jsonlite`.
