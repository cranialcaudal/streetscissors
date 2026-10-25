# Film Negatives Pipeline: Architecture, Mathematics & Integration

This document is the definitive technical specification of the analog-to-digital film pipeline powering **streetscissors** (`https://streetscissors.com/negatives`) and its accompanying toolchain (`tools/film/` in this repository).

It describes the entire lifecycle of an exposure: from physical emulsion on flatbed glass, through headless Script-Fu compositing and C-41 color balancing mathematics, to pure-Elixir coordinate translation and procedural SVG wax china-marker simulation in Phoenix LiveView.

---

## 1. System Overview & The Intertwined Architecture

Unlike conventional media applications that upload images to object storage (like AWS S3) and record URLs in a relational database, `streetscissors` operates on a **direct filesystem contract**. 

The filesystem *is* the database.

```
                    PHYSICAL WORLD
         [Exposed & Developed Analog Film]
                        │
                        ▼ (Film Cutter)
         [Strips: 120 (3-4 exp) / 35mm (6 exp)]
                        │
                        ▼ (Flatbed Scanner: Epson V550/V600)
    =======================================================
                   THE NEGATIVES TOOLCHAIN
               (~/.local/bin/negatives & friends)
                        │
        ┌───────────────┴───────────────┐
        ▼                               ▼
[Raw Strip Scans]             [Intake & Catalog]
(001.tiff, 002.tiff...)       (catalog.csv, rollNNN dir)
        │                               │
        ▼                               │
[film-develop (Python)]                 │
• Glass & border masking                │
• C-41 / B&W density balance            │
• Frame detection & frames.json ────────┤
        │                               │
        ▼                               │
[digital-contact-sheet-maker (GIMP)]    │
• film-contact-sheet.scm (Script-Fu)    │
• 300 DPI 8x10 Contact Sheet PNG ───────┤
        │                               │
    =======================================================
                 THE FILESYSTEM REPOSITORY
                 (~/Pictures/Negatives/)
                        │
    ┌───────────────────┴───────────────────┐
    ▼                                       ▼
Contact Sheets/<roll>.png            <Format>/<roll>/
Contact Sheets/previews/<roll>.webp    ├── 001.tiff..N.tiff
catalog.csv                            ├── frames.json
                                       └── [keepers: 3.tiff...]
    =======================================================
                THE WEB SERVER (streetscissors)
                (Phoenix 1.8 / LiveView 1.1)
                        │
        ┌───────────────┴───────────────┐
        ▼                               ▼
[Web.Negatives]               [Web.Negatives.Sheet]
• Catalog parsing             • Two-stage safety gates
• WebP downscaling            • Replays Scheme layout
• Frame discovery                       │
        │                               ▼
        │                     [Web.Negatives.SheetLayout]
        │                     • Mathematical coordinate translation
        │                     • Strip rect -> Sheet CSS %
        │                               │
        │                               ▼
        │                     [Web.Negatives.GreasePencil]
        │                     • Deterministic phash2 seed
        │                     • Tri-harmonic radial perturbation
        │                     • Catmull-Rom cubic spline SVG
        │                               │
        └───────────────┬───────────────┘
                        ▼
            [WebWeb.NegativesLive]
            • Interactive Contact Sheet Viewer
            • Clickable Wax Circles
            • Per-Frame Inspection Routing
```

### The Architectural Contract
1. **Zero Database Overhead for Media:** Film rolls, contact sheets, and individual frame rescans are never stored as database rows. The directory structure is parsed at request time with sub-millisecond efficiency.
2. **Deterministic Geometry Replay:** The website never attempts to perform optical character recognition or image segmentation on the final contact sheet PNG. Instead, `Web.Negatives.SheetLayout` transcribes the exact layout arithmetic executed by GIMP's Script-Fu engine, calculating frame positions directly from `frames.json`.
3. **Double Verification Gates:** To prevent misaligned click targets (such as clicking a photograph and opening another), `Web.Negatives.Sheet` verifies that the on-disk files match `frames.json` and that the composed image dimensions match one of the standard paper sizes at 300 DPI before drawing a single interactive element.
4. **Immediate Zero-Deploy Publishing:** When a photographer finishes scanning a roll at the physical workstation, the new contact sheet is live on `https://streetscissors.com/negatives` the instant GIMP finishes saving the PNG to disk. No server restarts, build scripts, or asset deploys are required.

---

## 2. Optical & Physical Scanning Geometry

### The 300 DPI Invariant
Every scan of a film strip intended for contact printing is captured at **exactly 300 DPI**.

In traditional darkroom photography, a *contact print* is produced by placing physical negative strips directly emulsion-down against a sheet of 8×10 inch silver gelatin photographic paper, held flat by a sheet of heavy glass, and exposing it under the enlarger lamp for several seconds. The resulting print exhibits exposures at their exact, unaltered physical size:
* **120 Medium Format (6×6 cm):** Real frame size is $56 \times 56\text{ mm}$. At 300 DPI ($11.811\text{ pixels/mm}$), each frame occupies approximately $661 \times 661\text{ pixels}$.
* **120 Medium Format (6×7 cm):** Real frame size is $56 \times 70\text{ mm}$. At 300 DPI, each frame occupies approximately $661 \times 827\text{ pixels}$.
* **35mm Miniature Format:** Real frame size is $24 \times 36\text{ mm}$. At 300 DPI, each frame occupies approximately $283 \times 425\text{ pixels}$.
* **Standard 8×10 inch Photographic Paper:** At 300 DPI, an 8×10 inch sheet measures exactly:
  $$\text{Width} = 8\text{ in} \times 300\text{ DPI} = 2400\text{ pixels}$$
  $$\text{Height} = 10\text{ in} \times 300\text{ DPI} = 3000\text{ pixels}$$

