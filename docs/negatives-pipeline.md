# Film Negatives Pipeline: Architecture, Mathematics & Integration

This document is the definitive technical specification of the analog-to-digital film pipeline powering **streetscissors** (`https://streetscissors.com/negatives`) and its accompanying toolchain (`~/negatives`).

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
