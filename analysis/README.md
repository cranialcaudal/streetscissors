# analysis/

**Statistics written in R**, for two parts of the site. Until 2026-10-20 this folder was called
`scripts/` and kept out of git. It is in the repository now, so anyone can read, run and check
the numbers the site shows.

R is a programming language made for statistics. You do not need it to run the website: the site
only *reads* what these scripts produce, and every page that uses them says so plainly when the
output is missing.

## What is here

| File | What question it answers | Where its answer appears | Run it with |
|---|---|---|---|
| [`emissions.R`](emissions.R) | How much carbon does each way of getting to work emit, per month and over a working life? | The charts in the blog post about commuting, and the post's "show the code" box | `Rscript analysis/emissions.R` |
| [`fitness_models.R`](fitness_models.R) | During a training block: is the lifting getting stronger, is the load climbing too fast, and was any day unusual? | The weekly training report (admin only) | Through the report, below |
| [`fitness_report.qmd`](fitness_report.qmd) | The weekly report itself: a Quarto document that runs `fitness_models.R` and lays out its charts and tables | `/admin/fitness/report` | `quarto render analysis/fitness_report.qmd …` (below) |
| [`fitness_synthetic.R`](fitness_synthetic.R) | None. It invents eight weeks of plausible training data, so the models can be tried before real data exists | Never shown by the site | `Rscript analysis/fitness_synthetic.R tmp/fitness-synthetic` |

Run every command from the top of the repository (the folder with `mix.exs` in it). The scripts
find their inputs relative to there.

## `emissions.R`, step by step

The script is written in three acts, and its opening comment explains each one, along with the
two different questions it is careful never to mix up ("what does *this* trip cost by each
mode?" versus "what do people who use each mode actually emit?").

1. **Data.** One row per way of travelling, with grams of carbon per mile from published sources,
   and the tables it multiplies against (electricity grids, diets for the energy a cyclist eats).
2. **Analysis.** Turns grams per mile into pounds per month and per year, and adds those up over
   a working life.
3. **Output.** It writes two files:
   - `priv/static/figures/emissions-frame-a.png`, a chart to look at while working on it;
   - `priv/static/figures/emissions.json`, the numbers the website draws its own charts from
     (`Web.Blog.Embeds` reads it; `assets/js/emissions_controls.js` redraws the charts when a
     reader moves the sliders).

R never runs on the live server. You run the script on your own machine when the assumptions
change, and the site reads the JSON. Both outputs are ignored by git (`priv/static/figures/` is),
so a fresh clone draws no chart until you have run the script once.

The website also **shows this file's text** inside the post. It reads `analysis/emissions.R`
when the site is compiled, so the code in the post and the code here can never disagree.

**Packages:** `jsonlite`, `dplyr`, `tidyr`, `ggplot2`.

## The training report, step by step

During a training block (a fixed number of weeks with a plan, written in
`content/fitness/blocks/<name>.md`), the site makes a report every Sunday evening. It can also be
made on demand from the block report page. Making it takes three steps; the site does all three
itself (`Web.Fitness.Report`), and you can do them by hand:

```bash
# 1. Write the training log and the daily check-ins out as CSV files R can read
#    (into tmp/fitness/). With no --db it reads the development database; to read
#    the live one, point at it. It is opened read-only, so this is safe on a server.
mix fitness.export tmp/fitness --db $HOME/streetscissors-data/streetscissors.db

# 2. Render the report. Quarto runs the R code inside fitness_report.qmd, which loads
#    fitness_models.R, and writes one self-contained HTML page.
quarto render analysis/fitness_report.qmd --output-dir ../tmp/fitness-report \
  -P db:$HOME/streetscissors-data/streetscissors.db

# 3. Open tmp/fitness-report/fitness_report.html in a browser.
```

What the models do, in plain words (the opening comment of `fitness_models.R` has the full
version, with references):

1. **Fitness and fatigue (the Banister model, 1975).** Every session builds fitness and also
   tiredness. Both fade, the tiredness faster. The model fits how quickly each fades for each lift,
   and then the gap between what it predicted and what actually happened says how ready the body
   was that day.
2. **Load ratio (acute:chronic, Gabbett 2016).** Compares the last 7 days' work with the average
   week over the last 28 days, separately for each kind of movement (hinge, squat, push, pull,
   jumping and running). A sudden rise is a known injury risk; the site's guardrails hold a lift
   back when the ratio passes 1.5. Bike rides count as endurance load.
3. **Odd days.** Looks for sessions much better or worse than the model expected, using a
   standard outlier test (generalised ESD, Rosner 1983), or a simpler one when there are fewer
   than 15 sessions.

**Stages.** Those three are "Stage 0" and work with any amount of data, saying when there is too
little. Heavier models (Stage 1 after 8 weeks of data, Stage 2 after 26) are switched off in the
code and print a message until there is enough data to make them meaningful; their packages
(`brms`, `glmnet`, `bsts`) are not needed until then.

**Packages:** `DBI`, `RSQLite`, `dplyr`, `jsonlite`, `ggplot2`, and the
[Quarto](https://quarto.org) command-line tool.

**Optional:** `-P flare_date:YYYY-MM-DD` adds a look back at the training load in the weeks before
a known injury flare-up.

## Trying the report without real data

```bash
Rscript analysis/fitness_synthetic.R tmp/fitness-synthetic
quarto render analysis/fitness_report.qmd --output-dir ../tmp/fitness-report \
  -P csv:tmp/fitness-synthetic/fitness_logs.csv
```

The invented block has one bad day planted in it on purpose (2026-12-03); the outlier test should
find exactly that day.

## Installing R and Quarto

On Fedora:

```bash
sudo dnf install R
Rscript -e 'install.packages(c("jsonlite","dplyr","tidyr","ggplot2","DBI","RSQLite"), repos="https://cloud.r-project.org")'
```

Quarto is not in Fedora's packages. Download the Linux `.tar.gz` from
[quarto.org](https://quarto.org/docs/download/), unpack it into `~/.local/opt/quarto`, and link
the program onto your `PATH`:

```bash
ln -s ~/.local/opt/quarto/bin/quarto ~/.local/bin/quarto
quarto --version
```

[`docs/setup.md`](../docs/setup.md) has the same steps alongside everything else a new machine
needs.

## The data stays private

These scripts are public; the data they read is not. The training log, check-ins and rides are
in the live database, and the block plan is in `content/`, outside git. The report is shown only
to the site's admin.
