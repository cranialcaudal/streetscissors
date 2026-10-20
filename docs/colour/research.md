# The colour pipeline: what the trade does, and what we took

Gathered once (2026-10-20) so that no workstream researches it again. Each entry
says what the tool or standard does, whether it is open, and what this pipeline
takes from it. `contracts.md` is the specification; this is its reasoning.

## The premise

A colour negative was never a colour measurement: it was made to be printed, and
the paper's response *was* the colour. So no tool recovers "true" colour from a
negative. The professional pipelines all do the same two things well: they
**measure** the film exactly (density, with the instrument calibrated), and then
apply a **named, chosen interpretation** (a print stock, a lab's look). That is
the standard here: measured to the tolerances in `contracts.md`, interpreted
through a paper the author picks.

## Standards and industry pipelines

- **Cinema film scanning: ADX and ACES.** SMPTE ST 2065-3 defines ADX, an
  encoding of negative film as Academy Printing Density, measured with
  narrow-band light. The "unbuild" works from densities back to the exposure
  that made them, and a print-film emulation gives the look. Separating
  *measurement*, *undoing the film* and *the look* is the design this pipeline
  copies. [ST 2065-3](https://pub.smpte.org/doc/st2065-3/20200909-pub/st2065-3-2020.pdf),
  [ACES Central on ADX16](https://community.acescentral.com/t/scanning-film-in-adx16/3135)
- **Densitometry: Status M against a white-light scanner.** Negatives are
  measured with Status M filters; a scanner whose channels peak elsewhere sees
  different contrast, and with channels that are not narrow, density and dye
  amount are related non-linearly, so a 3×3 matrix removes crosstalk only
  approximately. The Epson V550 lights the film with white light. Hence: the
  scanner is measured (step tablet), and the crosstalk matrix is fitted per
  stock on a chart, with its residual reported rather than assumed away.
  [US 5149960](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/5149960),
  [US 5500316](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/5500316)
- **Lab scanners (Fuji Frontier, Noritsu).** Closed; per-stock channel
  settings and an operator's choices. The "lab look" (Frontier punchy and cool,
  Noritsu flat and warm) is a rendering decision. Taken: the look is a named
  choice, not a by-product. [Carmencita's comparison](https://carmencitafilmlab.com/?p=35292)
- **Negative Lab Pro, SilverFast NegaFix.** Closed; per-stock profiles, roll
  analysis, edits kept off the scan. Taken: the scan is the master and the roll
  is analysed as one.

## Open implementations

- **darktable `negadoctor`** (GPL). Cineon densitometry: transmittance over the
  film base → density → a virtual print with print exposure, paper black and
  paper grade; `RGB_out = (RGB_in × exposure + black)^grade`; Dmin the film
  base, Dmax as gain = 1/Dmax; the default offset from Kodak's Cineon practice.
  Taken: `film.invert`'s print curve and its three controls, **reimplemented
  from the equations, not the code.**
  [Manual](https://docs.darktable.org/usermanual/5.6/en/module-reference/processing-modules/negadoctor/)
- **RawTherapee Film Negative** (GPL). A power per channel of the reciprocal of
  exposure, with exponents from two picked grey points (a reference exponent on
  green and red/blue ratios). This is the model `film-develop` already uses (a
  per-channel power on transmittance over the base). Known criticism: it treats
  a value of 1 as a transmittance of 1, which holds only if the base is exactly
  1 after white balance. Taken: the two-grey-point fit as a check, and the
  warning. [RawPedia](https://rawpedia.pixls.us/film_negative/)
- **spektrafilm, formerly agx-emulsion** (code GPLv3; profile JSON CC BY-SA
  4.0; its LUTs under their own licence, not for resale). A spectral simulation
  of negative and print: layer sensitivities, couplers (masking and DIR),
  halation, grain, then printing through a dichroic-filtered enlarger onto a
  paper (Portra Endura, Ektacolor Edge, 2383 and others), built from Kodak's
  datasheet curves. It runs **forward only**, from scene to print; it does not
  invert a scan. Fujifilm data is less self-consistent than Kodak's. Taken: its
  **print stage** run as a separate program to make paper LUTs (W5), and its
  **profile data** (credited) as datasheet characterisations (W3).
  [Repository](https://github.com/andreavolpato/agx-emulsion),
  [pixls.us thread](https://discuss.pixls.us/t/spectral-film-simulations-from-scratch/48209)
- **ArgyllCMS** (AGPL). Scanner profiles from IT8 targets: `scanin` reads the
  target (manual fiducials with `-F` when recognition fails), `colprof` builds
  the ICC. An IT8.7/1 target is a slide, so this is the colorimetric route for
  **E-6** only. Taken: `tools/it8-profile.sh`, called, not vendored.
  [Guide](https://www.printerknowledge.com/posts/145014)
- **colour-science** (BSD). `colour-checker-detection` finds a ColorChecker
  Classic 24 in a photograph by segmentation (BSD) or YOLO (AGPL: not used).
  Taken: chart detection for `characterize` (W3).
  [Docs](https://colour-checker-detection.readthedocs.io/)
- **LightCraft** (MIT or Apache-2.0), our engine. Scene-referred linear
  Rec.2020 float pipeline, OkLCh colour tools, per-channel point curves,
  three-way wheels, and **`.cube` 3D LUT profiles already**
  (`crates/pipeline/src/lut.rs`, applied to display-encoded colour). No
  negative inversion, colour management or scopes. Taken: the fork adds
  `film.invert`, `film.configure`, `scopes.compute`.
  [Repository](https://github.com/storytold/lightcraft)

## Learning one person's taste

No professional tool learns an individual's grading from their choices. The
precedent is research: **MIT-Adobe FiveK** (Bychkovsky, Paris, Chan, Durand,
CVPR 2011, "Learning Photographic Global Tonal Adjustment with a Database of
Input/Output Image Pairs") learned five retouchers' adjustments and scored them
by L\*a\*b\* error on held-out photographs. Taken: `mix darkroom.eval`, and the
rule that a model change must not make it worse. Pairwise choices are learned
as comparisons (Bradley–Terry), not as targets.

## Instruments to buy

| | Why | Unlocks |
|---|---|---|
| Stouffer T2115 transmission step tablet (21 steps, certified) | the scanner's true density response, flare and floor | `scanner-*.json` (W2) |
| X-Rite ColorChecker Classic 24 | a stock's crosstalk, gammas and primaries | `stock-*.json` (W3) |
| IT8.7/1 transparency target (e.g. Wolf Faust) | the scanner's colorimetric profile for slide film | ArgyllCMS ICC (W3) |

Until they arrive, every stage runs on the `assumed` and `datasheet` sources and
reproduces today's output.