By locking the flatbed scanner and the compositing canvas to 300 DPI:
1. Every frame rendered on screen represents physical reality in true proportional scale.
2. The contact sheet PNG can be sent directly to an inkjet or photographic printer at 100% scale without resampling, reproducing an authentic darkroom proof sheet.

### Transparency Unit (TPU) Illumination
Reflective scanning (using the standard scanner lid) cannot capture film negatives because light reflects off the silver or dye emulsion unevenly, producing an unreadable glare. Film negatives require **transmitted light**—light passing through the film from behind into the scanner's CCD sensor.

The pipeline utilizes the scanner's Transparency Unit (TPU):
* A secondary backlight lamp built into the scanner lid illuminates through the film base.
* The scanner carriage moves beneath the glass bed, recording light attenuation through the negative emulsion.
* Film strips must be placed within the scanner's calibrated TPU optical window (typically an 8×10 or 9×12 inch central zone on scanners like the Epson Perfection V550, V600, or V850).

---

## 3. Image Processing & Color Mathematics (`film-develop`)

Raw digital scans of film negatives cannot simply be inverted with an arithmetic `255 - value` operation. Three physical and chemical realities must be addressed:

### 1. The Scanner Glass & Border Masking Problem
When a film strip sits in a scanner holder on the glass bed:
* The clear scanner glass around the strip transmits 100% light, saturating the CCD sensor at value $255$ (pure white).
* The plastic ribs and edges of the film holder block 100% light, registering at value $0$ (pure black).

If a generic "auto-levels" or "auto-contrast" algorithm is applied to the raw scan, it inspects the minimum and maximum luminance values of the image. Because values $0$ and $255$ are already present on the borders, the histogram endpoints are already pegged:
$$\min(I) = 0, \quad \max(I) = 255$$
The algorithm concludes that the dynamic range is already fully utilized and performs **no transformation whatsoever**.

#### The Thresholding Solution
`film-develop` solves this by explicitly segmenting and discarding non-film pixels before calculating any statistics:
```python
WHITE_THRESHOLD = 245  # Clear glass / saturated backlight
BLACK_THRESHOLD = 12   # Plastic film holder borders / unexposed gaps
CLIP_PERCENTILE = 0.5  # Tail clipping
```
1. **Mask Generation:** A boolean mask is computed:
   $$M(x, y) = \begin{cases} 
   1 & \text{if } \text{BLACK\_THRESHOLD} < I(x, y) < \text{WHITE\_THRESHOLD} \\
   0 & \text{otherwise}
   \end{cases}$$
2. **Percentile Extraction:** Statistical percentiles are calculated *only* across pixels where $M(x, y) = 1$:
   $$P_{\text{low}} = \text{percentile}(I|_M, 0.5), \quad P_{\text{high}} = \text{percentile}(I|_M, 99.5)$$
3. This isolates the true optical dynamic range of the film emulsion, ignoring the scanner bed entirely.

---

### 2. C-41 Color Negative Inversion & Orange Mask Subtraction
Color negative film manufactured using the C-41 process (such as Kodak Portra, Fuji Pro 400H, or Ilford XP2) contains an **orange dye base mask** formed by colored dye couplers (azomethine and indaniline dyes). 

The orange mask exists in analog photography to correct for unwanted spectral absorption characteristics of cyan and magenta dyes during optical printing onto photographic paper. However, in digital capture:
* The orange mask adds a massive optical density offset in the red and green channels relative to the blue channel.
* If a C-41 negative is inverted naively via $I_{\text{inverted}} = 255 - I_{\text{raw}}$, the orange base ($R \gg G > B$) inverts into an intense cyan-blue cast ($B \gg G > R$) that completely destroys color fidelity.
* Furthermore, the chemical gamma (contrast response curve) differs across the three color layers:
  $$\gamma_{\text{red}} \neq \gamma_{\text{green}} \neq \gamma_{\text{blue}}$$

#### The Equalization & Midtone Matching Algorithm
`film-develop` eliminates the orange mask through a three-stage mathematical normalization:

1. **Per-Channel Endpoint Normalization:**
   For each color channel $c \in \{R, G, B\}$, the true film minimum $P_{\text{low}}(c)$ and maximum $P_{\text{high}}(c)$ are measured over the masked film area:
   $$I_{\text{norm}}(c) = \text{clamp}\left( \frac{I(c) - P_{\text{low}}(c)}{P_{\text{high}}(c) - P_{\text{low}}(c)}, 0.0, 1.0 \right)$$

2. **Inversion into Positive Space:**
   $$I_{\text{pos}}(c) = 1.0 - I_{\text{norm}}(c)$$

3. **Midtone Harmonic Balancing:**
   Simply stretching endpoints leaves the midtones uneven due to dye density slopes. The algorithm calculates the median luminance of each channel across midtone film pixels ($0.2 < I_{\text{pos}} < 0.8$):
   $$\mu_R = \text{median}(I_{\text{pos}}(R)), \quad \mu_G = \text{median}(I_{\text{pos}}(G)), \quad \mu_B = \text{median}(I_{\text{pos}}(B))$$
   A common target midtone $\mu_{\text{target}} = \frac{\mu_R + \mu_G + \mu_B}{3}$ is computed, and a gamma power correction $\gamma_c$ is applied to each channel:
   $$\gamma_c = \frac{\log(\mu_{\text{target}})}{\log(\mu_c)}$$
   $$I_{\text{final}}(c) = 255 \cdot \left( I_{\text{pos}}(c) \right)^{\gamma_c}$$
This completely strips the orange mask, producing neutral skin tones, true greys, and accurate color rendition without manual color grading.

---

