# Each ride's power, estimated. The bike has no power meter, so this works
# the power out from what Komoot recorded: how fast the rider went and how
# much they climbed, put through the physics of riding a bicycle.
#
#   Rscript analysis/ride_power.R --db DB --settings content/fitness/bike.json --out FILE
#   Rscript analysis/ride_power.R --self-test
#
# The model is Martin et al. (1998), "Validation of a mathematical model for
# road cycling power" (J Appl Biomech 14:276-291, doi:10.1123/jab.14.3.276):
# measured against an SRM power meter on the road it explained 97% of the
# variation in power, within about 3 W. The power at the pedals is the sum of
# what each of these takes, divided by the drivetrain's efficiency:
#
#   air        0.5 * rho * (CdA + Fw) * v^3           (no wind: air speed = ground speed)
#   tyres      Crr * m * g * cos(theta) * v
#   bearings   v * (91 + 8.7 v) / 1000
#   climbing   m * g * sin(theta) * v
#   speeding   0.5 * (m + I / r^2) * (v_end^2 - v_start^2) / dt
#
# with rho the air's density, CdA the rider's drag area, Fw the wheels' own
# (0.0044 m^2), Crr the tyres' rolling resistance, m the rider, bike and kit,
# theta the slope, I the wheels' inertia (0.14 kg m^2) and r their radius
# (0.311 m). The drivetrain keeps 97.6% of the rider's power.
#
# What it cannot know, and so leaves out: wind, and riding in someone's
# slipstream. A headwind makes the true figure higher, a tailwind or a wheel
# to follow lower. Downhill the rider coasts: a stretch whose sum is below
# zero counts as nothing, not as power given back.
#
# Two ways in, best first:
#   * the ride's profile (Web.Rides.Profile): time, distance and altitude at
#     every point Komoot gives a stranger, about every ten seconds. The sum
#     is worked stretch by stretch, so the stretches ridden fast count for
#     what they cost: air's cost goes with the cube of speed, and a mean
#     speed would make every ride look cheaper than it was.
#   * otherwise the ride's totals: distance, moving time and climb. Coarser,
#     and marked as such.
#
# Inputs, read only: the site's database (rides, and bodyweight from the
# daily check-ins), and the bike's settings, a private file (masses, drag
# area and rolling resistance for each of Komoot's sports). Output: one JSON
# file the site reads (Web.Rides.Power).

suppressPackageStartupMessages({
  library(DBI)
  library(RSQLite)
  library(jsonlite)
})

G <- 9.80665
WHEEL_FW <- 0.0044 # m^2, the wheels' drag area (Martin 1998)
WHEEL_I <- 0.14 # kg m^2, both wheels' moment of inertia
WHEEL_R <- 0.311 # m, a 700c wheel's radius
CHAIN <- 0.976 # the drivetrain's efficiency
STOPPED <- 1.0 # m/s: slower than this is standing, not riding
TOO_FAST <- 20 # m/s (72 km/h): faster is a car, a train or a GPS jump, not riding
FLAT_OUT <- 16 # m/s (58 km/h): faster than this anywhere but downhill is not pedalled
CARRIED <- 0.05 # a ride carried this share of its moving time is a mixed trip: no estimate
GRADE_SPAN <- 60 # m of road the slope is measured over
SHORTEST <- 321.87 # m (0.2 mi, matching Web.Rides): every listed bike ride is estimated
MIN_RIDING_S <- 60 # s of moving time required
SLOWEST <- 2.5 # m/s (9 km/h) moving average: slower is a bike pushed, not ridden
PEAK_WINDOW_S <- 30 # s of riding over which peak power is measured

# The settings when the private file is missing, for a fresh clone: an
# average man on an average road bike. The real ones live in content/.
DEFAULTS <- list(
  rider_kg = 75, temp_c = 15, kit_kg = 1.5,
  sports = list(
    racebike = list(bike_kg = 8.5, cda = 0.32, crr = 0.0045),
    touringbicycle = list(bike_kg = 13, cda = 0.40, crr = 0.006),
    mtb = list(bike_kg = 13.5, cda = 0.45, crr = 0.012),
    mtb_easy = list(bike_kg = 13.5, cda = 0.45, crr = 0.012),
    mtb_advanced = list(bike_kg = 14.0, cda = 0.46, crr = 0.012),
    downhillbike = list(bike_kg = 15.0, cda = 0.48, crr = 0.014)
  )
)

