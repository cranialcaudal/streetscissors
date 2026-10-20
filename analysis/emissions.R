# emissions.R
# Emissions by mode of transport, controlling for distance.
#
# Run locally; commit the JSON it writes. R does not run in production: the
# site reads the JSON and draws the charts itself.
#
#   Rscript analysis/emissions.R
#
# The script is in three acts, in the order you would do this by hand:
#
#   1. DATA      one row per mode of transport, and the reference tables
#                (grids, diets) the analysis multiplies against
#   2. ANALYSIS  turn grams per mile into pounds per month and per year, and
#                accumulate those over a working life
#   3. OUTPUT    a plot to look at, and the JSON the website consumes
#
# Units, once, so nothing below has to guess: emission rates are grams of
# CO2-equivalent per passenger-mile, and everything a reader sees is pounds
# of CO2e per period.
#
# TWO QUESTIONS, TWO FRAMES. Do not mix them.
#
#   FRAME A ("same trip"): hold distance fixed, vary mode. A treatment
#   effect. Answers "what does covering THIS trip cost by each mode?"
#
#   FRAME B ("as observed"): each mode at its observed mean trip distance
#   (NHTS). Confounded: mode choice is endogenous to distance. Bike
#   commuters emit less partly because they live closer. Answers "what do
#   people who use this mode actually emit?" which is a different and
#   weaker claim. Label it as such or do not ship it.
#
# NO LOG SCALE. Considered once Plane widened the range, but Walk and
# Bicycle are exactly 0 g/mi (mechanical) by construction, and log(0) is
# undefined -- a log axis cannot render them at all, on a bar chart or a
# line chart. Standard chart guidance already discourages log axes on bar
# charts even without a zero problem (no natural baseline, so where the axis
# starts becomes an editorial choice).

library(jsonlite)
library(dplyr)
library(tidyr)
library(ggplot2)

# =============================================================================
# 1. DATA
# =============================================================================

# --- Trip and schedule assumptions -------------------------------------------

# Frame A's fixed commute. Named once so R, the emitted JSON, and the
# client-side JS all read one declared value instead of three copies of the
# same magic number.
frame_a_one_way_miles <- 8

# A commute is there and back.
trips_per_commute_day <- 2

# 52 weeks minus about two weeks of leave and holidays.
commute_days_per_year <- 250
commute_days_per_month <- commute_days_per_year / 12

# US customary output, because every other number on the page is imperial.
pounds_per_kilogram <- 2.20462

# --- Burning a gallon of fuel ------------------------------------------------
# EPA, Office of Transportation and Air Quality (EPA-420-F-18-008).
grams_co2_per_gallon_gasoline <- 8887

# Extraction, refining and distribution, on top of what leaves the tailpipe.
upstream_fuel_multiplier <- 1.15

grams_per_mile_from_mpg <- function(miles_per_gallon) {
  round(grams_co2_per_gallon_gasoline / miles_per_gallon * upstream_fuel_multiplier)
}

# --- The electricity grid ----------------------------------------------------
# Anything that plugs in is only as clean as what it plugs into, so grid modes
# are not stored as a fixed rate. They carry kWh per mile and get multiplied
# by whichever grid the reader picks.
#
# Intensities are EPA eGRID via the Greenhouse Gas Equivalencies Calculator,
# converted from lb CO2/MWh. MROE is a real coal-heavy subregion, not a
# thought experiment.
grams_per_kwh_from_lb_per_mwh <- function(lb_per_mwh) {
  round(lb_per_mwh * 453.592 / 1000, 1)
}

grid_intensities <- tibble(
  name      = c("California",  "US average", "Coal-heavy"),
  lb_per_mwh = c(      497.4,        823.1,       1402.0),
  is_default = c(       TRUE,        FALSE,        FALSE)
) |>
  mutate(g_per_kwh = grams_per_kwh_from_lb_per_mwh(lb_per_mwh))

default_grid_g_per_kwh <- grid_intensities |>
  filter(is_default) |>
  pull(g_per_kwh)