### 3. Black-and-White Density Distribution
Black-and-white negatives contain no orange dye mask, but present their own distinct challenge:
* Silver gelatin negatives utilize only a fraction of the scanner's 8-bit or 16-bit sensor range, typically resulting in a muddy, low-contrast, milky appearance if inverted naively.
* Measuring channels independently (as in color film) would introduce catastrophic artificial color tints to what is supposed to be a monochrome image, due to slight optical differences in the scanner's RGB sensor elements.

#### The Monochromatic Neutralization Method
1. **Shared Unified Extrema:** A single minimum and maximum are calculated across all three color channels simultaneously:
   $$P_{\text{low}} = \min(P_{\text{low}}(R), P_{\text{low}}(G), P_{\text{low}}(B))$$
   $$P_{\text{high}} = \max(P_{\text{high}}(R), P_{\text{high}}(G), P_{\text{high}}(B))$$
2. **Channel Averaging:** All channels are inverted against the shared range and averaged into an exact neutral grey:
   $$Y(x, y) = 0.299 \cdot I_{\text{norm}}(R) + 0.587 \cdot I_{\text{norm}}(G) + 0.114 \cdot I_{\text{norm}}(B)$$
   $$I_{\text{final}}(R) = I_{\text{final}}(G) = I_{\text{final}}(B) = 255 \cdot (1.0 - Y(x, y))$$
This preserves the authentic grain structure and tonal depth of silver gelatin without introducing digital color noise.

---

### 4. Frame Quality Scoring (`negatives --analyze`)
To evaluate exposure health without relying on outliers, `film-develop` evaluates the **Interquartile Range (IQR)** of pixel intensities within each detected frame.

The 25th percentile ($Q_1$) and 75th percentile ($Q_3$) represent the core tonal meat of the photograph:
$$\text{IQR} = Q_3 - Q_1$$
* **Healthy Negative:** A well-exposed negative with rich shadow detail and controlled highlights exhibits an $\text{IQR} \approx 50.0 - 55.0$.
* **Thin / Underexposed Negative:** Lacks tonal separation; $Q_3$ and $Q_1$ collapse together, giving $\text{IQR} < 25.0$.
* **Blown / Dense Negative:** Emulsion is completely blocked up, compressing the dynamic range into clipping.

The quality metric is formulated as:
$$\text{Quality Score} = \text{clamp}\left( \frac{\text{IQR}}{\text{HEALTHY\_CONTRAST}}, 0.0, 1.0 \right) \quad (\text{where } \text{HEALTHY\_CONTRAST} = 55.0)$$
Frames scoring $\ge 0.5$ are marked as well-exposed. When developing a full roll, per-strip development parameters are calculated as a quality-weighted mean of its constituent frames, preventing an anomalous frame from corrupting the balance of the rest of the strip.

---

## 4. Headless GIMP Compositing (`digital-contact-sheet-maker`)

Once strip scans are prepared, `digital-contact-sheet-maker` drives GIMP in **headless batch mode** via Script-Fu (`film-contact-sheet.scm`):
```bash
gimp -i -b '(film-contact-sheet "path/to/roll" "Contact Sheets/roll.png" 0 "auto" TRUE TRUE)' -b '(gimp-quit 0)'
```
The flags `-i` (no GUI/X11 window) and `-b` (batch command) execute the layout algorithm with non-interactive speed.

### Layout Geometry Rules
The Script-Fu script adheres to physical constants:
* `@margin = 75` pixels ($0.25\text{ inch}$ at 300 DPI).
* `@gap = 24` pixels ($2\text{ mm}$ between adjacent film strips at 300 DPI).
* Background color is strictly **Black (`#000000`)**, replicating darkroom photo paper contact printing under glass.

```
+-------------------------------------------------------+
|  Canvas (e.g. 8x10: 2400 x 3000 px, Black Ground)     |
|                                                       |
|   Margin: 75px                                        |
|   +-----------------------------------------------+   |
|   | Strip 1 (Col 1) |Gap| Strip 2 (Col 2) |Gap|...|   |
|   |                 |24 |                 |24 |   |   |
|   |  Frame 1        |px |  Frame 4        |px |   |   |
|   |                 |   |                 |   |   |   |
|   |  Frame 2        |   |  Frame 5        |   |   |   |
|   |                 |   |                 |   |   |   |
|   |  Frame 3        |   |  Frame 6        |   |   |   |
|   +-----------------------------------------------+   |
|                                                       |
+-------------------------------------------------------+
```

#### Strip Rotation & Alignment Heuristics
1. **120 / 620 Medium Format (`columns` layout):**
   - Medium format strips (typically 3 exposures of 6×6, or 4 of 6×4.5) are scanned horizontally.
   - The engine rotates landscape strips by $90^\circ$ clockwise into vertical columns.
   - 4 strips stand side by side across the width of the 8×10 sheet.
2. **35mm Film (`rows` layout):**
   - 35mm strips (typically 5 to 6 exposures) are arranged horizontally.
   - Portrait-oriented scans are rotated $270^\circ$.
   - 6 to 7 strips stack from top to bottom along the vertical height of the sheet.
3. **Paper Selection & Auto-Fit:**
   The compositor tests three standard paper sizes at 300 DPI:
   - **8×10 inch:** $2400 \times 3000\text{ pixels}$
   - **A4:** $2480 \times 3508\text{ pixels}$
   - **US Letter:** $2550 \times 3300\text{ pixels}$
   If total strip dimensions exceed the available printable area after margins, every strip is scaled down by an identical uniform factor $S$:
   $$S = \min\left( \frac{W_{\text{paper}} - 2 \cdot \text{margin} - (N_{\text{cols}} - 1) \cdot \text{gap}}{\sum W_{\text{strips}}}, \frac{H_{\text{paper}} - 2 \cdot \text{margin} - (N_{\text{rows}} - 1) \cdot \text{gap}}{\sum H_{\text{strips}}} \right)$$