args <- commandArgs(trailingOnly = TRUE)
arg <- function(name, default = NULL) {
  i <- match(name, args)
  if (is.na(i) || i == length(args)) default else args[[i + 1]]
}

# The air's density (kg/m^3) at an altitude (m) and temperature (C): the
# standard atmosphere's fall with height, and the ideal gas's with warmth.
air_density <- function(alt_m, temp_c) {
  1.225 * exp(-alt_m / 8434) * (288.15 / (273.15 + temp_c))
}

# The power (W) at the pedals for stretches of road: v the mean ground speed
# of each (m/s), slope its sin(theta), v0 and v1 the speed at its start and
# end, dt its length in seconds.
pedal_power <- function(v, slope, v0, v1, dt, m, cda, crr, rho) {
  cosine <- sqrt(pmax(0, 1 - slope^2))
  air <- 0.5 * rho * (cda + WHEEL_FW) * v^3
  tyres <- crr * m * G * cosine * v
  bearings <- v * (91 + 8.7 * v) / 1000
  climb <- m * G * slope * v
  speeding <- 0.5 * (m + WHEEL_I / WHEEL_R^2) * (v1^2 - v0^2) / dt
  (air + tyres + bearings + climb + speeding) / CHAIN
}

# Smooth a series over a span of road either side of each point: Komoot's
# altitudes come from a terrain model and step between its cells.
smooth_over <- function(d, y, span) {
  vapply(seq_along(d), function(i) mean(y[abs(d - d[i]) <= span / 2]), numeric(1))
}

# Peak sustained power over PEAK_WINDOW_S of riding time.
peak_from_riding <- function(w, dt, riding) {
  wr <- w[riding]; dtr <- dt[riding]
  if (length(wr) == 0) return(0)
  total_s <- sum(dtr)
  if (total_s <= PEAK_WINDOW_S) return(sum(wr * dtr) / total_s)
  t_end <- cumsum(dtr)
  t_mid <- t_end - dtr / 2
  half <- PEAK_WINDOW_S / 2
  pw <- vapply(seq_along(wr), function(i) {
    in_win <- abs(t_mid - t_mid[i]) <= half
    if (sum(dtr[in_win]) < PEAK_WINDOW_S * 0.6) return(0)
    sum(wr[in_win] * dtr[in_win]) / sum(dtr[in_win])
  }, numeric(1))
  max(pw)
}

# From a profile: stretch by stretch.
from_profile <- function(p, m, cda, crr, temp_c) {
  t <- as.numeric(p$t); d <- as.numeric(p$d); alt <- as.numeric(p$alt)
  if (length(t) < 3) return(NULL)
  alt <- smooth_over(d, alt, GRADE_SPAN)
  dt <- diff(t); dd <- diff(d); da <- diff(alt)
  keep <- dt > 0
  # the profile's distance is over the ground's plan; the road along a slope
  # is a little longer, and the slope's sine is rise over that road
  grade <- ifelse(dd > 0, pmax(-0.3, pmin(0.3, da / pmax(dd, 1e-6))), 0)
  road <- dd * sqrt(1 + grade^2)
  slope <- grade / sqrt(1 + grade^2)
  v <- ifelse(keep, road / dt, 0)
  # a stretch no one pedals: a car's or a train's speed, or racing speed on
  # level road. One trip on record was partly driven, at 114-128 km/h.
  carried <- keep & (v > TOO_FAST | (v > FLAT_OUT & slope > -0.02))
  moving_all <- sum(dt[keep & v >= STOPPED])
  if (moving_all > 0 && sum(dt[carried]) / moving_all > CARRIED) {
    if (sum(dt[carried]) / moving_all <= 0.35) {
      first_c <- which(carried)[1]
      cut_t <- t[first_c] - 60
      keep <- keep & (head(t, -1) < cut_t)
      carried <- carried & keep
    } else {
      return(list(carried = TRUE))
    }
  }
  riding <- keep & v >= STOPPED & !carried
  moving <- sum(dt[riding])
  if (moving < MIN_RIDING_S || sum(road[riding]) / moving < SLOWEST) return(NULL)
  # the speed at each point: the mean of the stretches either side of it
  v_clean <- ifelse(riding, v, 0)
  at <- c(v_clean[1], (head(v_clean, -1) + tail(v_clean, -1)) / 2, v_clean[length(v_clean)])
  v0 <- head(at, -1); v1 <- tail(at, -1)
  rho <- air_density(mean(alt), temp_c)
  w <- pedal_power(v_clean, slope, v0, v1, pmax(dt, 1), m, cda, crr, rho)
  w <- ifelse(riding, pmax(0, w), 0)
  slope_peak <- pmax(-0.15, pmin(0.15, slope))
  w_steady <- pedal_power(v_clean, slope_peak, v_clean, v_clean, 1, m, cda, crr, rho)
  w_steady <- ifelse(riding, pmax(0, w_steady), 0)
  avg_w <- sum(w * dt) / moving
  peak_w <- max(avg_w, peak_from_riding(w_steady, dt, riding))
  list(
    basis = "profile",
    avg_w = avg_w,
    peak_w = peak_w,
    work_kj = sum(w * dt) / 1000,
    moving_s = moving,
    climb_share = sum((m * G * slope * v_clean / CHAIN * dt)[riding & slope > 0 & w > 0]) / max(sum(w * dt), 1),
    rho = rho
  )
}

