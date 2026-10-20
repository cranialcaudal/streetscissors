# fitness_models.R — the Get Sharp block's Stage 0 models (N-of-1).
#
# analysis/README.md explains the plan in plain words. Stage 0 runs on any amount of
# data and says when it has too little:
#
#   1. Banister impulse-response, per lift: e1RM as fitness minus fatigue,
#      each an exponentially decaying sum of the daily training load
#      (Banister et al., 1975), fitted by optim(L-BFGS-B). The residual,
#      observed minus fitted, is the day's readiness.
#   2. Acute:chronic workload ratio per movement pattern (Gabbett, 2016),
#      7 days over the 28-day weekly average, with the rides (Komoot) as an
#      endurance load beside the lifts; and a retrospective look at the days
#      before the October 2026 Achilles flare when its date is given.
#   3. Residual anomalies: the generalised ESD test (Rosner, 1983) on the
#      Banister residuals, written out here; an IQR fence when n < 15.
#
# Stage 1 (8 weeks of data) and Stage 2 (26 weeks) are gated in code: they
# skip with a message until the data is there, and their packages (brms,
# glmnet, bsts) are not needed until then.
#
# Inputs:
#   - the training log as CSV from `mix fitness.export` (Web.Fitness.Export
#     parses the log; this file does not parse it a second time);
#   - the live database, read-only, for rides and check-ins;
#   - the block file, for each lift's movement pattern.
#
# Base R, DBI, RSQLite, ggplot2, dplyr and jsonlite only.

suppressPackageStartupMessages({
  library(DBI)
  library(dplyr)
})

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0 || (length(a) == 1 && is.na(a))) b else a

# ── Inputs ─────────────────────────────────────────────────────────────

#' The block file's frontmatter as a named list of strings.
read_block <- function(path) {
  if (!file.exists(path)) return(NULL)
  lines <- readLines(path, warn = FALSE)
  fence <- which(lines == "---")
  if (length(fence) < 2) return(NULL)
  meta <- lines[(fence[1] + 1):(fence[2] - 1)]
  kv <- regmatches(meta, regexec("^([^:]+): (.*)$", meta))
  kv <- Filter(function(m) length(m) == 3, kv)
  stats::setNames(lapply(kv, `[`, 3), vapply(kv, `[`, "", 2))
}

#' Each block lift's slug and pattern, from `lifts:`.
block_lifts <- function(block) {
  if (is.null(block$lifts)) return(data.frame(exercise_slug = character(), pattern = character()))
  parts <- trimws(strsplit(block$lifts, ";")[[1]])
  bits <- strsplit(parts, "\\s+")
  ok <- vapply(bits, length, 0L) == 4
  data.frame(
    exercise_slug = vapply(bits[ok], `[`, "", 1),
    pattern = vapply(bits[ok], `[`, "", 4),
    stringsAsFactors = FALSE
  )
}

#' The training log from `mix fitness.export`, with each block lift's pattern.
read_logs <- function(csv, lifts) {
  if (!file.exists(csv)) stop("no training log at ", csv, ": run `mix fitness.export` first")
  logs <- utils::read.csv(csv, na.strings = "NA", stringsAsFactors = FALSE)
  if (nrow(logs) == 0) {
    logs$pattern <- character()
    logs$date <- as.Date(character())
    return(logs)
  }
  logs$date <- as.Date(logs$date)
  merge(logs, lifts, by = "exercise_slug", all.x = TRUE)
}

#' Rides and check-ins from the database, opened read-only. A database
#' without a table answers an empty frame for it.
read_db <- function(db_path) {
  empty <- list(
    rides = data.frame(date = as.Date(character()), minutes = numeric(), km = numeric()),
    checkins = data.frame(date = as.Date(character()), pain = integer())
  )
  if (is.null(db_path) || !file.exists(db_path)) return(empty)

  con <- DBI::dbConnect(RSQLite::SQLite(), db_path, flags = RSQLite::SQLITE_RO)
  on.exit(DBI::dbDisconnect(con))
  tables <- DBI::dbListTables(con)

  rides <- if ("rides" %in% tables) {
    # Pacific day of each activity: the database keeps UTC.
    r <- DBI::dbGetQuery(con, "SELECT started_at, distance_m, duration_s FROM rides WHERE distance_m >= 321.869")
    if (nrow(r)) {
      t <- as.POSIXct(r$started_at, tz = "UTC", tryFormats = c("%Y-%m-%dT%H:%M:%S", "%Y-%m-%d %H:%M:%S"))
      data.frame(
        date = as.Date(format(t, tz = "America/Los_Angeles", "%Y-%m-%d")),
        minutes = r$duration_s / 60,
        km = r$distance_m / 1000
      )
    } else empty$rides
  } else empty$rides

  # One row a day; the answers are a JSON map keyed by the check's id (the
  # checks themselves are content/fitness/checkins.md). Spread wide here:
  # a column per check, NA where a day did not answer it.
  checkins <- if ("fitness_checkins" %in% tables &&
                  "answers" %in% DBI::dbListFields(con, "fitness_checkins")) {
    c <- DBI::dbGetQuery(con, "SELECT date, answers, note FROM fitness_checkins ORDER BY date")
    if (nrow(c)) {
      answers <- lapply(c$answers, function(j) jsonlite::fromJSON(j %||% "{}"))
      ids <- sort(unique(unlist(lapply(answers, names))))
      wide <- as.data.frame(
        stats::setNames(lapply(ids, function(id) vapply(answers, function(a) as.character(a[[id]] %||% NA), "")), ids),
        stringsAsFactors = FALSE, check.names = FALSE
      )
      cbind(data.frame(date = as.Date(c$date), note = c$note), wide)
    } else empty$checkins
  } else empty$checkins

  list(rides = rides, checkins = checkins)
}

