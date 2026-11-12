# distsamp documentation

## Start here

| Document | Contents |
|---|---|
| [11-distance-sampling-steps.md](11-distance-sampling-steps.md) ([PDF](11-distance-sampling-steps.pdf)) | From a survey file to an abundance estimate, one step at a time, with code. |
| [10-code-guide.md](10-code-guide.md) ([PDF](10-code-guide.pdf)) | What each part of the pipeline code does, the order steps must run in, and the defects corrected in the 2026-11 audits. |
| [08-onboarding-a-real-extract.md](08-onboarding-a-real-extract.md) | Bringing in a new dataset: the order of steps, reading `diagnose_pipeline()`, and known traps. |

## Reference

| Document | Contents |
|---|---|
| [01-plan.md](01-plan.md) | Why the package exists, design decisions, and what is out of scope. |
| [02-implementation.md](02-implementation.md) | How each pipeline stage was built and what it replaces in `original/`. |
| [03-bug-fixes.md](03-bug-fixes.md) | The 16 defects found in `original/`, with fix and guarding test. |
| [04-verification.md](04-verification.md) | Check and test results, fixture numbers, and performance. |
| [05-next-steps.md](05-next-steps.md) | Work not yet done, in priority order. |
| [06-references.md](06-references.md) | Citations, what each is relied on for, and how to cite the package. |
| [07-fitting-architecture.md](07-fitting-architecture.md) | Where model fitting lives, and the `g(0)` problem. |
| [09-shipboard-surveys.md](09-shipboard-surveys.md) | What `platform = "vessel"` changes and why. |

Tutorials:

```r
vignette("segmenting-narwc-data", package = "distsamp")
vignette("from-segments-to-density", package = "distsamp")
```

## Summary

`distsamp` segments NARWC line-transect survey data for distance sampling and
density surface models. It replaces a set of research scripts (`original/`)
that could not run end to end: they called two undefined functions, had no
tests, used unseeded randomness, and discarded every pre-2004 record through a
visibility test.

The package keeps the segmentation method of Becker et al. (2010) and fixes the
defects, each listed in [03-bug-fixes.md](03-bug-fixes.md). It has 55 exported
functions and 809 test assertions. `R CMD check --no-manual` passes with no
errors, warnings or notes. `--as-cran` is not used, because the `narwcr`
dependency is not on CRAN.

## The `original/` scripts

The scripts are not distributed: they contain collaborators' working notes and
local paths. References such as `original/ds_data_dmr.R:106` record where each
defect came from. They are not links.