# --- Food energy -------------------------------------------------------------
# CONTESTED, and off by default in the UI. Human-powered travel is only
# "zero emission" if you do not eat more to fuel it, and two arguable
# assumptions carry this whole block:
#   (1) caloric compensation is complete (the literature says partial);
#   (2) marginal calories match average dietary carbon intensity.
#
# Net kcal above resting, per mile. Walking costs MORE per mile than cycling
# because the bicycle is the more efficient machine.
kcal_per_mile <- c(walk = 50, bike = 30, ebike = 12)

# g CO2e per kcal, by diet. A US-average food footprint of ~2.5 t CO2e/yr at
# ~2,500 kcal/day works out to ~2.7 g/kcal.
diet_intensities <- c(vegetarian = 1.2, us_average = 2.7, beef_heavy = 4.5)

# --- Energy draw of the things that plug in ----------------------------------
# EPA fueleconomy.gov rated consumption, which is measured at the wall and so
# already includes charging losses.
#
# The e-bike figure is not an EPA rating (they do not test bicycles); it is a
# realistic 21 Wh/mi, which lands this model within about a gram of the
# ITF/OECD "Good to Go?" (2020) numbers the e-bike used to carry as hardcoded
# constants. That agreement is the reason to trust the restructure.
kwh_per_mile <- c(
  ebike  = 0.021,
  tesla  = 29 / 100,  # Model 3 AWD, 29 kWh/100 mi
  rivian = 54 / 100   # R1T / R1S, 54 kWh/100 mi
)

grid_grams_per_mile <- function(vehicle, g_per_kwh = default_grid_g_per_kwh) {
  round(kwh_per_mile[[vehicle]] * g_per_kwh)
}

# --- Observed trip distances -------------------------------------------------
# FHWA, Chapter 3: Travel (23 CPR), citing NHTS 2009: "a walk trip only
# averaged 0.7 miles and a bike trip 2.2 miles"; vehicle trips averaged above
# 5 miles. These are TRIP averages, not commute-specific -- commutes run
# longer. NA means the survey has no comparable figure (it does not track
# commercial flights), and Frame B falls back to Frame A's distance.
observed_one_way_miles <- c(
  Walk = 0.7, Bicycle = 2.2, `E-bike` = 3.5, Bus = 5.5,
  Train = 12.0, Car = 15.0, Pickup = 15.0
)

# --- One row per mode --------------------------------------------------------
# `energy_source` decides how the rate is computed downstream:
#
#   food   zero mechanically; the only cost is what the rider eats
#   grid   kwh_per_mile x the selected grid intensity
#   fixed  a published per-passenger rate, already averaged over occupancy
#   occ    a private vehicle's own rate, borne by its occupants
#
# `food_key` and `ev_key` are lookup keys into kcal_per_mile and kwh_per_mile;
# NA means the mode has no such component.
#
# `nhts_distance_as` names which surveyed trip length supplies this mode's
# Frame B distance. Usually itself, but the electric cars borrow from their
# gasoline equivalents (NHTS surveys cars, not drivetrains), and Plane is NA
# because the survey does not track commercial flights at all.
# `grams_per_mile` is the mechanical rate on the default grid: what the site
# renders before the reader touches anything. Each one shows its own
# derivation rather than arriving as a bare number from somewhere else.
modes <- tribble(
  ~name,     ~sub,                       ~energy_source, ~grams_per_mile,             ~food_key, ~ev_key,  ~nhts_distance_as,
  "Walk",    "0.7 mi avg trip",          "food",         0,                           "walk",    NA,       "Walk",
  "Bicycle", "2.2 mi avg trip",          "food",         0,                           "bike",    NA,       "Bicycle",
  "E-bike",  "21 Wh/mi, grid-dependent", "grid",         grid_grams_per_mile("ebike"), "ebike",  "ebike",  "E-bike",
  "Train",   "Amtrak average",           "fixed",        65,                          NA,        NA,       "Train",
  "Bus",     "9 riders average",         "fixed",        105,                         NA,        NA,       "Bus",
  "Car",     "22.0 mpg fleet avg",       "occ",          grams_per_mile_from_mpg(22.0), NA,      NA,       "Car",
  "Pickup",  "19.2 mpg fleet avg",       "occ",          grams_per_mile_from_mpg(19.2), NA,      NA,       "Pickup",
  "Tesla",   "Model 3, 29 kWh/100 mi",   "grid",         grid_grams_per_mile("tesla"), NA,       "tesla",  "Car",
  "Rivian",  "R1T, 54 kWh/100 mi",       "grid",         grid_grams_per_mile("rivian"), NA,      "rivian", "Pickup",
  "Plane",   "short-haul, <300 mi",      "fixed",        207,                         NA,        NA,       NA
) |>
  mutate(
    observed_miles = unname(observed_one_way_miles[nhts_distance_as]),
    kwh_per_mile = unname(kwh_per_mile[ev_key])
  )

