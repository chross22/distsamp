# distsamp documentation

| Document | What is in it |
|---|---|
| [01-plan.md](01-plan.md) | Why the package exists, the decisions taken before building, the target layout and API, and what is deliberately out of scope |
| [02-implementation.md](02-implementation.md) | How each pipeline stage was built, what it replaces in `original/`, and why it works the way it does |
| [03-bug-fixes.md](03-bug-fixes.md) | The 16 defects found in `original/`, each with file and line, consequence, fix, and the test that guards it |
| [04-verification.md](04-verification.md) | `R CMD check` and test-suite results, what the tests establish, and reference numbers for the fixture |
| [05-next-steps.md](05-next-steps.md) | What v1 does not do, in the order it is worth doing |
| [06-references.md](06-references.md) | Every citation, what it is relied on for, what the published methods do *not* cover, and how to cite this in a methods section |
| [07-fitting-architecture.md](07-fitting-architecture.md) | Where detection-function and density-surface fitting should live, the model-selection sweep, and what can and cannot be done about `g(0)` |

For using the package rather than understanding how it was built, start with the
vignette:

```r
vignette("segmenting-narwc-data", package = "distsamp")
```

> **A note on `original/`.** This package was rewritten from a set of internal
> research scripts. Those scripts are **not distributed** — they contain
> collaborators' working notes and local paths, and were never intended for
> publication. References below of the form `original/ds_data_dmr.R:106` are
> provenance: they record which defect came from where, so the rewrite can be
> audited by anyone who has the original code. They are not links.

## The short version

`original/` could not run end-to-end: it called two functions that were never
defined. Beyond that it had no package structure, no tests, unseeded randomness,
and a visibility test that silently discarded every pre-2004 survey record.

`distsamp` is the segmentation core rebuilt as an installable package: NARWC
ingest and validation grounded in the handbook's code books, effort
determination, great-circle effort accumulation, track splitting, segment
planning and cutting, along-track midpoints, per-segment sighting summaries, and
right-angle distances from all four sources the archive records.
33 exported functions, 359 test assertions, `R CMD check --as-cran` clean.

The Becker segmentation method is preserved. The defects are fixed and
documented, one by one, in [03-bug-fixes.md](03-bug-fixes.md).