#' Weeks with any data in them, counted from the first entry's week: a
#' block of eight weeks counts 8 even when its last entry is a Friday.
weeks_of_data <- function(dates) {
  dates <- dates[!is.na(dates)]
  if (!length(dates)) return(0)
  length(unique(as.integer(dates - min(dates)) %/% 7))
}

# ── 1. Banister impulse-response ───────────────────────────────────────

#' Daily load, every day from the first to `to`, zero on rest days. Either
#' the day's volume load (lb) across the block's lifts, or its session
#' stress, RPE x minutes (`minutes`: the lifting minutes the plan gives each
#' weekday, `c(Tue = 60, Thu = 75)`; RPE 7 where none was logged), which
#' TrainingPeaks-style models use because it counts effort, not only tonnage.
daily_load <- function(logs, to = max(logs$date), load = c("volume", "stress"), minutes = NULL) {
  load <- match.arg(load)
  lifted <- logs[!is.na(logs$pattern) & !is.na(logs$volume_load_lbs), ]
  if (!nrow(lifted)) return(data.frame(date = as.Date(character()), load = numeric()))
  days <- seq(min(lifted$date), to, by = "day")
  per <- if (load == "volume") {
    tapply(lifted$volume_load_lbs, lifted$date, sum)
  } else {
    rpe <- tapply(ifelse(is.na(lifted$rpe), 7, lifted$rpe), lifted$date, mean)
    wd <- format(as.Date(names(rpe)), "%a")
    rpe * (minutes[wd] %||% 60)
  }
  data.frame(date = days, load = as.numeric(per[as.character(days)] %||% 0)) |>
    mutate(load = ifelse(is.na(load), 0, load))
}

#' The model's prediction on each of `days`, from the daily load.
banister_predict <- function(par, load, days) {
  p0 <- par[1]; k1 <- par[2]; k2 <- par[3]; t1 <- par[4]; t2 <- par[5]
  vapply(days, function(d) {
    past <- load$date < d
    lag <- as.numeric(d - load$date[past])
    w <- load$load[past]
    p0 + k1 * sum(w * exp(-lag / t1)) - k2 * sum(w * exp(-lag / t2))
  }, 0)
}

#' Fits one lift. Returns ok = FALSE with a reason when there is too little.
fit_banister <- function(logs, slug, min_obs = 6, free_taus = 15, load = "volume", minutes = NULL) {
  obs <- logs[logs$exercise_slug == slug & !is.na(logs$e1rm_lbs), ]
  obs <- if (nrow(obs)) {
    obs |> group_by(date) |> summarise(e1rm = max(e1rm_lbs), .groups = "drop")
  } else {
    data.frame(date = as.Date(character()), e1rm = numeric())
  }
  if (nrow(obs) < min_obs) {
    return(list(slug = slug, ok = FALSE, reason = sprintf("%d sessions with an e1RM; needs %d", nrow(obs), min_obs)))
  }

  load <- daily_load(logs, to = max(obs$date), load = load, minutes = minutes)
  # Scale the load so k1, k2 sit near 1e-3 whatever the units.
  scale <- max(1, stats::median(load$load[load$load > 0]))
  load$load <- load$load / scale

  # Five parameters from a handful of sessions are not identifiable: the
  # time constants run to their bounds. Under `free_taus` sessions they are
  # held at the values the literature settles on (fitness 42 days, fatigue
  # 7; Banister et al., 1975, and after) and only the three gains are fitted.
  free <- nrow(obs) >= free_taus
  taus <- c(42, 7)
  sse <- function(par) {
    full <- if (free) par else c(par, taus)
    sum((obs$e1rm - banister_predict(full, load, obs$date))^2)
  }
  start <- c(stats::median(obs$e1rm), 0.5, 0.5, if (free) taus)
  fit <- stats::optim(
    start, sse,
    method = "L-BFGS-B",
    lower = c(0, 0, 0, if (free) c(10, 1)),
    upper = c(Inf, 50, 50, if (free) c(60, 20))
  )
  par <- if (free) fit$par else c(fit$par, taus)

  fitted <- banister_predict(par, load, obs$date)
  list(
    slug = slug,
    ok = fit$convergence == 0,
    taus_fitted = free,
    reason = if (fit$convergence == 0) NA else fit$message,
    par = stats::setNames(par, c("p0", "k1", "k2", "tau_fitness", "tau_fatigue")),
    scale = scale,
    data = data.frame(date = obs$date, e1rm = obs$e1rm, fitted = fitted, residual = obs$e1rm - fitted)
  )
}

