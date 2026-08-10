# Next steps

What v1 does not do, roughly in the order it is worth doing.

## 1. Validate against a real NARWC extract

The highest-value next step, and the cheapest.

Everything in v1 is verified against a synthetic fixture built from the
handbook's worked example. That checks the logic but cannot surface the things
real archives do: codes outside the book, `LEGSTAGE` sequences that do not close,
duplicated events, time zones that shifted mid-season, `LEGNO` values that repeat
across blocks.

Concretely, with one real file:

```r
dat <- read_narwc("path/to/extract.csv")
issues <- validate_narwc(dat)
issues[, c("check", "severity", "column", "n")]
```

Then compare `segment_survey()` output against segments from a previous run of
the original scripts. Any difference should be attributable to a numbered defect
in [03-bug-fixes.md](03-bug-fixes.md); anything that is not is a finding.

## 2. A documented profile for the CCS Cape Cod Bay format

The processed "ready for model" CSV the original scripts consumed is not raw
NARWC. It carries columns that are not handbook Table 1 variables and that are
computed nowhere in `original/` — every occurrence of each is a `filter()` or a
`select()`, with no assignment. They arrive already set.

**Where they come from (Camille, 2026-08-10):** `Tr_SIGHTING` and the `IS_*`
columns are **specific to the Center for Coastal Studies aerial survey programme
of Cape Cod Bay**. They are an artifact of the CCS survey design, not of NARWC
and not of any general pipeline.

| Column | Meaning | Source | Used for |
|---|---|---|---|
| `Tr_SIGHTING` | Whether the sighting was made from the track-line | **CCS** | **load-bearing** — see below |
| `IS_LAT`, `IS_LONG`, `IS_SPECCODE` | **Initial sighting**: the *aircraft's* position on the track-line at first detection, and the species. Distinct from the circle position in `LATITUDE`/`LONGITUDE` | **CCS** | the distance calculation |
| `LEGTYPE_BK` | Kenney's `LEGTYPE`, alongside a different `LEGTYPE` | unconfirmed | aliased to `LEGTYPE` |
| `Effort_Type` | An upstream effort classification | unconfirmed | carried only |
| `OBSSIGHT` | An observer sighting flag | unconfirmed | carried only, never acted on |
| `Date_UTC`, `Time_UTC` | Date and time, already in UTC | unconfirmed | carried only |

### `IS_*` is not `S_LAT`/`S_LONG`

An earlier version of this document guessed that `IS_LAT`/`IS_LONG` were "the
handbook's `S_LAT`/`S_LONG`". That was wrong twice over: they are neither that
column nor a position of the animal at all. See below for what they are, and for
why the correction points at something useful.

### `Tr_SIGHTING`

`compute_distance.R:15` and `:18` gate **the entire distance calculation** on
`Tr_SIGHTING == 1`. Now that the column is identified, the consequence is
sharper than "an opaque filter": the original pipeline **silently required
CCS-format input.** Run against a NARWC extract from any other programme, the
column is absent and the filter errors, or — worse, if some other pipeline
supplies a column of that name meaning something else — it runs and returns the
wrong subset. Combined with the `"RIWH" %in% ...` day filter at line 13, the set
of sightings that ever received a distance was fixed by two conditions, one of
them a survey-programme artifact. See defect 15 in
[03-bug-fixes.md](03-bug-fixes.md).

`distsamp` does not use it. Eligibility comes from handbook columns only, so the
distance code runs on data from any programme. `Tr_SIGHTING` remains useful as a
*cross-check* on that eligibility where it exists — it encodes the same intent —
but it cannot be the mechanism.

### What is still unknown

`LEGTYPE_BK`, `Effort_Type`, `OBSSIGHT`, `Date_UTC`, and `Time_UTC` have not been
attributed. `OBSSIGHT` is the least recoverable of them: it appears five times,
all in `select()`, and is never filtered on or assigned, so its meaning cannot be
inferred from its use either.