# From totals: the mean speed while moving, the climb shared over the time.
# Air's cost at a mean speed is less than the mean of its cost, so this reads
# low on rides of changing speed; the profile is preferred wherever there is
# one.
from_totals <- function(r, m, cda, crr, temp_c) {
  moving <- r$time_in_motion_s
  if (is.na(moving) || moving <= 0) moving <- r$duration_s
  if (is.na(moving) || moving < MIN_RIDING_S || is.na(r$distance_m)) return(NULL)
  v <- r$distance_m / moving
  if (v < SLOWEST) return(NULL)
  rho <- air_density(0, temp_c)
  flat <- pedal_power(v, 0, v, v, 1, m, cda, crr, rho)
  climb <- m * G * max(0, ifelse(is.na(r$ascent_m), 0, r$ascent_m)) / moving / CHAIN
  w <- flat + climb
  v_peak <- max(v * 1.35, v + 2.0)
  grade_peak <- min(0.08, max(0.02, ifelse(is.na(r$ascent_m) || r$distance_m <= 0, 0.02, (r$ascent_m / r$distance_m) * 3)))
  slope_peak <- grade_peak / sqrt(1 + grade_peak^2)
  peak_w <- max(w * 1.5, pedal_power(v_peak, slope_peak, v_peak, v_peak, 1, m, cda, crr, rho))
  list(basis = "totals", avg_w = w, peak_w = peak_w, work_kj = w * moving / 1000, moving_s = moving,
       climb_share = climb / w, rho = rho)
}

# The rider's mass on a day: the mean of the morning weights logged in the
# ten days either side of it, else the settings'.
rider_mass <- function(day, weights, fallback) {
  if (nrow(weights) == 0) return(list(kg = fallback, from = "settings"))
  near <- weights$kg[abs(as.numeric(weights$date - day)) <= 10]
  if (length(near) == 0) list(kg = fallback, from = "settings") else list(kg = mean(near), from = "check-ins")
}

read_settings <- function(path) {
  s <- DEFAULTS
  if (!is.null(path) && file.exists(path)) {
    mine <- fromJSON(path, simplifyVector = FALSE)
    for (k in names(mine)) s[[k]] <- mine[[k]]
  }
  s
}