---

## 5. Elixir Coordinate Replay Engine (`Web.Negatives.SheetLayout`)

To make individual frames clickable on the website without maintaining image maps or manual bounding coordinates, Elixir transcribes the GIMP Script-Fu logic into pure functional arithmetic.

### Coordinate Translation Math
`frames.json` records the bounding rectangle of each frame within its unrotated, raw strip image:
$$\text{Region}_{\text{strip}} = \{x_{\text{strip}}, y_{\text{strip}}, w_{\text{strip}}, h_{\text{strip}}\}$$

`Web.Negatives.SheetLayout` transforms this into sheet coordinates:
1. **Rotation Transformation:**
   If the strip was rotated $90^\circ$ (for 120 columns):
   $$x' = y_{\text{strip}}, \quad y' = W_{\text{raw}} - x_{\text{strip}} - w_{\text{strip}}, \quad w' = h_{\text{strip}}, \quad h' = w_{\text{strip}}$$
   If rotated $270^\circ$ (for 35mm rows):
   $$x' = H_{\text{raw}} - y_{\text{strip}} - h_{\text{strip}}, \quad y' = x_{\text{strip}}, \quad w' = h_{\text{strip}}, \quad h' = w_{\text{strip}}$$
2. **Global Offset & Scaling:**
   Taking into account strip index $i$, scaling factor $S$, margin, and gap:
   $$X_{\text{sheet}} = \text{Margin} + i \cdot (W_{\text{strip}} \cdot S + \text{Gap}) + x' \cdot S$$
   $$Y_{\text{sheet}} = \text{Margin} + y' \cdot S$$
3. **Responsive Percentage Normalization:**
   To render identically across phones, 4K monitors, and tablet screens, coordinates are normalized against total canvas dimensions ($W_{\text{canvas}}, H_{\text{canvas}}$):
   $$\text{left} = \frac{X_{\text{sheet}}}{W_{\text{canvas}}} \times 100\%, \quad \text{top} = \frac{Y_{\text{sheet}}}{H_{\text{canvas}}} \times 100\%$$
   $$\text{width} = \frac{w' \cdot S}{W_{\text{canvas}}} \times 100\%, \quad \text{height} = \frac{h' \cdot S}{H_{\text{canvas}}} \times 100\%$$

### The Two Safety Gates (`Web.Negatives.Sheet`)
Before rendering any click target, Elixir verifies two strict conditions:
* **Gate 1 (Archive Freshness):** Verifies that the files currently on disk in the roll folder match `frames.json`'s `strips[].file` list in exact order. If an extra strip was scanned or an existing strip modified, the analysis is stale; Gate 1 trips, suppressing all overlays rather than showing misplaced targets.
* **Gate 2 (Dimension Proof):** Elixir reads the first 24 bytes of the contact sheet PNG header directly from disk to extract the physical width and height from the `IHDR` chunk. It runs `SheetLayout.compose/3` against each paper candidate. If the calculated dimensions do not match the real PNG dimensions to the exact pixel, Gate 2 trips.

---

## 6. Generative Grease Pencil Engine (`Web.Negatives.GreasePencil`)

In a traditional darkroom, a photographer reviews a dried contact sheet with a loupe and marks keeper frames using a red wax grease pencil (china marker). The waxy pencil skips over the glossy emulsion, wobbles slightly from human hand movement, and often loops twice as the circle closes.

Rendering static SVG ellipses or PNG stickers looks synthetic and digital. `streetscissors` procedurally generates authentic, organic wax china-marker marks using pure vector mathematics.

### Mathematical Formulation
1. **Deterministic Seeding:**
   To prevent layout shifting (CLS) between static dead-render and LiveView WebSocket connection, the seed is derived deterministically from the roll and frame numbers:
   $$\text{Seed} = \text{:erlang.phash2}(\{\text{roll}, \text{frame}\})$$
   Frame 3 of roll 12 receives the exact same unique circle on every render, across every server restart, while no two frames share the same circle.

2. **Tri-Harmonic Radial Modulation:**
   A circle of radius $R$ is sampled at $N = 32$ angular intervals $\theta_i \in [0, 2\pi]$. The radius at each angle is perturbed by three low-frequency sinusoidal harmonics (frequencies $k \in \{2, 3, 5\}$) with randomized phases $\phi_k$:
   $$r(\theta_i) = R \cdot \left( 1.0 + \sum_{k \in \{2, 3, 5\}} A_k \sin(k \theta_i + \phi_k) \right)$$
   Where amplitudes $A_k \in [0.03, 0.08]$ produce an organic, steady-handed wobble without looking jagged.

3. **Catmull-Rom Spline Smoothing:**
   The perturbed points $(x_i, y_i) = (r(\theta_i)\cos\theta_i, r(\theta_i)\sin\theta_i)$ are converted into smooth cubic Bézier segments using Catmull-Rom spline interpolation:
   The tangent $T_i$ at control point $P_i$ is determined by its adjacent neighbors:
   $$T_i = \frac{P_{i+1} - P_{i-1}}{2}$$
   The cubic control points $C_{1}, C_{2}$ between $P_i$ and $P_{i+1}$ are computed as:
   $$C_1 = P_i + \frac{T_i}{3}, \quad C_2 = P_{i+1} - \frac{T_{i+1}}{3}$$

4. **Double Wax Layer & Gloss Skip:**
   - **Main Stroke:** Rendered at full stroke width ($2.4\text{px}$) with opacity $0.92$.
   - **Return Pass:** A second stroke running along an offset trajectory with lighter opacity ($0.45$) simulates the second loop of the pencil.
   - **Gloss Skip:** Both strokes utilize dashed patterns normalized to SVG `pathLength="100"`:
     `stroke-dasharray="28, 1.2, 18, 0.8, 45, 1.5"`
     This replicates the waxy lead skipping over the smooth photographic paper.
   - **Vector Effect:** All marks declare `vector-effect: non-scaling-stroke`, ensuring that whether viewed on a mobile screen or zoomed into full resolution, the china marker retains its physical $2\text{mm}$ pencil line thickness.