# Where each number came from, kept beside the data rather than in a comment
# so it travels with it into the JSON and onto the page.
mode_sources <- c(
  Walk = "Zero mechanical emissions. Food energy adds ~135 g/mi on a
          US-average diet if compensation is complete; see note.",
  Bicycle = "Zero mechanical emissions. ~80 g/mi from food on a US-average
             diet. Lower than walking per mile: the bicycle is the more
             efficient machine.",
  `E-bike` = "21 Wh/mi against EPA eGRID intensities. Lands at ~5 g/mi on the
              California grid and ~13 on a coal-heavy one, within a gram of
              the ITF/OECD 'Good to Go?' (2020) figures it used to carry as
              constants. With food accounting on and a meat-heavy diet, the
              e-bike beats the bicycle.",
  Train = "Amtrak Sustainability Report (2023); BTS NTS Table 4-20.
           Electrified commuter rail 30-50; diesel long-haul 80-100.",
  Bus = "BTS NTS Table 4-20; EPA GHG Inventory (2024). Range 80-150 by
         occupancy and fuel.",
  Car = "EPA-420-F-18-008. 8887 / 22.0 = 404 g tailpipe, +15% upstream.
         Divided by occupancy.",
  Pickup = "EPA Automotive Trends Report (2023). 8887 / 19.2 = 463 g tailpipe,
            +15% upstream. Top-selling US vehicle class.",
  Tesla = "EPA fueleconomy.gov rated consumption, measured at the wall.
           ~65 g/mi on the California grid, ~108 US average, ~184 coal-heavy:
           at the clean end it matches Amtrak, at the dirty end it lands near
           a short-haul flight.",
  Rivian = "EPA fueleconomy.gov rated consumption. An electric pickup is still
            a pickup: ~122 g/mi on the California grid but ~343 on a
            coal-heavy one, which is most of the way to the gasoline car it
            replaced. Electrification and grid decarbonization are one
            question, not two.",
  Plane = "EPA GHG Emission Factors Hub (2025), short-haul (<300 mi) factor:
           0.207 kg CO2e/passenger-mile, higher per mile than medium- or
           long-haul (0.129, 0.163) because takeoff and climb burn
           disproportionate fuel on short hops."
)

modes <- modes |> mutate(source_note = unname(mode_sources[name]))

# =============================================================================
# 2. ANALYSIS
# =============================================================================

# A rate in grams per mile becomes pounds over a period by way of the round
# trip and the number of days it is made.
pounds_per_month <- function(grams_per_mile, one_way_miles) {
  grams_per_day <- grams_per_mile * one_way_miles * trips_per_commute_day
  round(grams_per_day * commute_days_per_month / 1000 * pounds_per_kilogram, 1)
}

pounds_per_year <- function(grams_per_mile, one_way_miles) {
  grams_per_day <- grams_per_mile * one_way_miles * trips_per_commute_day
  round(grams_per_day * commute_days_per_year / 1000 * pounds_per_kilogram, 1)
}

# The two frames, side by side, on the same rows. Frame B falls back to Frame
# A's distance where the survey has no comparable figure (Plane).
emissions_by_frame <- modes |>
  mutate(
    frame_a_miles = frame_a_one_way_miles,
    frame_b_miles = coalesce(observed_miles, frame_a_one_way_miles),
    frame_a_lb_per_month = pounds_per_month(grams_per_mile, frame_a_miles),
    frame_a_lb_per_year  = pounds_per_year(grams_per_mile, frame_a_miles),
    frame_b_lb_per_month = pounds_per_month(grams_per_mile, frame_b_miles),
    frame_b_lb_per_year  = pounds_per_year(grams_per_mile, frame_b_miles)
  )

