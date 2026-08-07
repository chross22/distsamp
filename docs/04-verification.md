# Verification

What was checked, how, and the result. Everything here was run on the code as it
stands.

## `R CMD check --as-cran`

```
* using R version 4.6.1 (2026-06-24)
* using platform: aarch64-apple-darwin25.4.0
* using option '--as-cran'
* this is package 'distsamp' version '0.1.0'
...
Status: 3 NOTEs
```

**0 errors, 0 warnings.** The three NOTEs:

1. **New submission, and two 404 URLs.** The `URL` and `BugReports` fields point
   at the GitHub repository. Expected for a package that has not been published.
2. **`data-raw` at top level.** Now in `.Rbuildignore`, along with `docs` and
   `original`.
3. **HTML manual validation skipped** — "'tidy' doesn't look like recent enough
   HTML Tidy". An artefact of the machine, not the package.

To reproduce (pandoc is needed for the vignette; on this machine it ships inside
RStudio):

```bash
export RSTUDIO_PANDOC=/Applications/RStudio.app/Contents/Resources/app/quarto/bin/tools
R CMD build .
R CMD check --as-cran distsamp_0.1.0.tar.gz
```

## Test suite

```
[ FAIL 0 | WARN 0 | SKIP 0 | PASS 180 ]
```

180 tests across five files. What they establish:

### Effort is conserved

Every kilometre of on-effort trackline lands in exactly one segment. Asserted
directly — total segment effort equals total track effort, to `1e-9` — and
indirectly, since the fixture's geometry makes every expected distance exactly
computable.

On the bundled fixture: **92.2296 km** across 7 tracks and 20 segments, with
segment effort and track effort agreeing exactly.

### Distances are right

- One degree of latitude is 111.12 km under all three methods.
- `becker` and `kenney` are bit-identical over 50 random position pairs.
- `haversine` agrees with the law of cosines to under `1e-6` km over 200 random
  short displacements — the range where the law of cosines is weakest.
- Symmetry, exact zero for coincident points, `NA` propagation, vectorisation,
  and recycling.
- Effort never bridges a gap between two occupations of the same survey line.

### Segments are the right size

- Planned target lengths sum to the track length exactly, over eight track
  lengths chosen to hit each branch of the planner.
- A remainder above the tolerance becomes its own segment; below it, it is
  absorbed. Both checked against hand-computed expectations.
- Realised segment lengths stay within `[0.5s, 1.5s]` plus one record of slop,
  over 15 seeds.
- Cutting error does not accumulate: on a 401-record, 111 km track, the final
  segment stays under `1.5s` over 10 seeds. **This test failed before the
  cumulative-cut-point fix** and is the reason that fix exists.
- Both over- and under-shooting cuts occur across seeds, confirming the coin
  flip is live in both directions.

### Bugs stay fixed

Each defect in [03-bug-fixes.md](03-bug-fixes.md) has a test named for the
behaviour it protects:

| Defect | Test |
|---|---|
| Legacy visibility discarded effort | "legacy-format effort is not silently discarded" |
| Last track dropped | "the last track is not dropped" |
| Not reproducible | "segmentation is reproducible under a seed" |
| Leftover never on the last segment | "the leftover can land on any segment, including the last" |
| Empty input | "empty and single-record inputs do not error" |
| Spurious tracks per break record | "a break in effort starts a new track" |
| Accumulated cutting error | "cutting error does not accumulate down a track" |
| Pilot sightings counted | "pilot and photograph sightings are excluded by default" |
| Circling hard-coded to right whales | "circling sightings are attached, and only for the same species" |

### Midpoints are on the track

A segment is built with its records deliberately bunched at one end. The
along-track midpoint lands at the true half-distance point (43.05); the
coordinate mean is well away from it (below 43.03). On a straight northbound
line, every midpoint sits on the meridian to `1e-9` degrees and the sequence is
monotonic.

### Sighting filters behave

- `LEGSTAGE` 6 and 7 excluded by default, includable on request.
- `IDREL` 1 and 9 excluded by default, includable on request.
- Two groups sharing one `EVENTNO` count as two sightings, not one.
- Attaching a circling sighting never changes a segment's effort.
- Weighted Beaufort tracks the distance-weighted sea state, not the record mean.

### Invariants that hold across the whole pipeline

- The caller's RNG stream is unchanged by segmenting, seeded or not.
- `crop_to_bbox()` leaves the segment, sighting, and point tables consistent.
- `segments_wide()` produces zeros, never `NA`, for absent species.
- `write_segments()` writes exactly the requested tables.

## Vignette

`vignettes/segmenting-narwc-data.Rmd` knits end-to-end from the bundled fixture
during `R CMD build`, so every example in it is executed on every build.

## Fixture numbers

Reference values for the bundled example, useful for spotting a regression:

| Quantity | Value |
|---|---|
| Records | 113 |
| Survey dates | 2 |
| Tracks with effort | 7 |
| Segments at `seg_length = 5, seed = 1` | 20 |
| Total effort | 92.2296 km |
| Segment length range | 2.2224 – 7.7784 km |
| Circling records detected | 5 |
| Validation findings | 0 |
| Exported functions | 24 |

## Cross-check against `original/`

A direct numerical diff against the original scripts was **not** run, for a
reason worth recording: the original pipeline cannot execute. `chop_segments()`
calls `calculate_midpoint()` and `crop_data()`, and neither is defined anywhere
in `original/` (see [03-bug-fixes.md](03-bug-fixes.md#14-functions-that-were-called-but-never-existed)).
There is no way to run it end-to-end on the fixture without first writing the two
missing functions, at which point the comparison would be against code that never
existed rather than against anything that produced a published result.

What was done instead: each ported stage was read against its original line by
line, and every intentional departure is enumerated in
[03-bug-fixes.md](03-bug-fixes.md) with the handbook section or failing test that
motivates it. Where behaviour is unchanged — the planner's `leftover`/`segtol`
arithmetic, the coin flip, the `case2`–`case5` structure, the track-splitting
rule — that is stated explicitly.

If you can supply a real NARWC extract together with segment output from a
previous run, a numerical comparison becomes possible and is worth doing. It is
the first item in [05-next-steps.md](05-next-steps.md).


---

Full citations: [06-references.md](06-references.md).