v1 treats all of these as optional pass-through columns; `LEGTYPE_BK` is aliased
to `LEGTYPE`, and the rest survive if named in `extra_columns`. That works by
arrangement rather than by design. `read_narwc(profile = "ccs")` could map them
properly given a data dictionary.

### `IS_*` is a better anchor, not a better animal position

**Settled: `IS_LAT`/`IS_LONG` is the *aircraft's* position on the track-line at
initial sighting**, not the animal's. The CCS row therefore carries both ends of
the measurement — the track-line point at detection in `IS_*`, and the circle
position in `LATITUDE`/`LONGITUDE` — and `compute_distance.R:23` takes the
distance between them.

That maps onto `circling_distance()` directly, and improves it. This package
currently anchors a circling sighting on the `LEGSTAGE == 3` break-off record;
`IS_*` gives **the point of detection instead of the point of turning**, which is
strictly better, because the aircraft flies some distance past a group before it
begins the turn. The animal's position still has to come from the circle record,
so the orbit-radius caveat in step 11e of
[02-implementation.md](02-implementation.md) is unaffected.

Note that the CCS distance is still *radial* — track-line point straight to the
animal — so defect 15 stands and the projection `circling_distance()` does is
still the improvement. The two changes compose: better anchor, and perpendicular
rather than radial.

**To build:** an `anchor` argument on `circling_distance()` accepting an explicit
pair of position columns, so a CCS file can supply `IS_LAT`/`IS_LONG` and
anything else can fall back to the break-off record. Blocked on a real CCS file
to verify the column semantics end to end — the reading above is confirmed, but
no file has been seen.

## 2b. Handling columns from other survey programmes — done

`narwc_profiles()`, `read_narwc(profile = )`, and the
`columns_outside_handbook` check now cover the general case: unrecognised
columns are reported by name rather than silently dropped, and named to a
survey programme where one is recognised. Step 1b of
[02-implementation.md](02-implementation.md) has the reasoning, including why a
profile is never applied automatically.

CCS is the only profile registered, and is **an exception rather than a
representative case**. Adding a programme needs its column list and — the part
that is usually missing — a data dictionary, since a column's meaning cannot be
inferred from its name. Entries whose meaning was guessed are marked
`confidence = "unconfirmed"` and should stay that way until someone who ran the
survey confirms them.

Note the handling in `DataExploration.R:52` and `:71`: those scripts
`tidyr::fill()` `LEGTYPE`, `LEGSTAGE`, `LEGNO`, `VISIBLTY`, `BEAUFORT` and others
in both directions (`.direction = "downup"`) before use. That propagates a sea
state or leg number backwards in time across arbitrary gaps. Whether it is
appropriate depends on how the upstream file records those variables, and is
worth settling before that profile is written.

## 3. Detection functions

Perpendicular distances are now computed from the `ANGLEL`/`ANGLER` declination
angles (handbook 8.A.2) and surfaced in `segs$detections`, so fitting a
detection function is a matter of handing that table to `Distance::ds()`. What
is still missing:

- ~~**`STRIP` to right-angle distance.**~~ Done — `narwc_strip_bins()` and
  `strip_distance()`.
- ~~**Exact sighting positions.**~~ Done — `exact_distance()`, which projects
  onto the trackline rather than measuring radially as
  `original/compute_distance.R` did.
- **Truncation and binning.** `Distance::ds()` wants a truncation distance, and
  `STRIP`-derived distances are intervals rather than points, so binned fitting
  is needed for older data.
- The multi-year fitting from `original/detectionFunctionMultipleYears.R`. Not
  a wrapper around `Distance::ds()` — see the design note below.

One caution carried over from the original: `detection_function.R:10` filters
`CIRCLE != 1`, which drops rows where `CIRCLE` is `NA` as well as where it is 1.
Use `!(CIRCLE %in% 1)`.

## 4. Covariates and density surface models

