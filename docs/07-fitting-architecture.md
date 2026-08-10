# Where fitting goes, and how g(0) fits in

A design note, settled 2026-08-10. Covers three questions: where the detection
function and the density surface model should be fitted, how to support a gamma
key and an automated model-selection sweep, and whether `g(0)` can be estimated
at all.

Nothing here is built yet. It records the decisions so they do not have to be
re-derived, in the same spirit as the detection-function design in
[05-next-steps.md](05-next-steps.md).

---

## 1. Three layers, not two

| Layer | Holds | Form |
|---|---|---|
| `distsamp` | NARWC ingest, effort, segmentation, right-angle distances | package — exists |
| a fitting package | the model-selection sweep, gamma support, goodness-of-fit and `p̄` reporting, the `dsm` handoff, `g(0)` correction | **package** — to build |
| an analysis repository | which years, which truncation, which covariates, the report | `targets` + `renv`, **not** a package |

The obvious split is two — `distsamp`, then "the analysis". The reason for three
is that the middle layer contains logic that must be tested and will be reused,
and the outer layer contains choices that change every time the analysis is run.
Putting them together means either the analysis choices get frozen into a
package, or the tested logic ends up in a scripts repository where the tests do
not run.

**Why fitting stays out of `distsamp`.** The dependency stack is the immediate
reason: `Distance` pulls `mrds`, `dsm` pulls `mgcv`, and the covariate work pulls
`terra`, `ncdf4`, and the Copernicus tooling. None of that should be imposed on
someone who only wants to cut segments — the same argument already recorded for
the covariate and GAM work in [05-next-steps.md](05-next-steps.md) item 4.

The deeper reason is that `distsamp`'s value is the NARWC-specific knowledge:
which `STRIP` code book applies, where the blind spot is, that a circling
position is not a perpendicular distance. Fitting a detection function is not
NARWC-specific and is well served by mature packages. A wrapper around
`Distance::ds()` would hide its options and rot against it.

**Why the middle layer is a package and not scripts.** Automated regression
testing over detection-function configurations is the requirement that decides
this. Test infrastructure that lives in a scripts repository does not get run.
The sweep logic — holding truncation fixed so that AIC stays comparable,
computing `p̄`, deciding what "best performing" means — is precisely
where a silent error costs a density estimate rather than throwing an error.

**The handoff points already exist.** `detection_data()` (not yet built, see
[05-next-steps.md](05-next-steps.md)) for the detection function, and
`segments_as_sf(segs, "midpoints")` for the density surface. Neither layer needs
to reach into the other's internals.

---

## 2. Fit everything through `mrds::ddf()`

`Distance::ds()` accepts `key = c("hn", "hr", "unif")`. **There is no gamma
key.** It is available in `mrds::ddf(key = "gamma")`.

Since `ds()` is itself a wrapper around `ddf()`, the model set should be fitted
through `ddf()` directly rather than mixing the two. Two reasons:

- **Comparability.** Every AIC in a selection table has to come off the same
  likelihood machinery. `ds()` applies its own truncation handling and
  monotonicity constraints; a table mixing `ds()` and `ddf()` fits risks
  presenting those differences as if they were model differences.
- **Coverage.** A sweep that cannot include gamma is not a sweep over the
  candidate set that matters for this data — see below.

`ds()` remains the right thing for a human fitting one model interactively, and
the vignette should keep using it. The sweep is a different job.

---

## 3. The gamma key, and why it may suit this data

The gamma key function is **unimodal with its peak away from zero**. Detection
probability is *lowest on the track-line* and rises to a maximum at some distance
out. It does not satisfy `g(0) = 1`; scaling is to the mode, not to zero.

For most surveys that shape is a defect. For an aerial platform that cannot see
beneath itself it may be the correct model — which is exactly the situation
handbook 8.A.31 describes for the Skymaster, whose CETAP-era distances "are
actually measured from about 1/8 mile to either side of the survey line", and
which `strip_distance(left_truncation = TRUE)` already half-addresses.

