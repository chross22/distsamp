# Package index

## Segmenting a survey

Turning track lines into effort segments ready for Distance and dsm —
each with a location, an amount of effort, and counts of what was seen
along it.

- [`cut_segments()`](https://camilleross.org/distsamp/reference/cut_segments.md)
  : Cut tracks into segments
- [`line_effort()`](https://camilleross.org/distsamp/reference/line_effort.md)
  : Effort per survey line
- [`plan_segments()`](https://camilleross.org/distsamp/reference/plan_segments.md)
  : Plan how many segments each track carries
- [`point_to_point_effort()`](https://camilleross.org/distsamp/reference/point_to_point_effort.md)
  : Accumulate point-to-point survey effort
- [`segment_midpoints()`](https://camilleross.org/distsamp/reference/segment_midpoints.md)
  : Locate the along-track midpoint of each segment
- [`segment_sightings()`](https://camilleross.org/distsamp/reference/segment_sightings.md)
  : Summarise sightings and conditions by segment
- [`segment_survey()`](https://camilleross.org/distsamp/reference/segment_survey.md)
  : Segment a line-transect survey
- [`segments_as_sf()`](https://camilleross.org/distsamp/reference/segments_as_sf.md)
  : Convert segments to spatial features
- [`segments_wide()`](https://camilleross.org/distsamp/reference/segments_wide.md)
  : Segment table with one column per species
- [`split_tracks()`](https://camilleross.org/distsamp/reference/split_tracks.md)
  : Split survey lines at breaks in effort
- [`track_effort()`](https://camilleross.org/distsamp/reference/track_effort.md)
  : Summarise effort by continuous track
- [`write_segments()`](https://camilleross.org/distsamp/reference/write_segments.md)
  : Write segmentation results to CSV

## Distances and geometry

Perpendicular distance is what a detection function consumes. Where the
survey recorded declination angles, it can be computed exactly.

- [`circling_distance()`](https://camilleross.org/distsamp/reference/circling_distance.md)
  : Perpendicular distances for sightings made while circling

- [`cross_track_distance()`](https://camilleross.org/distsamp/reference/cross_track_distance.md)
  : Perpendicular distance from a track to an exact sighting position

- [`detection_data()`](https://camilleross.org/distsamp/reference/detection_data.md)
  :

  Build a flatfile for `Distance::ds()`

- [`dist_methods()`](https://camilleross.org/distsamp/reference/dist_methods.md)
  : Distance methods available

- [`exact_distance()`](https://camilleross.org/distsamp/reference/exact_distance.md)
  : Perpendicular distances from exact sighting positions

- [`gc_bearing()`](https://camilleross.org/distsamp/reference/gc_bearing.md)
  : Initial great-circle bearing between positions

- [`gc_distance()`](https://camilleross.org/distsamp/reference/gc_distance.md)
  : Great-circle distance between positions

- [`gc_interpolate()`](https://camilleross.org/distsamp/reference/gc_interpolate.md)
  : Interpolate a position along a great circle

- [`perp_distance()`](https://camilleross.org/distsamp/reference/perp_distance.md)
  : Perpendicular distance from a declination angle

- [`sighting_distances()`](https://camilleross.org/distsamp/reference/sighting_distances.md)
  : Perpendicular distances for a survey data frame

- [`strip_distance()`](https://camilleross.org/distsamp/reference/strip_distance.md)
  : Convert STRIP codes to distance intervals

- [`track_bearing()`](https://camilleross.org/distsamp/reference/track_bearing.md)
  : Local bearing of the track-line at each record

## Circling and reflights

An aircraft that circles a sighting is no longer on effort. These find
those passages and attach their sightings to the right segment.

- [`attach_circling_sightings()`](https://camilleross.org/distsamp/reference/attach_circling_sightings.md)
  : Attach sightings made while circling to the segment they came from
- [`filter_days()`](https://camilleross.org/distsamp/reference/filter_days.md)
  : Keep the survey days you want to look at
- [`flag_circling()`](https://camilleross.org/distsamp/reference/flag_circling.md)
  : Flag records made while circling
- [`reflight_summary()`](https://camilleross.org/distsamp/reference/reflight_summary.md)
  : How much of the survey was re-flown

## Reading NARWC data

Re-exported from narwcr so a survey can be read and segmented without
loading both packages.

- [`validate_narwc()`](https://camilleross.org/distsamp/reference/validate_narwc.md)
  : Check survey data against the handbook and against distance sampling

## Preparing and inspecting

Aerial-specific preparation, a pipeline diagnosis that reports rather
than stops, and plots for looking at what came out.

- [`crop_to_bbox()`](https://camilleross.org/distsamp/reference/crop_to_bbox.md)
  : Restrict data to a bounding box
- [`diagnose_pipeline()`](https://camilleross.org/distsamp/reference/diagnose_pipeline.md)
  : Diagnose common reasons a segmentation might be wrong before you
  trust it
- [`distsamp_checks()`](https://camilleross.org/distsamp/reference/distsamp_checks.md)
  : Checks that only matter for distance sampling
- [`plot(`*`<distsamp_segments>`*`)`](https://camilleross.org/distsamp/reference/plot.distsamp_segments.md)
  : Diagnostic plots for a segmentation
- [`plot_survey()`](https://camilleross.org/distsamp/reference/plot_survey.md)
  : Look at the survey partway through the pipeline
- [`plot_survey_panel()`](https://camilleross.org/distsamp/reference/plot_survey_panel.md)
  : Several views of a survey, side by side
- [`prepare_aerial()`](https://camilleross.org/distsamp/reference/prepare_aerial.md)
  : Get a NARWC extract ready to segment