---

## 7. Storage Structure & Filesystem Layout

The archive lives at `~/Pictures/Negatives/` (configurable via `NEGATIVES_PATH`):

```
~/Pictures/Negatives/
├── 120 Film/                               # Format directory
│   ├── roll001_2026-07-04_120_bw/          # Roll directory
│   │   ├── 001.tiff                        # Strip 1 scan (300 DPI)
│   │   ├── 002.tiff                        # Strip 2 scan (300 DPI)
│   │   ├── 003.tiff                        # Strip 3 scan (300 DPI)
│   │   ├── 004.tiff                        # Strip 4 scan (300 DPI)
│   │   ├── frames.json                     # Frame coordinates & quality scores
│   │   ├── 3.tiff                          # Keeper: High-res single frame rescan
│   │   └── 7.tiff                          # Keeper: High-res single frame rescan
├── 35mm Film/
│   └── roll002_2026-07-10_35mm_color/
├── Contact Sheets/
│   ├── roll001_2026-07-04_120_bw.png       # Assembled 300 DPI contact sheet
│   └── previews/
│       └── roll001_2026-07-04_120_bw.webp  # Max 2000px downscaled web preview
├── .trash/                                 # Retired rolls (freed roll numbers)
└── catalog.csv                             # Master index (roll,date,format,color,frames,dir)
```

---

## 8. Summary of Toolchain Commands

| Command | Purpose |
|---|---|
| `negatives` (or `film-intake`) | Interactive scan wizard: prompts for roll number, format, emulsion, and date; opens scanner; catalogs and builds sheet. |
| `negatives --list` | Lists all active rolls, taken numbers, formats, and identifies the next free roll number. |
| `negatives --delete NNN` | Retires roll `NNN`: moves scan folder to `.trash/`, purges `catalog.csv`, contact sheet PNG, and WebP preview. |
| `negatives --analyze NNN` | Splits strips into frames, measures exposure IQR, calculates quality-weighted development parameters, and writes `frames.json`. |
| `negatives --select NNN 2,5,9` | Stickers frames 2, 5, and 9 as keepers, triggering the red grease-pencil circle on the website. |
| `negatives --scan-frames NNN` | Interactive rescan helper for stickered keepers at high optical resolution ($2400-3200\text{ DPI}$). |
| `digital-contact-sheet-maker <dir>` | Invokes headless GIMP to assemble a contact sheet PNG from any directory of strip scans. |
| `film-develop strips <dest> --mode bw\|color <scans...>` | Runs the standalone Python C-41 / B&W density and masking engine. |

---

## 9. `film-develop` and the scanner studio (October 2026)

Sections 2 and 3 describe the pipeline as first built, for strips scanned in Epson's own program.
When the site's scanner studio arrived, `film-develop` (in `~/.local/bin`, outside this repo) was
reworked several times so it could read strips scanned on bare glass. These notes record what
changed and why, roll by roll. Each replaced copy of the tool is kept in
`~/film-pipeline-backups/<date>/`. Where this section and sections 2 and 3 disagree, this section
is current. In particular, 35mm is no longer cut into six frames a strip.

- **A frame's rectangle in `frames.json` is the picture itself**, rebate and film edges
  left out. That is why a single scanned in place gets no margin
  (`Driver.keeper_margin(:in_place)` is 0) and why the grease-pencil rings sit tighter.
- **35mm is cut on the film's fixed 38 mm grid**, so a strip holds however many frames it
  holds and frame numbers run on across strips of different lengths. The old tool cut
  every strip into six and cut through pictures on 19 of the archive's 53 strips.
  `mis_split` and the "Try --frames-per-strip" retry in `generate_frames_analysis/4` now
  only arise for 120 and 620, whose spacing is the camera's.
- **The roll sets the colour and a frame only its exposure** (the `film` block: base,
  a power per channel, white). Developing frame by frame is what tinted thin negatives.
  `develop` also removes small white dust specks unless told `--no-dust`.
- The whole archive was re-analysed and every sheet rebuilt that day.
- **Glass is never film** (2026-10-09; the copy it replaced is in
  `~/film-pipeline-backups/2026-10-09/`). A strip from the scanner studio is the whole
  holder slot, so there is bare glass beyond the film's ends, and the holder's grey edges
  down its sides pass the tool's film test. Three things went wrong from that: the film's
  extent ran on over the glass, the "film base" was read off it (238 where the film's is
  about 170, so no gap between frames ever read as bare), and the 38 mm grid was hung on
  the glass just past the film's end. Roll 035's first strip (two night frames, a third,
  and a fogged leader) had every frame cut 9 mm late. Now `glass_level/1` finds the glass,
  `film_on_glass/5` reads the strip down the middle of its width only, stops the film where
  the glass starts and measures base on the film, and `grid_35mm` looks for gaps on the
  film: between frames, and in the last millimetre inside each end (a cut between frames
  ends on rebate, a leader does not). **A scan that shows no glass (every roll before 031)
  is read exactly as before**, checked strip by strip. The frame is named
  (`FRAME_35MM = 36`, the gap is what the pitch leaves) and `analyze --frame-mm 18` is a
  half-frame camera. Rolls 031 to 036 were analysed by the old rule and are not redone;
  re-analysing one moves its frames by up to 2 mm, and by more on its short strips.
