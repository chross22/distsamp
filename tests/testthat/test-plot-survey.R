staged <- function() {
  narwcr::flag_effort(narwcr::make_leg_id(example_data(), quiet = TRUE))
}

test_that("each view draws from the stage that provides its column", {
  d <- staged()
  expect_s3_class(plot_survey(d, "effort"), "ggplot")
  expect_s3_class(plot_survey(d, "occupations"), "ggplot")
  expect_s3_class(plot_survey(d, "legstage"), "ggplot")

  d <- split_tracks(point_to_point_effort(d))
  expect_s3_class(plot_survey(d, "tracks"), "ggplot")
})

test_that("a view whose column is missing says which stage adds it", {
  expect_error(plot_survey(example_data(), "effort"), "flag_effort")
  expect_error(plot_survey(example_data(), "tracks"), "split_tracks")
  expect_error(plot_survey(example_data(), "platform"), "make_leg_id")
})

test_that("a missing column sends you to prepare_aerial(), not to one step", {
  # Naming the single function that adds the column is true and is bad advice:
  # the steps are order-dependent. The platform hint is the one that mattered -
  # classifying and filtering before make_leg_id() merges two occupations of a
  # line and turns the ferry between them into effort.
  for (view in c("effort", "tracks", "platform", "occupations")) {
    expect_error(plot_survey(example_data(), view), "prepare_aerial",
                 info = view)
  }
  expect_error(plot_survey(example_data(), "platform"), "never before")
})

test_that("position is required whatever the view", {
  d <- staged()
  d$LATITUDE <- NULL
  expect_error(plot_survey(d, "effort"), "LATITUDE")
})

test_that("thinning takes every nth and says so", {
  d <- staged()
  p <- plot_survey(d, "effort", max_points = 20)
  expect_lte(nrow(p$data), 20)
  expect_match(p$labels$subtitle, "of 113 \\(every \\d+th\\)")
})

test_that("nothing is thinned when it fits", {
  p <- plot_survey(staged(), "effort")
  expect_equal(nrow(p$data), nrow(staged()))
  expect_no_match(p$labels$subtitle, "thinned")
})

test_that("occupations get recycled colours, not one per level", {
  # 8,175 occupations cannot have 8,175 distinguishable colours, and do not
  # need to: what matters is that neighbours differ.
  p <- plot_survey(staged(), "occupations", max_legend = 2)
  expect_lte(length(levels(p$data$.col)), 8)
  expect_match(p$labels$subtitle, "colours repeat")
  expect_equal(p$guides$guides$colour, "none")   # a recycled legend is no legend
})

test_that("few enough occupations keep their own colours and a legend", {
  p <- plot_survey(staged(), "occupations")      # the fixture has 6
  expect_match(p$labels$subtitle, "Each has its own colour")
  expect_false(identical(p$guides$guides$colour, "none"))
})

test_that("the subtitle says what an occupation is, not just how many", {
  # "8175 occupations drawn; 5,787 on none" reads only to someone who already
  # knows both terms, which is not who is looking at the figure.
  sub <- plot_survey(staged(), "occupations")$labels$subtitle
  expect_match(sub, "one pass along one survey line")
  expect_match(sub, "transit, ferrying between lines, circling")
})

test_that("faceting by day happens only where it is readable", {
  d <- staged()                                   # 2 days
  expect_true(length(plot_survey(d, "effort")$facet$params$facets) > 0)

  d$DATE <- as.Date("2024-04-01") + seq_len(nrow(d))   # every record its own day
  expect_equal(length(plot_survey(d, "effort")$facet$params$facets), 0)
})

test_that("records on no occupation are drawn but not joined into one", {
  d <- staged()
  p <- plot_survey(d, "occupations")
  # The main layer holds only records that belong to an occupation.
  expect_false(any(is.na(p$data$LEGNO3)))
  expect_match(p$labels$subtitle, "in grey are on no line")
})

test_that("a view with nothing loose says nothing about it", {
  d <- staged()
  d <- d[!is.na(d$LEGNO3), ]
  expect_no_match(plot_survey(d, "occupations")$labels$subtitle, "in grey")
})

test_that("the positions view needs nothing but a position", {
  # The point of it: a file that has been through none of the pipeline, or
  # whose columns are not what you expected, still draws.
  bare <- example_data()[, c("LATITUDE", "LONGITUDE")]
  p <- plot_survey(bare, "positions")
  expect_s3_class(p, "ggplot")

  # One neutral group: no legend, and not the first palette colour either -
  # bright orange effort reads as though the colour meant something.
  scale <- p$scales$get_scales("colour")
  expect_equal(scale$palette(1), "grey40")

  # Both halves matter. The scale suppresses the legend, and nothing may add a
  # `guides()` override afterwards - that override is what put a lone "position"
  # key back on the figure.
  expect_equal(scale$guide, "none")
  expect_null(p$guides$guides$colour)

  # Every other view refuses this frame, which is what makes it worth having.
  expect_error(plot_survey(bare, "raw"), "LEGTYPE")
})

test_that("sightings are drawn on request and never thinned away", {
  d <- staged()
  expect_length(plot_survey(d, "positions", coastline = FALSE)$layers, 1)

  p <- plot_survey(d, "positions", sightings = TRUE, coastline = FALSE,
                   max_points = 10)
  sight_layer <- p$layers[[length(p$layers)]]
  n_sight <- sum(!is.na(blank_to_na(as.character(d$SPECCODE))))

  # Thinned to 10 effort records, but every sighting is still on the map.
  expect_equal(nrow(sight_layer$data), n_sight)
  expect_match(p$labels$subtitle, "sightings, all of them")
})

test_that("sightings can be narrowed to named species", {
  d <- staged()
  spp <- stats::na.omit(unique(blank_to_na(as.character(d$SPECCODE))))
  skip_if(length(spp) < 2, "fixture has too few species to narrow")

  p <- plot_survey(d, "positions", sightings = spp[1], coastline = FALSE)
  drawn <- p$layers[[length(p$layers)]]$data
  expect_setequal(as.character(drawn$SPECCODE), spp[1])
})

test_that("a day, a month, or a year can be picked out", {
  d <- staged()                                        # 2024-04-01 and -02
  expect_setequal(plot_survey(d, "effort", dates = "2024-04-01")$data$DATE,
                  as.Date("2024-04-01"))
  expect_equal(nrow(plot_survey(d, "effort", months = "April")$data), nrow(d))
  expect_error(plot_survey(d, "effort", years = 1999), "No records fall")
})
