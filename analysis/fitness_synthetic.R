# fitness_synthetic.R — an invented eight-week block, in the shape
# `mix fitness.export` writes, to prove the models on before real data
# exists. Seeded, so every run is the same. Never read by the site.
#
#   Rscript analysis/fitness_synthetic.R tmp/fitness-synthetic

args <- commandArgs(trailingOnly = TRUE)
dir <- if (length(args)) args[1] else "tmp/fitness-synthetic"
dir.create(dir, recursive = TRUE, showWarnings = FALSE)
set.seed(20261026)

start <- as.Date("2026-10-26")
lifts <- data.frame(
  slug = c("hex-flat-side-deadlift", "incline-dumbbell-press", "shoulder-press", "dumbbell-rows"),
  name = c("Hexbar Deadlift", "Incline Dumbbell Press", "Shoulder Press", "Dumbbell Rows"),
  day = c(4, 2, 5, 2),
  base = c(185, 50, 40, 55),
  step = c(5, 5, 5, 5),
  stringsAsFactors = FALSE
)

rows <- list()
for (week in 1:8) {
  for (i in seq_len(nrow(lifts))) {
    l <- lifts[i, ]
    date <- start + (week - 1) * 7 + l$day - 1
    deload <- week == 4
    weight <- l$base + l$step * max(0, week - 1 - (week > 4)) * (if (deload) 0.9 else 1)
    reps <- if (deload) 5 else sample(6:8, 1)
    sets <- if (deload) 2 else 3
    # One bad day, to be found: week 6's RDL.
    if (week == 6 && l$slug == "hex-flat-side-deadlift") reps <- 3
    rpe <- if (deload) 6 else round(runif(1, 7, 9) * 2) / 2
    e1rm <- round(weight * (1 + reps / 30), 1)
    rows[[length(rows) + 1]] <- data.frame(
      date = format(date), week_num = as.integer(format(date, "%V")), year = 2026,
      quarter = 4, month = as.integer(format(date, "%m")), exercise_name = l$name,
      muscle_group = "legs", weight_lbs = weight, distance_miles = NA, time_str = NA,
      height_result = NA, notes = NA, exercise_slug = l$slug, sets = sets, reps = reps,
      rpe = rpe, e1rm_lbs = e1rm, volume_load_lbs = sets * reps * weight
    )
  }
}

logs <- do.call(rbind, rows)
utils::write.csv(logs, file.path(dir, "fitness_logs.csv"), row.names = FALSE, na = "NA")
cat(nrow(logs), "invented entries written to", dir, "\n")