- **Slide film is a third mode** (2026-10-09, for a roll of E100). `film-develop` has
  `color`, `bw` and `slide`; a slide is already the picture, so nothing is inverted or
  colour-balanced (the roll's brightest highlight is white, the same in all channels, and
  a frame may only nudge its own black and white), frames are found by their **dark**
  gaps, and dust removal is skipped. **The site does not know the mode exists, and the tool tells
  by looking** (`film_look/1`): a roll the page calls colour is a slide when the
  clearest film down the middle of its strips is neutral (a colour negative's orange mask
  makes it far redder than blue) and at least 2% of it is true black. All eleven colour
  negative rolls in the archive read as negatives by it. `roll.json` outranks the look
  either way: a reversal stock under Film or `"process": "slide"` makes it a slide,
  `"process": "negative"` keeps it a negative. The page's own detection still has to call
  the roll **colour** (`Web.Scanner.Detect` knows only colour and black and white, and a
  roll taken for black and white is stored grey). 35mm only.
- **A slide developed badly is balanced channel by channel** (2026-10-09, six rolls of
  E100 that came out dense with a red black). The slide branch of `film_model` reads, per
  channel and pooled over the roll's pictures, a **black** (taken off: the film's read
  about 7, 2, 2 and every shadow wore it), a **contrast** (`power`: the film is crossed,
  red at twice green and blue through the midtones and level only near white, so each
  channel is bent until the roll's midtones agree, `SLIDE_BALANCE` of the way) and a
  **white** (held further back, since a roll's highlights are lamps and signs). A frame
  then sets its own white and raises its own midtones; one with nothing lit stays night.
  The roll decides the colour, never a frame. `roll.json` may overrule it:
  `"slide": {"lift": 1.2, "balance": 0.6, "warmth": 0.5}`. `film-develop redevelop ROLL`
  develops every single again, but **on a published roll go through
  `Web.Scanner.Pipeline.develop_keeper/2`** (by `bin/web rpc`), which also turns the print
  and remakes its previews. A slide's singles are scanned at **16 bits**
  (`Driver.band_args/5` `deep: true`, when `Scanner.slide?/1`); the print is 8.
- **A crossed colour negative gets a curve per channel, when roll.json says so**
  (2026-10-24). Film kept warm loses speed layer by layer, and a layer that starts late and
  catches up prints one colour in the shadows and another in the highlights, which one power
  per channel can't undo. With `"crossed": true` in `roll.json`, `layer_curves` reads each
  layer's rate against green at `CURVE_POINTS`, fits a straight line through the bends (log,
  against density) and keeps its two ends as the channel's `curve`; `apply_args` then draws
  the channel through a 16-bit lookup table (`clut_file`) instead of the divide and power.
  On synth's aged film (`Film.aged()`) a grey's channels part by 46 of 255 without it and 26
  with it, as fresh film does. **It is never automatic:** read off a roll's pictures, the bend
  is the scene's as much as the film's. Tried on every colour roll, it took a purple cast off
  roll 022's sky and put one on rolls 025 and 031, and most rolls bent to the limits.
- **A thin roll's contrast is held** (2026-10-24). The roll's contrast is the power that puts
  its middle density at a middle grey. On an underexposed roll much of the picture is bare
  film, and that power rose to the top of `POWER_LIMITS` (rolls 030, 067, 069, 070, with 44%
  to 59% of their pictures within `THIN_DENSITY` of the base; no other roll is over 36%),
  lifting grain and veil rather than shadows the negative never held. With `THIN_SHARE` of
  the picture on the base the roll is **thin**: its contrast is held to `THIN_POWER_MOST` and
  the diagnosis says so. A roll whose densest highlights stop under `FLAT_TOP` is **flat**
  (short development, or flat light) and is only named: raising the contrast is the right
  remedy for underdevelopment. Both go in `frames.json`'s `diagnosis` (`on_base`, and `top`
  as D), for colour rolls too, and `Pipeline.bath_notes/1` says them on the page.
  **A thin roll's singles are scanned at 16 bits** (its diagnosis says `deep`, which
  `Pipeline.deep?/1` reads): roll 067's pictures lie within D 0.05 to 0.25 of its base, and
  in an 8-bit scan its red held four steps, which the print pushed apart into posterised
  colour and blotchy grain. Its dense frames (02, 03) read red at a fifth of green and stay
  cyan whatever is done to the print; only a 16-bit rescan gives them back.