**The trap: a gamma key and `ds(left = )` model the same phenomenon.** Left
truncation removes the unsearched region from the analysis; a gamma key absorbs
the near-track shortfall into the fitted shape. Doing both treats the blind spot
twice. This is a deliberate either-or, and the choice belongs in the record
alongside `distance_source` — a reviewer will ask which was used.

**What a gamma key is not.** It is a shape assumption about *geometry*. It does
not correct for animals being submerged, and it does not correct for observers
missing animals that were at the surface. Reading a gamma fit as though it had
dealt with `g(0)` is the error section 5 is about.

---

## 4. The model-selection sweep

The requirement is to fit many configurations — key function, adjustment terms
and order, covariates, truncation — and see which performs best. Four things
must be built in from the start, because each one silently invalidates a
comparison rather than failing.

**AIC compares only models fitted to the same data.** Truncation changes the
data: a different right truncation means a different set of detections, and the
likelihoods are not on the same scale. Truncation must therefore be an **outer
loop** producing separate tables; key, adjustments, and covariates are the
**inner loop**, where AIC is meaningful. A sweep that varies truncation and ranks
everything in one table is ranking nothing.

**Binned and exact distances cannot share a table.** `STRIP`-era distances are
intervals and are fitted binned; angle- and position-derived distances are
points. A multi-year sweep splits along that line whether or not the analyst
wants it to. `detection_data()` will emit `distbegin`/`distend` for the binned
rows, so the split is detectable from the data rather than something the analyst
must remember.

**Rank on `p̄`, not on AIC alone.** Effective strip half-width is what
propagates into abundance, and two models within 2 AIC of each other can give
materially different `p̄`. The selection table should carry, per model:
AIC and ΔAIC; `p̄` and its CV; a goodness-of-fit statistic
(Cramér-von Mises and Kolmogorov-Smirnov, or chi-squared for binned fits); and
whether the fit converged and stayed monotonic. "Best performing" should be
defined against that set, not against AIC rank.

**Selection and regression testing are two different jobs.** The sweep *selects*
a model. Regression tests *pin* the sweep's output, so that an `mrds` or
`Distance` upgrade cannot silently change which model wins. The second is the one
that earns the word regression, and it is the reason the middle layer is a
package: it needs a fixture, a stored expected result, and a test that compares
them. Snapshot the selection table, not just the winner — a change in the ranking
of models 3 and 4 is early warning that something moved.

---

## 5. Can `g(0)` be estimated? Mostly no, and the reason matters

Short answer: **an option to *apply* a `g(0)` correction makes sense and should
be built. An option to *estimate* it from a standard NARWC extract does not,
because the data required is not there.**

The reason this is worth spelling out is that three different things all present
as `g(0) < 1`, they need three different treatments, and correcting for one
while believing you have corrected for another is how density estimates go wrong
by a factor rather than a percentage.

### The three components

| | What it is | How it is addressed | Estimable from NARWC? |
|---|---|---|---|
| **Geometric** | The aircraft cannot see the water directly beneath it | `ds(left = )`, or a gamma key | Yes — it is a property of the platform, already documented per aircraft |
| **Availability** | The animal was submerged and could not be seen at all | Multiplier from dive/surfacing data | **No** — needs external tag data |
| **Perception** | The animal was at the surface and the observer missed it | Double-observer / mark-recapture distance sampling | **No** — needs a protocol NARWC extracts do not record |

**Geometric** is the one already partly handled, and the only one recoverable
from the survey record itself, because it is a fact about the aircraft rather
than about the animals or the observers. Section 3 covers it.

**Availability** cannot be estimated from line-transect data. It requires the
proportion of time an animal is at or near the surface and the length of the
window during which it is in view — the latter a function of aircraft speed,
altitude, and the geometry of the observation window. The surfacing parameters
come from tagging studies, not from the survey. The correction is therefore
something the analyst *supplies*, with a source, and the package's job is to
apply it correctly and propagate its uncertainty. This matters more here than for
most species: right whales spend a large fraction of their time submerged, so the
correction is large, and an uncorrected density estimate is not slightly low but
substantially low.

**Perception** requires two observers whose detections can be matched into
duplicates — `mrds` supports this through `method = "io"`, `"trial"`, and
`"rem"`. A standard NARWC sightings extract records one row per sighting group,
not per observer, so the duplicate structure that mark-recapture needs is
absent. Unless a particular survey ran a dedicated double-observer protocol *and*
that structure survives into the extract, this is not estimable.

