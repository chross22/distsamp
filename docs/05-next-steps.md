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

`original/DataExploration.R` reads `MEDMR_proc_all_formodel_*.csv` and
`NARWC_proc_all_formodel_*.csv`, which are not raw NARWC. They carry derived
columns that are not NARWC variables at all:

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
`read_narwc(profile = "medmr")` could map them properly, and the `IS_*` columns
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

- **`STRIP` to right-angle distance,** for surveys predating the 2022 switch to
  angles. The intervals come from calibrated
  markings on the observation bubble and wing struts (Kenney and Scott 1981);
  handbook 8.A.31 defines *two* interval code books — one for CETAP and the WEA surveys, another for NLPSC/MassCEC from
  October 2011 — and which applies depends on the platform (AT-11 versus
  Skymaster) and the year. Odd codes are the port side, even the starboard. A
  correct conversion needs `PLATFORM` and the survey date, and should return an
  interval rather than a point, so that `Distance` can fit to binned data.
- **Truncation and binning.** `Distance::ds()` wants a truncation distance, and
  `STRIP`-derived distances are intervals rather than points, so binned fitting
  is needed for older data.
- **Exact sighting positions.** Where `S_LAT`/`S_LONG` exist (8.A.33, 8.A.34),
  perpendicular distance can be computed directly against the trackline, as
  `original/compute_distance.R` did with `geosphere::distHaversine`. That is the
  better estimate where available and a check on `STRIP` where both exist.
- Wrappers around `Distance::ds()` (Miller et al. 2019), and the multi-year
  fitting from `original/detectionFunctionMultipleYears.R`.

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