- **A developed single is finished by `film-finish`** (2026-10-24; `tools/film/bin/`, numpy
  and OpenCV, run by `film-develop` under the print repair's Python). Three steps, in place:
  - *Lines*: the print editor's line finder and per-channel gain/offset correction
    (`priv/repair/film_repair.py`, imported), so the green scanner line across rolls 064 to
    067 is gone from every single, not only from those repaired by hand.
  - *Dust*, replacing `remove_dust`, which left nearly every speck (a 7 px median and a 14%
    lift miss most specks on grainy film, and it never took a hair). A mark is thinner than
    13 px, stands out of the local spread of a top-hat by 5 (white) or 6 (dark) times, peaks
    6 times over the ground's grain, sits on plain ground with no edge beside it (read off a
    median of the print, so a speck's own blur is not an edge), and on colour **moved every
    free channel**: dust stops the lamp in every layer, a grain clump is one layer's dye.
    That last test is what kept faces clean (teeth, catchlights and hair strands were taken
    before it). Thin, long marks (hairs, fibres) clear a lower bar. Black and white has
    only size to go by (`DUST_K_GREY`). Long fibres across textured ground are left: the
    repair notes record that a line finder there found only real things.
  - *Balance*, colour only. Per brightness band the least coloured pixels give the print's
    grey axis, fitted per channel as a cast at the middle and a slope from shadow to
    highlight. Each print's reading goes into the roll's `finish.json`; the roll's cast is
    the median over its prints, and a print leans half of the way to its own warmth and
    0.8 of the way to its own tint. Tint (green against magenta) is taken off nearly whole,
    cold more than warmth, every move capped; a print past 1.5 times a cap is moved the
    most it may be and said `out_of_reach`. `redevelop` measures every print first and
    balances them after, so the first print of a roll is balanced as the last is.
  Tried on twelve rolls (colour 031, 048, 049, 064 to 067; black and white 034, 044, 057,
  060, 069) in a scratch copy: the lavender road and pavement of 031, 049, 065 and 067 went
  grey, 048's red face and 067's orange kitchen came back, lamp-lit rooms kept their
  warmth. A roll-wide fit of the grey axis on the raw densities (one base and power per
  channel) was tried first and moved little: the casts are frame by frame as much as roll by
  roll. About 8 s a print, most of it the line finder.
- **Medium format's frame count is read off the film** (`count_by_template/4`): 120 and
  620 are one film in different cameras, and a 620 roll of 6x9 (two to a strip) was being
  cut in three. On a strip on glass, each count from 2 to 6 is laid cut to cut and the one
  whose gaps are all gap wins; `--frames-per-strip` still insists. Scans without glass
  (every roll before 031) are counted as before.
- **The frame is 36 mm; the spacing is the camera's** (2026-10-09, roll 048, a camera
  that wound 41.8 mm on one strip and 467, 467, 430 px on the next). "38.00 mm apart
  whatever the camera" was wrong. On a strip on glass, a 38 mm grid that puts picture in
  one of its own gaps (`grid_cuts_a_picture/7`; only gaps with a frame kept on each side,
  since past the last frame there may be a fogged leader) gives way to
  **`walk_frames/6`**: the plainest frame is found first (gap outside, picture inside, at
  both ends of a 36 mm window, `_frame_score/5`) and the strip is walked each way from it,
  each next frame looked for from touching the last to 10 mm on, and a frame with no edge
  of its own set one spacing on so the count stays right. The walk is believed only where
  it differs from the grid by more than 2.5 mm, so an evenly wound roll keeps its grid.
  Every strip on glass is then cut as whole 36 mm frames, and **`snap_frames/6`** moves a
  frame up to 5 mm onto its own picture, but only for an edge at *both* its ends (a thin
  frame has edges inside it that pass for one).
- **A roll's contrast is the whole roll's when few frames score well**, and a dense
  frame may be darkened further (`GAMMA_LIMITS` low end 0.5, was 0.72). "Well exposed" is
  the spread of the *scan's* values, which a dense, overexposed negative squeezes, so on
  roll 048 one thin frame set the contrast for all seven and the rest printed blown.
  Under a third of the roll scoring well, `film_model` reads every frame. **The page's
  small positives and a developed single are the same recipe**: a preview that is too
  bright means the single will be.