estimate_all <- function(db, settings) {
  con <- dbConnect(SQLite(), db, flags = SQLITE_RO)
  on.exit(dbDisconnect(con))
  # a database from before profiles were kept has none: its rides go by totals
  has_profile <- "profile" %in% dbListFields(con, "rides")
  rides <- dbGetQuery(con, paste(
    "SELECT id, sport, started_at, distance_m, duration_s, time_in_motion_s, ascent_m,",
    if (has_profile) "profile" else "NULL AS profile", "FROM rides"))
  checkins <- if ("fitness_checkins" %in% dbListTables(con)) {
    dbGetQuery(con, "SELECT date, answers FROM fitness_checkins")
  } else {
    data.frame(date = character(), answers = character())
  }
  weights <- data.frame(date = as.Date(character()), kg = numeric())
  for (i in seq_len(nrow(checkins))) {
    lb <- suppressWarnings(as.numeric(fromJSON(checkins$answers[[i]])$bodyweight))
    if (length(lb) == 1 && !is.na(lb) && lb > 50 && lb < 500)
      weights <- rbind(weights, data.frame(date = as.Date(checkins$date[[i]]), kg = lb * 0.45359237))
  }
  out <- list()
  for (i in seq_len(nrow(rides))) {
    r <- rides[i, ]
    bike <- settings$sports[[r$sport]]
    if (is.null(bike)) next # walking, running, e-bikes: no pedal power to estimate
    if (is.na(r$distance_m) || r$distance_m < SHORTEST) next
    day <- as.Date(substr(r$started_at, 1, 10))
    rider <- rider_mass(day, weights, settings$rider_kg)
    m <- rider$kg + bike$bike_kg + settings$kit_kg
    p <- if (!is.na(r$profile) && nchar(r$profile) > 2) fromJSON(r$profile) else NULL
    e <- if (!is.null(p)) from_profile(p, m, bike$cda, bike$crr, settings$temp_c) else NULL
    if (isTRUE(e$carried)) next # part of the trip was not on the bike: no honest estimate
    if (is.null(e)) e <- from_totals(r, m, bike$cda, bike$crr, settings$temp_c)
    if (is.null(e)) next
    out[[length(out) + 1]] <- list(
      id = r$id, basis = e$basis, avg_w = round(e$avg_w, 1), peak_w = round(e$peak_w, 1),
      work_kj = round(e$work_kj, 1), moving_s = round(e$moving_s),
      climb_share = round(e$climb_share, 3), mass_kg = round(m, 1),
      weight_from = rider$from, cda = bike$cda, crr = bike$crr, rho = round(e$rho, 4)
    )
  }
  out
}

# The model's own arithmetic, against values worked by hand.
self_test <- function() {
  check <- function(what, got, want, tol) {
    if (abs(got - want) > tol) stop(sprintf("%s: %.2f, expected %.2f", what, got, want))
    cat(sprintf("ok  %-46s %8.2f\n", what, got))
  }
  rho <- air_density(0, 15)
  check("air density at sea level, 15 C", rho, 1.225, 0.001)
  # 72 kg, 9 m/s on the flat, CdA 0.32, Crr 0.0045: air 0.5*1.225*0.3244*729
  # = 144.85, tyres 28.59, bearings 1.52; /0.976 = 179.2 W
  check("flat, 9 m/s, 72 kg", pedal_power(9, 0, 9, 9, 1, 72, 0.32, 0.0045, rho), 179.2, 0.3)
  # the same at 5% adds 72*g*0.05*9 = 317.8 W at the rider, 325.6 at the pedals
  climb <- pedal_power(9, 0.05, 9, 9, 1, 72, 0.32, 0.0045, rho) - pedal_power(9, 0, 9, 9, 1, 72, 0.32, 0.0045, rho)
  check("added by a 5% climb at 9 m/s", climb, 325.4, 0.6)
  # a steady ride's profile and totals agree
  p <- list(t = seq(0, 3600, 10), d = seq(0, 3600, 10) * 8, alt = rep(20, 361))
  a <- from_profile(p, 72, 0.32, 0.0045, 15)$avg_w
  b <- from_totals(list(time_in_motion_s = 3600, duration_s = 3600, distance_m = 28800, ascent_m = 0), 72, 0.32, 0.0045, 15)$avg_w
  check("steady ride: profile vs totals (W apart)", abs(a - b), 0, 1.5)
  # a ride with a stretch in a car is no ride to estimate
  car <- list(t = seq(0, 3600, 10), d = c(seq(0, 1800, 10) * 8, 14400 + seq(10, 1800, 10) * 30), alt = rep(20, 361))
  if (!isTRUE(from_profile(car, 72, 0.32, 0.0045, 15)$carried)) stop("a driven stretch was counted as riding")
  cat("ok  a trip partly driven is not estimated\n")
  invisible(TRUE)
}

if ("--self-test" %in% args) {
  self_test()
} else {
  db <- arg("--db"); out <- arg("--out")
  if (is.null(db) || is.null(out)) stop("usage: ride_power.R --db DB --settings FILE --out FILE")
  settings <- read_settings(arg("--settings"))
  rides <- estimate_all(db, settings)
  write_json(
    list(
      generated_at = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
      model = list(
        name = "Martin et al. 1998", doi = "10.1123/jab.14.3.276",
        drivetrain = CHAIN, wheel_fw = WHEEL_FW, temp_c = settings$temp_c,
        not_counted = c("wind", "drafting")
      ),
      rides = rides
    ),
    out, auto_unbox = TRUE, digits = NA, pretty = TRUE
  )
  cat(length(rides), "rides estimated\n")
}