# Figure 2: the same Frame A commute, accumulated. Mechanical emissions only,
# food accounting off, matching the rest of the script's defaults. Walk and
# Bicycle are both 0 here and will legitimately overlap as flat lines -- that
# is correct, not a bug.
cumulative_years <- c(0, 1, 5, 10, 20)

cumulative_by_mode <- emissions_by_frame |>
  select(name, energy_source, food_key, frame_a_lb_per_year) |>
  crossing(elapsed_years = cumulative_years) |>
  mutate(cumulative_lb = round(frame_a_lb_per_year * elapsed_years, 1)) |>
  arrange(match(name, modes$name), elapsed_years)

# =============================================================================
# 3. OUTPUT
# =============================================================================

# --- Read it in the terminal -------------------------------------------------

print_frame <- function(data, label, miles, lb_per_month, lb_per_year) {
  cat("\n---", label, "---\n")

  data |>
    transmute(
      line = sprintf(
        "%-9s %5.1f mi  %4s g/mi  %6.1f lb/mo  %7.1f lb/yr",
        name, {{ miles }}, grams_per_mile, {{ lb_per_month }}, {{ lb_per_year }}
      )
    ) |>
    pull(line) |>
    cat(sep = "\n")

  cat("\n")
}

print_frame(emissions_by_frame, "FRAME A: same trip, held constant across modes",
            frame_a_miles, frame_a_lb_per_month, frame_a_lb_per_year)

print_frame(emissions_by_frame, "FRAME B: each mode at its observed distance (CONFOUNDED)",
            frame_b_miles, frame_b_lb_per_month, frame_b_lb_per_year)

# --- Look at it --------------------------------------------------------------
# The website draws its own charts from the JSON below; this plot is here so
# that running the script shows you the same numbers, and so the shape can be
# checked without a browser.

frame_a_plot <- emissions_by_frame |>
  mutate(name = factor(name, levels = rev(modes$name))) |>
  ggplot(aes(x = name, y = frame_a_lb_per_month, fill = energy_source)) +
  geom_col(width = 0.7) +
  geom_text(aes(label = sprintf("%.1f", frame_a_lb_per_month)),
            hjust = -0.15, size = 3.2) +
  coord_flip() +
  scale_y_continuous(expand = expansion(mult = c(0, 0.15))) +
  labs(
    title = sprintf("Pounds of CO2e per month, %g-mile one-way commute",
                    frame_a_one_way_miles),
    subtitle = "Frame A: same trip by every mode. Higher is worse.",
    x = NULL, y = "lb CO2e per month", fill = "Energy source"
  ) +
  theme_minimal(base_size = 11)

ggsave("priv/static/figures/emissions-frame-a.png", frame_a_plot,
       width = 8, height = 5, dpi = 150)

cat("\nWrote emissions-frame-a.png\n")

# --- Hand it to the website --------------------------------------------------
# The JSON keys below are a contract with lib/web/blog/embeds.ex and
# assets/js/emissions_controls.js. The R names above are chosen for reading;
# these are chosen for the consumers, so the mapping happens here, once.
# Absent values are dropped rather than emitted as null, which is what the
# readers expect (a missing `observed` means "no comparable figure").

drop_missing <- function(x) x[!vapply(x, function(v) all(is.na(v)), logical(1))]

modes_json <- lapply(seq_len(nrow(modes)), function(i) {
  row <- modes[i, ]

  drop_missing(list(
    name         = row$name,
    sub          = row$sub,
    base         = row$grams_per_mile,
    type         = row$energy_source,
    kwh_per_mile = row$kwh_per_mile,
    food_key     = row$food_key,
    observed     = row$observed_miles,
    src          = row$source_note
  ))
})

series_json <- lapply(modes$name, function(mode_name) {
  rows <- cumulative_by_mode |> filter(name == mode_name)

  drop_missing(list(
    name     = mode_name,
    type     = rows$energy_source[[1]],
    lb       = rows$cumulative_lb,
    food_key = rows$food_key[[1]]
  ))
})