# ── 2. ACWR by movement pattern, rides beside the lifts ────────────────

#' The ratio on each day for one daily-load series (7-day sum over the
#' 28-day sum / 4); NA for the first 27 days and when the chronic load is 0.
acwr_series <- function(load) {
  if (nrow(load) < 28) return(data.frame(date = load$date, acwr = rep(NA_real_, nrow(load))))
  # stats::filter answers a time series; plain numbers bind cleanly.
  acute <- as.numeric(stats::filter(load$load, rep(1, 7), sides = 1))
  chronic <- as.numeric(stats::filter(load$load, rep(1, 28), sides = 1)) / 4
  data.frame(date = load$date, acwr = ifelse(!is.na(chronic) & chronic > 0, acute / chronic, NA_real_))
}

#' ACWR per pattern and for the rides (minutes as the endurance load).
acwr_by_pattern <- function(logs, rides) {
  out <- list()
  lifted <- logs[!is.na(logs$pattern) & !is.na(logs$volume_load_lbs), ]
  for (p in unique(lifted$pattern)) {
    rows <- lifted[lifted$pattern == p, ]
    days <- seq(min(rows$date), max(lifted$date, rows$date), by = "day")
    per <- tapply(rows$volume_load_lbs, rows$date, sum)
    load <- data.frame(date = days, load = as.numeric(per[as.character(days)]))
    load$load[is.na(load$load)] <- 0
    out[[p]] <- cbind(pattern = p, acwr_series(load))
  }
  if (nrow(rides)) {
    days <- seq(min(rides$date), max(rides$date), by = "day")
    per <- tapply(rides$minutes, rides$date, sum)
    load <- data.frame(date = days, load = as.numeric(per[as.character(days)]))
    load$load[is.na(load$load)] <- 0
    out[["endurance"]] <- cbind(pattern = "endurance", acwr_series(load))
  }
  if (!length(out)) return(data.frame(pattern = character(), date = as.Date(character()), acwr = numeric()))
  do.call(rbind, out)
}

#' The ratios over the seven days before a flare-up, by pattern; NULL
#' without a date.
achilles_retrospective <- function(acwr, flare_date) {
  if (is.null(flare_date) || is.na(flare_date)) return(NULL)
  flare <- as.Date(flare_date)
  acwr |>
    filter(date >= flare - 7, date < flare) |>
    group_by(pattern) |>
    summarise(peak = max(acwr, na.rm = TRUE), over_1_5 = sum(acwr > 1.5, na.rm = TRUE), .groups = "drop") |>
    mutate(peak = ifelse(is.finite(peak), peak, NA_real_))
}

# ── 3. Residual anomalies ──────────────────────────────────────────────

#' The generalised ESD test (Rosner, 1983) for up to `max_out` outliers at
#' level `alpha`: the indices of the outliers, possibly none. Written out
#' rather than taken from a package so the test is on the page.
gesd <- function(x, max_out = max(1, floor(length(x) / 10)), alpha = 0.05) {
  n <- length(x)
  idx <- seq_len(n)
  removed <- integer()
  r <- lambda <- numeric(max_out)
  for (i in seq_len(max_out)) {
    if (length(x) < 3) break
    dev <- abs(x - mean(x)) / stats::sd(x)
    j <- which.max(dev)
    r[i] <- dev[j]
    removed[i] <- idx[j]
    p <- 1 - alpha / (2 * (n - i + 1))
    t <- stats::qt(p, n - i - 1)
    lambda[i] <- (n - i) * t / sqrt((n - i - 1 + t^2) * (n - i + 1))
    x <- x[-j]
    idx <- idx[-j]
  }
  k <- max(c(0, which(r[seq_along(removed)] > lambda[seq_along(removed)])))
  if (k == 0) integer() else removed[seq_len(k)]
}

#' Outlying residuals: GESD from 15 values, else outside 1.5 IQR.
anomalies <- function(residuals) {
  x <- residuals[!is.na(residuals)]
  if (length(x) < 4) return(integer())
  if (length(x) >= 15) return(gesd(x))
  q <- stats::quantile(x, c(0.25, 0.75))
  fence <- 1.5 * diff(q)
  which(x < q[1] - fence | x > q[2] + fence)
}

