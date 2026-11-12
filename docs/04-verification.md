# Verification

*C. H. Ross. 2026-11-12. Distributed with the package source.*

## 1. Scope

This chapter records what was checked, how, and the result. Everything here
was run on the code as it stands. Sections 2 to 5 cover the package check, the
test suite, the vignettes, and reference numbers for the bundled fixture.
Section 6 covers performance on synthetic full seasons. Section 7 explains why
no numerical comparison against the original scripts (`original/`) was made.

The fixture is the small example survey bundled with the package, built from
the handbook's worked example.

## 2. `R CMD check --as-cran`

```
* using R version 4.6.1 (2026-06-24)
* using platform: aarch64-apple-darwin25.4.0
* using option '--as-cran'
* this is package 'distsamp' version '0.1.0'
...
Status: 3 NOTEs
```

Result: **0 errors, 0 warnings, 3 NOTEs.**

| NOTE | Cause |
|---|---|
| 1. New submission, and two 404 URLs | The `URL` and `BugReports` fields point at the GitHub repository. Expected for an unpublished package. |
| 2. `data-raw` at top level | Now in `.Rbuildignore`, with `docs` and `original`. |
| 3. HTML manual validation skipped ("'tidy' doesn't look like recent enough HTML Tidy") | An artefact of the machine, not the package. |

To reproduce (pandoc is needed for the vignette; on this machine it ships
inside RStudio):

```bash
export RSTUDIO_PANDOC=/Applications/RStudio.app/Contents/Resources/app/quarto/bin/tools
R CMD build .
R CMD check --as-cran distsamp_0.1.0.tar.gz
```

## 3. Test suite

```
[ FAIL 0 | WARN 0 | SKIP 0 | PASS 809 ]
```

809 assertions in 307 tests across 22 files (2026-11-12; 189 tests across six
files when this chapter was first written). Sections 3.1 to 3.8 state what they establish.

### 3.1 Effort is conserved

Every kilometre of on-effort trackline lands in exactly one segment. This is
asserted directly (total segment effort equals total track effort, to `1e-9`)
and indirectly (the fixture's geometry makes every expected distance exactly
computable).

On the fixture: **92.2296 km** across 7 tracks and 20 segments, with segment
effort and track effort agreeing exactly.

### 3.2 Distances are correct

- One degree of latitude is 111.12 km under all three methods.
- `becker` and `kenney` are bit-identical over 50 random position pairs.
- `haversine` agrees with the law of cosines to under `1e-6` km over 200 random
  short displacements, the range where the law of cosines is weakest.
- Symmetry, exact zero for coincident points, `NA` propagation, vectorisation,
  and recycling hold.
- Effort never bridges a gap between two occupations of the same survey line.

### 3.3 Segments are the right size

- Planned target lengths sum to the track length exactly, over eight track
  lengths chosen to reach each branch of the planner.
- A remainder above the tolerance becomes its own segment; below it, the
  remainder is absorbed. Both cases are checked against hand-computed values.
- Realised segment lengths stay within `[0.5s, 1.5s]` (`s` is the target
  length) plus one record of slop, over 15 seeds.
- Cutting error does not accumulate: on a 401-record, 111 km track, the final
  segment stays under `1.5s` over 10 seeds. **This test failed before the
  cumulative-cut-point fix** and is the reason that fix exists.
- Both over- and under-shooting cuts occur across seeds, so the coin flip works
  in both directions.

### 3.4 Defects stay fixed

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

### 3.5 Midpoints are on the track

A segment is built with its records bunched at one end. The along-track
midpoint lands at the true half-distance point (43.05). The coordinate mean is
well away from it (below 43.03). On a straight northbound line, every midpoint
lies on the meridian to `1e-9` degrees and the sequence is monotonic.

### 3.6 Sighting filters behave

- `LEGSTAGE` 6 and 7 are excluded by default and can be included on request.
- `IDREL` 1 and 9 are excluded by default and can be included on request.
- Two groups sharing one `EVENTNO` count as two sightings, not one.
- Attaching a circling sighting never changes a segment's effort.
- Weighted Beaufort follows the distance-weighted sea state, not the record
  mean.

### 3.7 Pipeline invariants

- The caller's RNG stream is unchanged by segmenting, seeded or not.
- `crop_to_bbox()` leaves the segment, sighting, and point tables consistent.
- `segments_wide()` produces zeros, never `NA`, for absent species.
- `write_segments()` writes exactly the requested tables.

### 3.8 Citations stay current

Three offline checks in `test-citations.R`: every DOI cited anywhere in the
package is in `tools/citations.csv`; the registry is well formed; and the
handbook version is cited consistently across the code, the README, and the
checker script.