- **A strip's film base is read off its film** when it is on glass. The whole-strip
  reading that feeds `film_model` took in the holder's grey edges, so a colour negative's
  base came out nearly neutral (blue 65 where the film's is 38) and every shadow printed
  blue. Scanner-era colour negatives analysed before this (031) carry that cast until
  analysed again.
- **Dark film is placed by a template of the frame, not by counting black lines**
  (`grid_by_template/6`, 2026-10-09, roll 037: night pictures on E100). Between two night
  frames a slide's gap is a third of a brightness level darker than the pictures, and a
  dark corner of a picture is exactly as black as a gap, so "is this line black" hung the
  grid on the pictures' shadows and every frame came out 4 to 7 mm off. The strip is now
  read as brightness with its fractions (`middle_trace/2`) and a grid of 36 mm frames and
  2 mm gaps is slid along it under two rules: **nothing of a picture may lie in a gap**
  (a gap is at the strip's own gap level within 6%, or that grid is out), and **a picture
  edge beside a gap is the score**. Frames it places stay on its grid, all the same size.
  A slide is always placed this way; **a negative on glass is, when its gaps do not read
  bare** (thin, fogged or expired film), and otherwise as before. With no evidence at
  all, a strip a whole number of frames long is laid end to end between its cuts
  (`whole_strip/3`). The page's own finder (`Web.Scanner.Detect`) also had to learn that
  a slot showing bare glass past the film's ends holds film even when the film is as
  black as the holder; film that dark is taken for reversal film, in colour. This was
  written against a slide made by inverting a negative strip, not yet against real E100.
- **Two pieces in one slot, and a camera that winds unevenly** (2026-10-11, roll 055; the
copy replaced is in `~/film-pipeline-backups/2026-10-11/`). Two short pieces of film
laid end to end in one slot are two strips: `film_on_glass` now keeps each stretch of
film parted by 2.5 mm of glass (`PIECE_GAP_MM`) and each is laid out by itself; one grid
across both cut the second piece at the first's spacing. **A studio strip that fills
its slot shows no glass**, so it was read by the oldest rule (a fixed 38 mm grid from
the film's start, "unaligned"): it is now read line by line like a strip on glass
(`strip_source` knows it by the studio's mark; scans from Epson's program are left as
they were). And where the clear film between pictures is plain to see,
**`frames_by_gaps/4` reads the pictures straight off it**, believed only when every
stretch is one frame long: strip 4 had a blank stretch after its first frame, and
every grid and the walk put the rest half a frame out. Thin film falls through to the
template as before.
- **The tool looks at its own answer** (2026-10-11, roll 060, his ask: "a feature that
retries the frame selection… so I'm not always prompting for the fix"). After a 35mm
strip on glass is laid out, `frames_miss/4` measures how much picture was left outside
every frame; 12 mm or more and `retry_frames/10` lays the strip every other way (the
plain grid, the template, the gaps, and `frames_by_runs/5`, which sets frames on each
stretch of picture and knows nothing of spacing) and keeps the one that leaves least
out. `frames.json` records it under `relaid` and the run prints "laid again by …".
**Only pictures left out count as wrong**: thin film reads as bare through its
pictures, so bare film inside a frame proves nothing. The page does not show `relaid`
yet, and has no button to ask for another cut.
- **The bath is read off the clear film** (2026-10-15, rolls 069 and 071: "the fixer
period was too short"; the copy replaced is in `~/film-pipeline-backups/2026-10-15/`).
Work in density: fog and the veil of a short fix or wash are density *added* to all
the film, gaps included, while development is a *gain* on the picture, so blank film
measures the first and never the second. Three things follow, black and white only:
- **Each strip may have its own clear film** (`strip_veils`, `gap_level`): read in the
  gaps between its frames, never the brightest of the whole strip (which moves with a
  fogged leader or a strip with no clear stretch, and moving bases on that wrecked
  sound rolls), and used only when the strip's gaps agree among themselves and sit 20%
  off the roll's (`VEIL_STEP`). The roll's contrast is still the roll's, read with every
  strip brought to the roll's base. On the roll's base a clearer strip printed black
  end to end: roll 069's second, roll 059's first three (Dodger Stadium).
- **`frames.json` carries a `diagnosis`** (`diagnose`) and the page says it after a look
  or an analysis (`Pipeline.bath_notes/1`): `veil` (clear film over D 0.50; the
  archive's sound rolls read 0.22 to 0.39, at the scanner's gamma of 1.8), `uneven`
  (strips' gaps more than 0.20 apart: fog at the roll's start, or fixed apart) and
  `blocked` (over 5% of the pictures under 8-bit 5, where the scan reads noise). Only
  said: a veil of undissolved halide comes off in fresh fixer and **darkens for good
  under any lamp, the scanner's included**, so the advice is to test a cut piece and
  refix before the singles. A veiled or blocked roll's singles are 16-bit
  (`Pipeline.deep?/1`, as a slide's). Nothing digital recovers what lies at the
  scanner's floor: roll 071 (clear film at D 2.0) printed blank from its look.
- **A negative denser than the holder's black is still film**: read off the glass
  alone, as a slide is, when that finds far more film, and a strip with a quarter of
  its film under `BLACK` keeps those pixels (`DENSE_STRIP_SHARE`). Analysed as black
  and white, roll 071 crashed on an empty gap reading before this.
- **A negative as black as a slide is told by its gaps** (2026-10-15; the copy replaced
  is in `~/film-pipeline-backups/2026-10-15-slide/`). Roll 071 was filed colour by the
  page and developed as a slide, because both took film mostly darker than the holder
  for reversal film. The film between frames has nothing on it, so it is a negative's
  clearest and a slide's blackest: where film is that dark, gaps are laid on it at the
  35mm pitch, and gaps 2.5 times as bright as the pictures' median (about 0.7 in
  density) make it a negative. `Web.Scanner.Detect` reads the look that way, a row to
  the millimetre between the glass at the film's ends (071 read 3.5 and 4.5 on looks
  rebuilt from its strips, no slide strip past 1.9), and then reads its colour as any
  other film's. `film-develop`'s `film_look/1` lays its frame template as a negative's
  (`clear_gaps`: 071 read 4.4 and 3.7, and only two of the 34 slide strips took such a
  grid at all, at 1.3 and 1.4), and calls a dense negative black and white when its gaps'
  channels part by under 0.4 in density (`MASK_DENSITY`: C-41 reads 0.65 to 1.26, 071
  about 0.2). **Roll 027's pink base reads 0.19**, so a colour roll that dense would be
  taken for black and white: `"process": "negative"` in `roll.json` keeps it colour. Old
  and new tools gave byte-identical `frames.json` for every other roll in the archive.
- **Medium format, and a strip scanned again** (2026-10-10, roll 023: "a disaster"). Three
things went wrong at once when one strip of an August roll was scanned again on the site.
**The strip was the whole bed.** No holder rectangle is configured for 120, so `add_pass/6`
cut 242 mm: the holder's own plastic past the glass (black in the scan, a block of white on
the sheet) and 60 mm of glass, which also shrank every picture on the sheet by a quarter.
With no rectangle, each strip is now cut to its own film and 4 mm of glass either end
(`film_rows/5`, `film_run/2`); `film-develop strips` paints out any holder left in an older
file (`holder_mask`). Rolls 023 and 047 were trimmed by hand that day (originals in
`~/film-pipeline-backups/2026-10-10/`). **The colour was another scanner's.** Epson's own
program set its levels scan by scan; the site takes what the scanner gives. The same film
base read 224, 141, 107 in the August strips and 177, 102, 75 in the new one, the roll's
base is the middle strip's, and the new strip and its three singles printed lavender.
`film-develop` now reads a roll scanned on two instruments as two (`strip_source/2`:
"glass" when the strip shows glass or carries the mark the site writes into every scan it
makes, `@studio_mark`, in the TIFF's description; "plain" otherwise), keeps both models in
`frames.json` (`films`), and `film` is the glass's, since a single is always scanned on
the glass. **A single off the glass of a frame whose strip is plain** (singles added to an
old roll) is developed on the roll's glass model when it has one and read by itself
otherwise; that second case is not yet checked against a real roll. **The end frames kept
their rebate**: `trim_to_pictures` stopped at the first line a shade less than bare, so a
strip's first picture kept 4 mm of clear film (a black bar on the print); it now carries
over such lines. And **a deleted strip is set aside** in the archive's `.trash`
(`set_aside/2`), not destroyed: deleting the strip to scan it again took its only scan.
Still as it was: a strip scanned again joins the end of the roll and has to be moved back
into place under Strips.