`original/access_covars.R` and `accessCopernicus.py` fetch Copernicus Marine
products; `load_covars.R` reads them; `integrated_gam_development.CHR.R` fits the
GAMs. These are a natural separate package — they share no data structures with
segmentation beyond the segment midpoints, and they carry a heavy dependency
stack (`terra`, `marmap`, `copernicus`, `ncdf4`) that would otherwise be imposed
on everyone who only wants to cut segments.

`segments_as_sf(segs, "midpoints")` is the intended handoff point.

## 5. Mapping — partly done

`plot()` methods on `distsamp_segments` now cover the diagnostic views, behind
`Suggests` on `ggplot2`: the track with segment midpoints and sightings, tracks
coloured by `new_trackno`, segment lengths against the target, and the
distribution of perpendicular distances. They return `ggplot` objects rather
than writing PNGs to a directory.

Still missing, and deliberately: **coastlines and basemaps**.
`original/map_utils.R` contains a substantial reimplementation of
`ggspatial::annotation_map_tile` worth preserving, but it needs `sf` and a tile
source, and the diagnostic plots do not. `segments_as_sf()` is the handoff for
anyone who wants a real map.

## 6. Smaller items

- **Effort summaries per survey line.** `ds_data_dmr.R` produced
  `effort_summary` and `effort_summary_reduced` — effort per `FILEID` x `LEGNO`,
  and per `LEGNO` with re-flights combined — plus the percentage of lines
  re-flown. `segs$tracks` covers most of this but is keyed on continuous tracks,
  not on survey lines.
- **A `Distance`-shaped export.** A `flatfile` writer producing
  `Region.Label` / `Area` / `Sample.Label` / `Effort` / `distance` / `size`, with
  area and region as arguments rather than the hard-coded 5,811 km² of
  `ds_data_dmr.R:248`.
- **`LEGSTAGE` sequence validation.** The handbook (8.A.20) requires that stages
  occur in logical order — `1` cannot follow `2`, `2` cannot follow `5` or a
  blank, `5` cannot follow a blank. `validate_narwc()` checks the code book but
  not the sequence. The fixture originally contained exactly this kind of
  violation (an "end line" immediately before a "break off to circle"), and
  nothing caught it.
- **Performance on a full season.** The cutter is linear now, but
  `attach_circling_sightings()` loops over candidate sightings and
  `segment_midpoints()` splits by segment. Neither has been profiled on hundreds
  of thousands of records.


---

Full citations: [06-references.md](06-references.md).

---

## Detection function: design decided, partly built

Settled 2026-08-10. Two decisions frame the rest:

**Build it general** — support all three distance sources, since the data era is
not yet fixed.

**Data preparation only** — `distsamp` does not wrap `Distance::ds()`. `Distance`
is mature and well documented; a wrapper hides its options and rots against it.
What `distsamp` can offer instead is the NARWC-specific knowledge: which `STRIP`
code book applies, that the Skymaster has a blind spot, that a circling position
is not a perpendicular distance.

### Three sources, three eras

| source | era | gives | state |
|---|---|---|---|
| `ANGLEL`/`ANGLER` | 2022+ (NEAQ) | point distance, `ALT / tan(angle)` | **done**, wired into `sighting_distances()` |
| `STRIP` | pre-2022 | interval | **done**, not yet wired in |
| `S_LAT`/`S_LONG` | 2011+ (NLPSC/WEA) | point distance from exact position | **done**, not yet wired in |

### Done

`narwc_strip_bins()` and `strip_distance()` encode both code books from handbook
8.A.31, resolve the scheme from the survey date (CETAP before October 2011,
NLPSC after), branch on aircraft where the CETAP bins differ, and optionally
apply the Skymaster blind-spot offset.

The stakes are worth stating: `STRIP` code 13 means **1-2 nmi** under CETAP and
**over 4 nmi** under NLPSC. Code 5 differs by a factor of two. Reading a code
with the wrong book silently produces wrong distances, and nothing downstream
would notice.

