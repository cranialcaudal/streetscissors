# The colour pipeline: contracts

This is the one document every workstream reads. It fixes what each stage takes
and gives, where each file lives, and what counts as correct, so that work on one
stage never needs another stage's code. The plan behind it, and who does what,
is at the foot. The sources are in `research.md`, next to this file.

## The pipeline

```
scan (16-bit, linear)                        Web.Scanner.Bed / Driver
  → density        D = scanner curve(v)      film-develop, LightCraft film.invert
  → relative       D − Dmin                  film base read off the clear film
  → dye            A⁻¹ (D − Dmin)            un-crosstalk (the stock's 3×3)
  → exposure       H = d / γ  (per channel)  the film's characteristic curve undone
  → scene          10^H · k                  scene-linear light, film primaries
  → print          paper LUT or print curve  the look: a real paper, chosen
  → grade          LightCraft's sliders      correction (wb), then taste
  → output         sRGB print, previews
```

Each arrow has **one** implementation that serves the preview and the print
alike: LightCraft's `film.invert` for everything from density to scene, and
LightCraft's existing LUT profiles for the paper. `film-develop` finds frames,
reads the roll, writes the parameters, and still writes `developed/NN.png` for
recipes of version 1.

## Rules every stage keeps

1. **Without its calibration, a stage gives today's output to the byte.** A
   missing `scanner-*.json` means the gamma assumption used today; a missing
   stock means the identity crosstalk and the roll's own gammas. The regression
   check (`tools/film/regress.sh`, W2) compares `frames.json` and every
   print on the fixture rolls before and after.
2. **Tested against the known-answer model** (`tools/film/test-model/synth.py`) to
   the tolerances below. A test that needs a real scan goes in the gitignored
   `test/private/`.
3. **Every number written says where it came from**: `"source": "tablet" |
   "chart" | "datasheet" | "assumed"`, and the date and tool version.
4. **Measurements of the author's own material live in the archive, never in
   git** (`<archive>` is `NEGATIVES_PATH`). Only datasheet profiles, which are
   public, are committed.
5. **GPL code is never copied in.** negadoctor (darktable), RawTherapee and
   spektrafilm are reimplemented from their published equations or run as
   separate programs. ArgyllCMS (AGPL) is called, never vendored.

## Files

### Scanner calibration — `<archive>/.darkroom/calibration/scanner-<id>.json`

Written by `film-develop calibrate-tablet` from a scan of a transmission step
tablet (Stouffer T2115: 21 steps, certified densities typed in from its card).

```json
{
  "id": "v550-2026-11-02",
  "scanner": "epson2:libusb (V550)",
  "settings": {"dpi": 1600, "depth": 16, "mode": "Color", "gamma": "as-scanned"},
  "curve": {"r": [[0, 3.62], [12, 3.10], ..., [65535, 0.0]], "g": [...], "b": [...]},
  "flare": [0.004, 0.004, 0.005],
  "floor": [3.4, 3.5, 3.3],
  "source": "tablet",
  "tablet": {"maker": "Stouffer", "model": "T2115", "densities": [0.05, 0.20, ...]},
  "made": "2026-11-02", "tool": "film-develop 2026.11"
}
```

`curve` maps the scanner's 16-bit value to density, per channel, as monotone
`[value, density]` pairs (interpolate linearly in value; extrapolate flat).
`floor` is the density past which the channel reads noise. The scan's TIFF
description names the calibration it was made under: the studio mark, then
`; calibration <id>`.

### Stock characterisation — `<archive>/.darkroom/calibration/stock-<slug>.json`, else `priv/film/profiles/<slug>.json`

`<slug>` is a stock's key in `priv/film/stocks.json`. A chart the author shot
outranks a datasheet profile; both have the same shape.

```json
{
  "stock": "portra-400",
  "process": "c41",
  "crosstalk": [[1.0, 0.08, 0.02], [0.10, 1.0, 0.12], [0.03, 0.25, 1.0]],
  "gamma": [0.55, 0.60, 0.65],
  "to_working": [[...], [...], [...]],
  "residual": {"mean_de00": 1.4, "max_de00": 3.9},
  "source": "chart",
  "made": "2026-11-09", "tool": "film-develop 2026.11"
}
```