grids_json <- lapply(seq_len(nrow(grid_intensities)), function(i) {
  row <- grid_intensities[i, ]
  entry <- list(name = row$name, g_per_kwh = row$g_per_kwh)
  if (row$is_default) entry$default <- TRUE
  entry
})

figure <- list(
  title = "Emissions by mode, controlling for distance",
  units = "g CO2e / passenger-mile; lb CO2e / period",
  frame_a_one_way_mi = frame_a_one_way_miles,
  kg_to_lb = pounds_per_kilogram,
  frames = list(
    a = list(
      key   = "same_trip",
      label = "Same trip",
      note  = "Distance held constant. A counterfactual: what this trip
               costs by each mode."
    ),
    b = list(
      key   = "as_observed",
      label = "As observed",
      note  = "Each mode at its observed mean trip distance (NHTS 2009).
               Confounded: mode choice is endogenous to distance. Bike
               commuters emit less partly because they live closer. This
               compares lifestyles, not modes."
    )
  ),
  modes = modes_json,
  grids = grids_json,
  diets = as.list(diet_intensities),
  kcal  = as.list(kcal_per_mile),
  work_days = list(month = commute_days_per_month, year = commute_days_per_year),
  cumulative = list(
    commute_one_way_mi = frame_a_one_way_miles,
    note = "Same one-way commute as Frame A, every mode. Mechanical
            emissions only; food-energy accounting off, as above. The
            gap shown is mechanical emissions only, not a claim that
            walking or cycling has zero cost.",
    years = cumulative_years,
    series = series_json
  ),
  excluded = list(
    vehicle_manufacture = "Embodied manufacturing emissions excluded for
      ALL modes, consistently. Amortized over lifetime mileage this
      penalizes the bicycle disproportionately at low annual mileage. It
      also flatters the electric cars most: battery production is the
      single largest asterisk on any EV lifecycle claim, and an EV starts
      its life further in debt than the gasoline car it replaced. Counting
      only what comes out of the tailpipe or the wall is the consistent
      choice here, not the generous-to-EVs one by accident.",
    infrastructure = "Roadway embodied carbon excluded for all modes.
      Cement is ~8% of global CO2. The 17-mile trench emitted before a
      single car drove on it. No per-passenger-mile figure for any mode
      captures this.",
    cold_start = "Cold starts contribute ~64% of trip CO, 68% HC, 58% NOx,
      but only ~4.5% of CO2 (Atmosphere 2023, doi:10.3390/atmos14010035).
      Negligible for this chart; decisive for local air quality.",
    induced_demand = "Capacity generates trips. System-level, not per-trip.",
    aviation_non_co2 = "Plane's figure is CO2 only. Contrail cirrus, NOx,
      and other non-CO2 effects account for roughly two-thirds of
      aviation's total effective radiative forcing, not a fraction of it
      (Lee et al. 2021, doi:10.1016/j.atmosenv.2020.117834). No other
      mode here has an excluded effect anywhere near that large relative
      to what is counted."
  ),
  citation = paste(
    "U.S. Environmental Protection Agency, Office of Transportation and Air",
    "Quality. Greenhouse Gas Emissions from a Typical Passenger Vehicle.",
    "EPA-420-F-18-008."
  ),
  citation_url = paste0(
    "https://www.epa.gov/greenvehicles/",
    "greenhouse-gas-emissions-typical-passenger-vehicle"
  ),
  distance_source = paste(
    "Federal Highway Administration, Chapter 3: Travel (23 CPR), citing",
    "National Household Travel Survey 2009. Walk trips average 0.7 mi;",
    "bike trips 2.2 mi; vehicle trips above 5 mi."
  ),
  distance_source_url = "https://www.fhwa.dot.gov/policy/23cpr/chap3.cfm",
  generated = format(Sys.Date(), "%Y-%m-%d")
)

write_json(figure, "priv/static/figures/emissions.json",
           auto_unbox = TRUE, pretty = TRUE)

cat("Wrote emissions.json\n")