Two things worth checking against a real extract before concluding, both of
which are unresolved because no real NARWC data has been used yet (the top open
item in [05-next-steps.md](05-next-steps.md)):

- `Tr_SIGHTING` is now identified: it flags whether a sighting was made from the
  track-line, and it is specific to the **Center for Coastal Studies** Cape Cod
  Bay programme. It says nothing about observers, so it is not a route to
  perception bias.
- `OBSSIGHT` remains unattributed, and is the least recoverable column in that
  file. It is never assigned and never filtered on — five occurrences, all
  `select()` — so its meaning cannot be inferred from its use, and it is not a
  handbook Table 1 variable. The name invites reading it as observer identity,
  which would make it the one column here relevant to perception bias. Whether it
  is anything of the sort needs a data dictionary, not more code reading. See
  [05-next-steps.md](05-next-steps.md) item 2.
- `LEGSTAGE == 6` marks a **pilot** sighting, which is in principle a second
  detector. It is tempting to read that as a double-observer structure. It very
  probably is not usable as one: pilots search opportunistically rather than
  systematically, so the independence assumption that mark-recapture rests on
  fails, and the detection function being estimated would not be the observers'.
  Note also that this package *excludes* pilot sightings from density estimates
  by default, for reasons recorded as defect 9 in
  [03-bug-fixes.md](03-bug-fixes.md); using them as a second observer would be a
  different use of the same records and would need its own justification.

### The design

A `g0` argument that takes a **value and a standard error**, not a bare number,
applied at the abundance step, with three rules:

1. **No default, and never silently 1.** Omitting it is a choice, and the output
   should record that `g(0) = 1` was assumed rather than let it pass
   unremarked. This is the requirement already stated in
   [05-next-steps.md](05-next-steps.md): the package should not estimate
   `g(0)`, but it must not let a user assume it away either.
2. **Uncertainty is propagated, or the correction is refused.** The CV of a
   `g(0)` correction frequently dominates the CV of the abundance estimate. An
   abundance figure corrected by a point estimate with its variance dropped is
   worse than an uncorrected one, because it is wrong *and* looks precise.
   Delta-method or bootstrap propagation, and the reported CV must include it.
3. **The components are named separately.** Availability and perception enter as
   distinct factors, each with its own source, so that it is visible which have
   been applied and which are still assumed to be 1. A single opaque `g0 = 0.35`
   invites exactly the double-counting this section is about — most obviously,
   combining it with a gamma key that has already absorbed the geometric term.

And an **MRDS backend, conditional on the data supporting it.** If a survey does
carry double-observer structure, `mrds` already does this properly and the
fitting layer should hand off to it rather than reimplement. The important part
is the guard: the handoff must verify that the duplicate structure is present and
**error** if it is not, rather than fitting a single-observer model and reporting
it as though perception bias had been handled.

---

## 6. Build order

1. `detection_data()` in `distsamp` — the sweep's input. Blocks everything else.
2. The fitting package skeleton, with the `ddf()` backend and the selection table
   over key × adjustment × covariates at fixed truncation.
3. Gamma support, and the recorded either-or against left truncation.
4. Regression fixtures and snapshot tests over the selection table.
5. The `g(0)` correction slot, with separate availability and perception factors
   and propagated uncertainty.
6. The `dsm` handoff and the density surface, from
   `segments_as_sf(segs, "midpoints")`.
7. The analysis repository, last, once the layers beneath it are stable.

## 7. Open questions

- **Does any NARWC extract in hand carry per-observer detections?** Decides
  whether the MRDS backend is worth building at all. Needs a real extract.
- **What are `OBSSIGHT` and `Tr_SIGHTING`?** Same dependency.
- **Which availability parameters, from which study?** A citation the analysis
  will have to defend, and it belongs in `tools/citations.csv` once chosen.
- **Gamma or left truncation for the Skymaster era?** Not answerable in the
  abstract; the sweep should fit both and the comparison should be recorded.

---

Full citations: [06-references.md](06-references.md).