The network-dependent checks run monthly in CI (`tools/check-citations.R`);
see [06-references.md](06-references.md#7-keeping-citations-current).

## 4. Vignettes

Both vignettes knit end to end from the fixture during `R CMD build`, so every
evaluated example runs on every build.

| Vignette | Content |
|---|---|
| `segmenting-narwc-data.Rmd` | The full walkthrough. |
| `from-segments-to-density.Rmd` | Handing the output to `Distance` and `dsm`. The chunks that call those two packages are `eval = FALSE`, since neither is a dependency; everything else runs. |

## 5. Fixture reference numbers

Reference values for the fixture, for spotting a regression:

| Quantity | Value |
|---|---|
| Records | 113 |
| Survey dates | 2 |
| Tracks with effort | 7 |
| Segments at `seg_length = 5, seed = 1` | 20 |
| Total effort | 92.2296 km |
| Segment length range | 2.2224 – 7.7784 km |
| Circling records detected | 5 |
| Validation findings | 1 (a note: one line has no end-line record, by design) |
| Exported functions | 55 |
| Tests | 809 assertions |

## 6. Performance on a full season

The 113-record fixture says nothing about behaviour on a season.
`data-raw/make-season.R` generates a synthetic season of any size (days x
lines x points), with sightings and circling excursions at chosen rates, so
these numbers can be reproduced and rechecked after a change.

Method: `segment_survey(seg_length = 5)` on an M-series Mac, R 4.6.1, with 1%
of records a sighting and 15% of those circled. Remeasured 2026-11-12, after
`segment_midpoints()` was vectorised, on 12, 24 and 48 days of
`make_season()`:

| records | segments | time | per record | vs previous |
|---|---|---|---|---|
| 58,035 | 6,361 | 2.62 s | 45.2 us | — |
| 116,045 | 12,710 | 5.84 s | 50.3 us | x2.23 |
| 231,980 | 25,412 | 11.81 s | 50.9 us | x2.02 |

**Run time is linear.** Doubling the data doubles the time, and the per-record
cost is flat. A quarter of a million records takes about twelve seconds.

By stage, at 116k records: `cut_segments()` 2.32 s, `sighting_distances()`
0.30 s, `attach_circling_sightings()` 0.16 s, `segment_midpoints()` 0.12 s.

Earlier baseline (before 2026-11-12): 60,430 / 120,945 / 241,745 records in
5.17 / 10.59 / 21.61 s, with `segment_midpoints()` taking 4.75 s of the 121k
run. It built one table per segment. It now computes all midpoints in one pass,
with results equal to the old ones within 1.5e-14 degrees on a 194k-record
season.

### 6.1 One quadratic term, found and removed

`attach_circling_sightings()` was the exception. It looped over circling
sightings and, for each, scanned the whole segment table and then the whole
point table to apply the same-species rule: `O(candidates x records)`. At a
realistic circling rate the cost is invisible, which is why the totals above
look linear either way. Raising the rate until every sighting is circled
exposes it:

| records | candidates | before | after |
|---|---|---|---|
| 25,060 | 1,012 | 0.39 s | 0.100 s |
| 49,785 | 1,957 | 1.03 s (x2.62) | 0.203 s (x2.03) |
| 100,030 | 4,006 | 2.99 s (x2.89) | 0.401 s (x1.98) |

The ratios are the evidence. Before the rewrite, 2.62 and 2.89 trend toward 4,
the signature of a quadratic. After it they are 2.

This matters because right whale surveys circle often; the rate that exposes
the problem is not pathological. The fix replaces the per-candidate scans with
a rolling lookup per day and a membership test built once. Since 2026-11-12 the
lookups split the table once by line occupation. It is guarded by
`test-attach-circling.R`, which checks that each sighting still joins the
segment containing the break-off, never crosses a day boundary or a file, and
looks for the group within the line occupation.

## 7. Cross-check against `original/`

A direct numerical diff against the original scripts was **not** run, because
the original pipeline cannot execute. `chop_segments()` calls
`calculate_midpoint()` and `crop_data()`, and neither is defined anywhere in
`original/` (see
[03-bug-fixes.md](03-bug-fixes.md#14-functions-that-were-called-but-never-existed)).
It cannot run end to end on the fixture without first writing the two missing
functions. The comparison would then be against code that never existed, not
against anything that produced a published result.

Instead, each ported stage was read against its original line by line. Every
intentional departure is listed in [03-bug-fixes.md](03-bug-fixes.md) with the
handbook section or failing test that motivates it. Where behaviour is
unchanged (the planner's `leftover`/`segtol` arithmetic, the coin flip, the
`case2`–`case5` structure, the track-splitting rule), that is stated
explicitly.

A numerical comparison becomes possible, and is worth doing, given a real
NARWC extract and segment output from a previous run. It is the first item in
[05-next-steps.md](05-next-steps.md).

## 8. References

Full citations: [06-references.md](06-references.md).