# ── Stage gates ────────────────────────────────────────────────────────

#' Runs `f` only once `n_weeks` reaches `needed`; otherwise a message.
gated <- function(n_weeks, needed, label, f) {
  if (n_weeks < needed) {
    return(sprintf("%s waits for %d weeks of data (%.1f so far).", label, needed, n_weeks))
  }
  f()
}

stage1 <- function(logs, n_weeks) {
  gated(n_weeks, 8, "Stage 1 (brms dose-response, glmnet transfer)", function() {
    "Stage 1 is open: install brms and glmnet and fill in stage1() (see analysis/README.md)."
  })
}

stage2 <- function(logs, n_weeks) {
  gated(n_weeks, 26, "Stage 2 (bsts forecast, readiness model)", function() {
    "Stage 2 is open: install bsts and fill in stage2()."
  })
}

# ── The site's look ────────────────────────────────────────────────────

#' ggplot2 in the site's print voice: paper ground, ink type, hairline
#' grid, the poppy/laurel/valley-dusk pigments for series (assets/css/app.css).
site_colours <- c(ink = "#17140f", ink2 = "#4b453a", ink3 = "#7d7566", paper = "#f3eee4",
                  poppy = "#c2451d", laurel = "#3f6b4a", dusk = "#2c4a6e", rust = "#a73b19")

theme_site <- function(base_size = 11) {
  ggplot2::theme_minimal(base_size = base_size, base_family = "serif") +
    ggplot2::theme(
      plot.background = ggplot2::element_rect(fill = site_colours[["paper"]], colour = NA),
      panel.grid.major = ggplot2::element_line(colour = "#17140f22", linewidth = 0.3),
      panel.grid.minor = ggplot2::element_blank(),
      text = ggplot2::element_text(colour = site_colours[["ink"]]),
      axis.text = ggplot2::element_text(colour = site_colours[["ink3"]], family = "mono"),
      strip.text = ggplot2::element_text(colour = site_colours[["ink2"]], face = "bold", hjust = 0),
      legend.position = "bottom"
    )
}

scale_colour_site <- function(...) {
  ggplot2::scale_colour_manual(
    values = unname(site_colours[c("poppy", "dusk", "laurel", "rust", "ink2", "ink3")]), ...
  )
}

# ── Everything ─────────────────────────────────────────────────────────

#' Runs Stage 0 and the gates. `flare_date` is the Achilles flare-up's day.
run_models <- function(csv, db_path = NULL, block_path, flare_date = NULL) {
  block <- read_block(block_path)
  lifts <- block_lifts(block)
  logs <- read_logs(csv, lifts)
  db <- read_db(db_path)
  n_weeks <- weeks_of_data(logs$date)

  banister <- lapply(lifts$exercise_slug, function(s) fit_banister(logs, s))
  names(banister) <- lifts$exercise_slug
  acwr <- acwr_by_pattern(logs, db$rides)

  for (s in names(banister)) {
    b <- banister[[s]]
    if (isTRUE(b$ok)) b$data$anomaly <- seq_len(nrow(b$data)) %in% anomalies(b$data$residual)
    banister[[s]] <- b
  }

  list(
    block = block,
    lifts = lifts,
    logs = logs,
    checkins = db$checkins,
    rides = db$rides,
    n_weeks = n_weeks,
    banister = banister,
    acwr = acwr,
    retrospective = achilles_retrospective(acwr, flare_date),
    stage1 = stage1(logs, n_weeks),
    stage2 = stage2(logs, n_weeks)
  )
}

if (sys.nframe() == 0) {
  args <- commandArgs(trailingOnly = TRUE)
  csv <- args[1] %||% "tmp/fitness/fitness_logs.csv"
  db <- args[2] %||% NA
  block <- args[3] %||% "content/fitness/blocks/get-sharp.md"
  m <- run_models(csv, if (is.na(db)) NULL else db, block, Sys.getenv("ACHILLES_FLARE_DATE", NA))
  cat(sprintf("%d entries over %.1f weeks\n", nrow(m$logs), m$n_weeks))
  for (b in m$banister) {
    if (isTRUE(b$ok)) {
      cat(sprintf("%-26s fitted (%s): tau fitness %.0f d, tau fatigue %.0f d, %d anomalies %s\n",
                  b$slug, if (b$taus_fitted) "taus fitted" else "taus held",
                  b$par["tau_fitness"], b$par["tau_fatigue"], sum(b$data$anomaly),
                  paste(format(b$data$date[b$data$anomaly]), collapse = " ")))
    } else {
      cat(sprintf("%-26s %s\n", b$slug, b$reason))
    }
  }
  cat(m$stage1, "\n", m$stage2, "\n", sep = "")
}
