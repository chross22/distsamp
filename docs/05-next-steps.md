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

## 2. A documented profile for the upstream processed format

The upstream processing pipeline emits a "processed, ready for model" CSV that
is not raw NARWC. It carries derived columns that are not NARWC variables at
all:

| Column | Apparently |
|---|---|
| `LEGTYPE_BK` | Kenney's `LEGTYPE`, alongside a different `LEGTYPE` |
| `Effort_Type` | An upstream effort classification |
| `Tr_SIGHTING` | Flag for a sighting made from the trackline |
| `OBSSIGHT` | Observer sighting flag |
| `IS_LAT`, `IS_LONG`, `IS_SPECCODE` | Exact sighting position and species, presumably the handbook's `S_LAT`/`S_LONG` |
| `Date_UTC`, `Time_UTC` | Date and time, already in UTC |

v1 treats these as optional pass-through columns; `LEGTYPE_BK` is aliased to
`LEGTYPE`, and the rest survive if named in `extra_columns`. That works by
arrangement rather than by design. With one of those files in hand,
`read_narwc(profile = ...)` could map them properly, and the `IS_*` columns
would give a second, independent source of sighting position.

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

## 5. Mapping

`original/make_plots.R`, `make_maps.R`, and `map_utils.R` produce the diagnostic
maps — tracklines by date, tracks coloured by `new_trackno`, chopped segments
with their sightings. These are genuinely useful for spotting a segmentation
gone wrong, and `map_utils.R` contains a substantial reimplementation of
`ggspatial::annotation_map_tile` worth preserving.

They belong behind `Suggests` on `ggplot2` and `sf`, as `plot()` methods on
`distsamp_segments` rather than as standalone scripts writing PNGs to a
directory.

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

1. **Unify the sources in `sighting_distances()`**, with a `distance_source`
   column recording which was used per detection — `"angle"`, `"strip"`,
   `"exact"`, `"circling"`. That provenance is not optional: a reviewer will
   ask, and mixing point and interval distances in one fit is a decision the
   analyst must make consciously rather than discover. The pieces are all built
   and independently tested; this is the assembly step, plus a documented
   precedence rule for records carrying more than one source. Where an angle and
   an exact position coexist they are independent measurements of the same
   quantity, so their disagreement is worth surfacing rather than silently
   resolving.
2. **`detection_data()`** — a flatfile `ds()` accepts directly. Must emit
   `distbegin`/`distend` for `STRIP`-derived rows (binned fitting), apply
   truncation **consistently to detections and to the counts used for
   abundance**, and drop the open top bin, which cannot be fitted.

   It must also take **`include_circling`, defaulting to `FALSE`** — track-line
   detections only. A detection function is a model of detection *from the
   track-line under standard search effort*, and a circling position is neither
   measured at the moment of detection nor obtained under that effort. Including
   them has to be an explicit, recorded choice. The mechanism is already there:
   `exact_distance()` and `sighting_distances()` return nothing off the census
   line, `circling_distance()` handles them separately, and `distance_source`
   labels the rows.

   **The spatial model is the opposite case, and is already handled.** Circling
   sightings are animals that were really there, and abundance per segment
   should count them whether or not their distance is usable.
   `attach_circling_sightings()` has done this since v1 under the CETAP
   same-species rule, selected by `segment_survey(circling = )`. The two choices
   are independent — a defensible analysis commonly excludes circling sightings
   from the detection function and includes them in the density surface — so
   they must stay separate arguments, and `detection_data()` must not quietly
   couple them by filtering the segment counts to match the detections it kept.
3. **Left truncation** for the Skymaster blind spot, as `ds(left = ...)` rather
   than by shifting bins, which is the statistically correct treatment.

### Deliberately out of scope, and must be said

**g(0).** Aerial surveys of whales suffer both availability bias, from animals
being submerged, and perception bias, from observers missing animals that were
at the surface. A detection function fitted without correcting for either
assumes `g(0) = 1` and biases density low, badly for a deep-diving species.
`distsamp` should not estimate `g(0)` — but it must not let a user assume it
away either. Whatever `detection_data()` returns should say so in its
documentation.
