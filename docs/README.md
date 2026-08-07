# distsamp documentation

| Document | What is in it |
|---|---|
| [01-plan.md](01-plan.md) | Why the package exists, the decisions taken before building, the target layout and API, and what is deliberately out of scope |
| [02-implementation.md](02-implementation.md) | How each of the 13 pipeline stages was built, what it replaces in `original/`, and why it works the way it does |
| [03-bug-fixes.md](03-bug-fixes.md) | The 14 defects found in `original/`, each with file and line, consequence, fix, and the test that guards it |
| [04-verification.md](04-verification.md) | `R CMD check` and test-suite results, what the 180 tests establish, and reference numbers for the fixture |
| [05-next-steps.md](05-next-steps.md) | What v1 does not do, in the order it is worth doing |

For using the package rather than understanding how it was built, start with the
vignette:

```r
vignette("segmenting-narwc-data", package = "distsamp")
```

## The short version

`original/` could not run end-to-end: it called two functions that were never
defined. Beyond that it had no package structure, no tests, unseeded randomness,
and a visibility test that silently discarded every pre-2004 survey record.

`distsamp` is the segmentation core rebuilt as an installable package: NARWC
ingest and validation grounded in the handbook's code books, effort
determination, great-circle effort accumulation, track splitting, segment
planning and cutting, along-track midpoints, and per-segment sighting summaries.
24 exported functions, 180 tests, `R CMD check --as-cran` clean.

The Becker segmentation method is preserved. The defects are fixed and
documented, one by one, in [03-bug-fixes.md](03-bug-fixes.md).