`crosstalk` is `A` (rows: the scanner's R G B; columns: cyan, magenta and
yellow dye), `gamma` the slope of each layer's density against log exposure,
`to_working` the 3×3 from the film's primaries to linear Rec.2020 (LightCraft's
working space), fitted on the chart's patches. A datasheet profile has no
`to_working` unless its sheet gives spectral sensitivities. `residual` is the
fit's error on the chart.

### The roll — `frames.json` `"film_op"`

`film-develop` adds the roll model, as `film.invert`'s parameters, beside its
existing `film`/`films` blocks (which stay as they are):

```json
"film_op": {
  "version": 1,
  "scanner": "v550-2026-11-02",
  "stock": "portra-400",
  "dmin": [0.25, 0.60, 0.85],
  "gamma": [0.55, 0.60, 0.65],
  "crosstalk": [[...]],
  "white": [2.1, 2.3, 2.4],
  "source": {"dmin": "film", "gamma": "roll", "crosstalk": "chart", "scanner": "tablet"}
}
```

`white` is the density the roll's brightest highlight reaches, per channel
(today's `film.white`), so a print's exposure starts where `film-develop`'s
does.

### The master — `raw-frames/frame-NN.tiff`

A single as the scanner gave it: 16 bits a channel, nothing adjusted, the
studio mark and calibration id in its description. Already kept today for
keepers; W1d makes every single 16-bit.

### Paper LUTs — `<archive>/.darkroom/luts/<stock>__<paper>.cube`

33³, made by `tools/paper-lut` (spektrafilm's print stage, run as its own
program). Input: `film.invert`'s output encoded as below. Output: display sRGB.
LightCraft loads them through its **existing** `.cube` profiles
(`crates/pipeline/src/lut.rs`, ids `lut:<name>`), which apply to the
display-encoded colour. So `film.invert` hands the paper an agreed encoding:
**log2 of scene-linear, mapped −8..+4 stops about 0.18 to 0..1, per channel**
(`DOMAIN_MIN 0 0 0`, `DOMAIN_MAX 1 1 1`). The LUT's `TITLE` names the stock,
the paper and the spektrafilm version.

### Recipe v2 — `edits/NN.json`

```json
{
  "v": 2,
  "engine": "lightcraft 43a47e5+film.1",
  "source": "raw",
  "film": {"dmin": [...], "gamma": [...], "crosstalk": [[...]], "exposure": 0.0, "black": 0.0, "grade": 1.0},
  "paper": "portra-400__endura",
  "calibration": {"scanner": "v550-2026-11-02", "stock": "chart:portra-400"},
  "controls": {...}, "crop": {...}, "spots": [...]
}
```

`film` holds only what the author moved off the roll's `film_op`; the rest is
read from `frames.json` at render time. **A recipe with no `"v"` is version 1**
and renders from `developed/NN.png` exactly as before. Nothing upgrades a
recipe but the author's own button.

### Grey points — `<archive>/.darkroom/neutrals.jsonl`

One line per eyedropper click: `{"roll", "frame", "x", "y", "radius", "rgb":
[linear, from the uncorrected render], "recipe_v", "at"}`. Ground truth for
`Web.Darkroom.Stats`' neutral gate and `Prior`.

### The held-out score — `<archive>/.darkroom/eval/<timestamp>.json`

`mix darkroom.eval`: leave one out over `Taste.examples/1` (saved edits only),
per example the ΔE₀₀ of the predicted against the saved grade's colour (via
`Film.cast_of/3`) and each other slider's error in its own steps; summed overall
and per film group. The task prints the comparison with the previous file.

## LightCraft operations (the fork, `cranialcaudal/lightcraft`)