`exact_distance()` computes the perpendicular distance from `S_LAT`/`S_LONG` to
the trackline, on `gc_bearing()`, `track_bearing()`, and
`cross_track_distance()`. The substantive point is that it *projects onto the
track* rather than measuring straight to the animal as
`original/compute_distance.R` did: a radial distance exceeds the perpendicular
one by however far the aircraft was from abeam, always in the same direction,
and biases density low. The along-track offset is returned alongside the
distance so the size of that correction is visible rather than assumed away.
Details and the four judgement calls are in
[02-implementation.md](02-implementation.md), step 11d.

A fourth source was added after the first three: `circling_distance()` ties a
sighting logged during a circle back to the `LEGSTAGE == 3` break-off record on
the census line and measures from there. Those are real on-effort detections —
the animal was seen from the track-line, which is why the aircraft left it — and
dropping them thins the near-zero end of the distance distribution, where a
detection function is most sensitive. But the position is fixed minutes after
detection, so the animal has moved. They are a *separate and weaker* source, not
more of the same. Step 11e of
[02-implementation.md](02-implementation.md) has the reasoning.

### Remaining

1. ~~**Unify the sources in `sighting_distances()`**~~ — **done.** `sources` is a
   precedence order over `"angle"`, `"exact"`, `"strip"`, `"circling"`;
   `distance_source` records which claimed each row, and `distbegin`/`distend`
   carry the interval for binned rows. Circling is available but not on by
   default. Step 11f of [02-implementation.md](02-implementation.md).
2. ~~**`detection_data()`**~~ — **done.** The `Distance` flatfile:
   `Region.Label` / `Area` / `Sample.Label` / `Effort` / `object` / `distance` /
   `size`, with `distbegin`/`distend` for binned rows and segment covariates on
   request. `area` is required with no default. Every segment appears, including
   those with no detections, because that is how the flatfile records effort
   that produced nothing. Truncation drops detections and keeps their segments.
   Point and interval distances in one table is an error by default, and open
   top bins are dropped. `include_circling` defaults to `FALSE`, and does not
   touch the segment counts — the density-surface side stays on
   `segment_survey(circling = )`.
3. **Left truncation** for the Skymaster blind spot, as `ds(left = ...)` rather
   than by shifting bins, which is the statistically correct treatment. Note the
   interaction recorded in [07-fitting-architecture.md](07-fitting-architecture.md):
   a gamma key function and a left truncation model the same phenomenon, so
   doing both counts the blind spot twice.
4. **A `g(0)` correction slot** at the abundance step — supplied by the analyst,
   not estimated, with its standard error propagated and its components named
   separately. Section 5 of
   [07-fitting-architecture.md](07-fitting-architecture.md).

### Deliberately out of scope, and must be said

**g(0).** Aerial surveys of whales suffer both availability bias, from animals
being submerged, and perception bias, from observers missing animals that were
at the surface. A detection function fitted without correcting for either
assumes `g(0) = 1` and biases density low, badly for a deep-diving species.
`distsamp` should not estimate `g(0)` — but it must not let a user assume it
away either. Whatever `detection_data()` returns should say so in its
documentation.

Worked through properly in
[07-fitting-architecture.md](07-fitting-architecture.md) section 5. The short
version: three separate things present as `g(0) < 1` — the geometric blind spot,
availability, and perception — and only the first is recoverable from a NARWC
extract. Availability needs external dive data; perception needs a
double-observer protocol the standard extract does not record. So the design is
a correction the analyst *supplies*, with its standard error propagated and its
components named separately, rather than an estimator. Correcting for one
component while believing you have corrected for another is how these estimates
go wrong by a factor rather than a percentage.

**Where fitting lives.** Also settled in
[07-fitting-architecture.md](07-fitting-architecture.md): three layers, with the
detection-function and DSM fitting in a separate package and the analysis itself
in a `targets` repository. `distsamp` stops at `detection_data()` and
`segments_as_sf()`.