| Command / control id | What | Notes |
|---|---|---|
| `film.invert` section `film`: `film.dmin.{r,g,b}`, `film.gamma.{r,g,b}`, `film.exposure`, `film.black`, `film.grade` | density → scene, then a print curve (negadoctor's published model) when no paper LUT is set | crosstalk and scanner curve are not sliders: set by `film.configure {scanner, crosstalk, to_working}` |
| `film.configure` | loads `scanner-*.json` and a 3×3 | JSON params, as `develop.set` |
| `lut:<name>` profiles | **exist already** | paper LUTs register through them |
| `scopes.compute` | histogram, waveform, parade, vectorscope of the current render | compact arrays, for the editor's `.Scopes` hook |

Each runs first in the pipeline (before white balance), on the CPU and the GPU
paths alike, with unit tests in the fork against fixtures from `synth.py`.
Offered upstream as one PR each.

## Tolerances

| Check | Tolerance |
|---|---|
| Density recovered from a synth scan, patch mean, D < 2.5 | ≤ 0.02 |
| The same, noise-free | ≤ 0.01 |
| Scene recovered, noise-free, through `film.invert` | ΔE₀₀ ≤ 1.0 |
| End to end (synth → film-develop → LightCraft → print vs the scene printed through the same paper) | ΔE₀₀ ≤ 2.0 mean, ≤ 4.0 max |
| `film.invert` against `film-develop`'s own density maths on one TIFF | ΔE₀₀ ≤ 0.5 |
| No calibration present | byte-identical to before |
| `mix darkroom.eval` after a Taste or Prior change | mean not worse |

## The test model

`python3 tools/film/test-model/synth.py roll OUT --process c41|bw|e6 --frames N
--seed S` writes `strip-01.tiff` (16-bit, uncompressed, the studio mark in its
description) and `truth.json`: the film's every number, the scanner's, and each
patch's scene light, density and rectangle. `synth.read_tiff` reads it back
with numpy alone. Committed rolls (seed 1, three frames each) are in
`test/support/fixtures/colour/{c41,bw,e6}/`. Its own tests:
`python3 -m pytest tools/film/test-model/test_synth.py`.

## Workstreams

The order of work is W0 → (W1, W2, W3, W4 in parallel) → W5 after W4, W6
after W2 and W4 → W7 after W1b.

| | What | Where |
|---|---|---|
| W0 | This document, `research.md`, the test model, the cloud start hook, `tools/lightcraft/install.sh`, the fork; `film-develop` brought into `tools/film/` (done 2026-10-20, with its history) | here |
| W1 | Taste's hue fix; `mix darkroom.eval`; the film-name page; 16-bit singles with the calibration id | `lib/web/darkroom/`, `lib/web/scanner/` |
| W2 | `film-develop`: `calibrate-tablet`, density throughout, crosstalk, `film_op`; `regress.sh` | `tools/film/` |
| W3 | `film-develop characterize` (ColorChecker, colour-checker-detection's BSD path only), datasheet profile import from spektrafilm (CC BY-SA, credited in `priv/film/LICENSES.md`), `tools/it8-profile.sh` (ArgyllCMS) for slides | `tools/`, `priv/film/profiles/` |
| W4 | `film.invert`, `film.configure`, `scopes.compute` in the fork | `cranialcaudal/lightcraft` |
| W5 | `tools/paper-lut/` (spektrafilm, pinned, run as a program); `Web.Cuts.Render` takes a `lut3d` | `tools/`, `lib/web/cuts/` |
| W6 | The editor on recipe v2: source from the master, Film and Paper sections, scopes, density readout, eyedropper → `neutrals.jsonl`; the stub learns the new commands | `lib/web/darkroom.ex`, `lib/web_web/live/admin_live/darkroom_editor.ex`, `assets/js/` |
| W7 | Taste v2: pairwise (Bradley–Terry) learning from `choices.jsonl` with its `other`, choosing the most uncertain step, a grade per roll | `lib/web/darkroom/taste.ex`, `lib/web_web/live/admin_live/taste.ex` |

**Done means**: the tolerances above, `mix precommit` clean, and CLAUDE.md's
darkroom section updated in its own voice.
