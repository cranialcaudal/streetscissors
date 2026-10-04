# Custom Flatbed Scanner GUI: Architectural Blueprint & Specification

> **Status (2026-10-02).** This is the original design, kept for its reasoning. What was built
> differs: scans run through `Web.Scanner.Bed` (a GenServer holding a `scanimage` port), one
> strip placement per scan cut to a configured holder rectangle; strips are reordered with
> buttons, not drag and drop; the preview is a plain inversion, with no WebGL shader or rebate
> pipette; there is no bed-wide strip detection. `CLAUDE.md` describes the code as it is.

This document defines the architectural blueprint and technical specification for a **custom flatbed scanner GUI** specifically engineered for scanning film negatives and directly producing archives that conform to the hosting constraints and verification gates of **streetscissors**.

The application is designed to be accessible natively inside the `streetscissors` admin console at:
```
https://streetscissors.com/admin/scanner  (or http://localhost:4000/admin/scanner)
```

---

## 1. Problem Statement & Motivation

The current negative scanning workflow relies on a fragmented combination of separate tools:
1. A bash terminal wizard (`negatives`) to calculate roll names and create directories.
2. Epson's legacy Linux scanner software (`iscan` or `simple-scan`) to control the flatbed.
3. External file managers to inspect files.
4. Python scripts (`film-develop`) and headless GIMP Script-Fu (`digital-contact-sheet-maker`) to invert, analyze, and composite sheets.

### Inefficiencies of the Legacy Approach
* **Inverted Blindness:** When previewing negatives in standard scanner software (`iscan`), the user sees an orange-tinted negative. Evaluating exposure, focus, and framing requires completing the scan, running terminal commands, and inspecting the final image.
* **Manual Strip Numbering:** Strips must be manually named in filename order (`001.tiff`, `002.tiff`) during the scanner's save dialog. Loading a strip backwards or numbering out of order corrupts the physical sequence on the contact sheet.
* **Separation from the Web Studio:** The scanning process is decoupled from the web application, even though the scanner is physically plugged into the exact same workstation that serves the site.

### The Vision
An integrated **Darkroom Studio Console** mounted directly inside `streetscissors`'s authenticated admin area. It combines hardware scanner control, real-time positive previewing, computer-vision strip auto-detection, a virtual 8×10 contact sheet layout canvas, and zero-click web publishing.

---

## 2. System Architecture & Colocated Placement

Because the production Phoenix server runs on the physical host workstation where the flatbed scanner is connected via USB, the architecture takes advantage of direct local hardware access:

```
+-----------------------------------------------------------------------------------+
|                           ADMIN CLIENT (Desktop / iPad / Phone)                   |
|                                                                                   |
|  [ LiveView Studio Console: /admin/scanner ]                                      |
|  ├── Bed Preview & Rebate Pipette (HTML5 Canvas / WebGL Inversion Shader)        |
|  ├── Virtual 8x10 Contact Sheet Layout Canvas (Drag & Re-order Strips)            |
|  └── Roll Intake & Publishing Bar ([Scan Strips] [Assemble & Publish])           |
+------------------------------------------┬----------------------------------------+
                                           │ WebSocket (/live)
+------------------------------------------▼----------------------------------------+
|                          PHOENIX 1.8 / OTP SERVER (Host: Fedora)                  |
|                                                                                   |
|  WebWeb.AdminLive.Scanner (LiveView Module)                                       |
|    │                                                                              |
|    ▼                                                                              |
|  Web.Scanner.Driver (GenServer & Port Supervisor)                                 |
|    │                                                                              |
|    ├─► Elixir Port: stdin/stdout stream ──► [SANE scanimage / libsane C-Shim]     |
|    │                                                     │                        |
|    ├─► Port Worker: Python OpenCV / CV Engine            │                        |
|    │   (Auto-detects strip bounding boxes)               ▼                        |
|    │                                       [Epson Perfection V550/V600 (USB)]     |
|    ▼                                                                              |
|  Web.Scanner.Publisher (Workflow Orchestration)                                   |
|    ├── Writes raw strips: ~/Pictures/Negatives/<Format>/rollNNN_DATE.../          |
|    ├── Executes film-develop analyze -> frames.json                               |
|    ├── Executes digital-contact-sheet-maker -> Contact Sheets/rollNNN.png         |
|    ├── Verifies Gate 1 (frames.json sync) & Gate 2 (PNG IHDR dimensions)          |
|    ├── Generates 2000px WebP Preview via ImageMagick                              |
|    └── Appends roll record to catalog.csv                                         |
+------------------------------------------┬----------------------------------------+
                                           │ Request-time Filesystem Mount
+------------------------------------------▼----------------------------------------+
|                          PUBLIC APPLICATION (streetscissors.com)                  |
|                                                                                   |
|  WebWeb.NegativesLive -> Roll instantly live at /negatives/roll/NNN                |
+-----------------------------------------------------------------------------------+
```

---

## 3. Hardware & Driver Interface (SANE Layer)

The flatbed scanner communicates through the **Scanner Access Now Easy (SANE)** API via `libsane` and the `scanimage` utility.

### Scanner Parameters for Film Negatives
To scan negatives on modern flatbeds (e.g. Epson Perfection V550, V600, V850):
* **Transparency Unit (TPU):** The standard reflective white lid is detached or covered, and the top backlight lamp is activated.
  ```bash
  scanimage -d "epson2:libusb:001:004" --source "TPU8x10" ...
  ```
  *(or `--source "Film"` depending on backend revision)*.
* **Scan Modes & Bit Depth:**
  * **Preview Mode:** 8-bit RGB at $75\text{ DPI}$ or $100\text{ DPI}$ for rapid bed scanning ($< 10\text{ seconds}$).
  * **Contact Strip Mode:** 16-bit linear raw RGB (or 8-bit RGB) at **strictly 300 DPI**.
  * **Single Frame Keeper Mode:** 16-bit TIFF at $2400\text{ DPI}$ or $3200\text{ DPI}$ optical resolution.
* **Scan Geometry Constraints:**
  SANE coordinates define the active bed window in millimeters:
  `-l` (left-x), `-t` (top-y), `-x` (width), `-y` (height).

### The Elixir Port Driver (`Web.Scanner.Driver`)
LiveView processes must never block the Erlang VM's schedulers during a physical hardware scan that takes 30–60 seconds. The hardware is wrapped in an Elixir GenServer managing a child Port process:

```elixir
defmodule Web.Scanner.Driver do
  use GenServer
  require Logger

  @doc "Triggers a non-blocking preview scan of the flatbed."
  def preview_bed(caller_pid) do
    GenServer.cast(__MODULE__, {:start_preview, caller_pid})
  end

  @doc "Triggers a high-resolution strip scan for specified bounding boxes."
  def scan_strips(boxes, roll_meta, caller_pid) do
    GenServer.cast(__MODULE__, {:scan_strips, boxes, roll_meta, caller_pid})
  end

  # Callbacks execute inside supervised OTP GenServer, streaming chunks via send/2
end
```

---

## 4. Real-Time Inversion & Debayering Shader

In standard tools, the photographer stares at orange or dark inverted negatives on screen. The Custom Scanner GUI introduces a **Real-Time Positive Canvas Engine**:

```
[Raw Scanner Bed Frame] (Orange C-41 / Milky B&W)
            │
            ▼
[Pipette Tool / Auto-Rebate] ──► Samples unexposed film border: (D_R, D_G, D_B)
            │
            ▼
[WebGL Fragment Shader / Canvas 2D Pipeline]
  1. Subtract Orange Mask:
     I_norm(c) = (I_raw(c) - D_base(c)) / (I_white(c) - D_base(c))
  2. Invert:
     I_pos(c) = 1.0 - I_norm(c)
  3. Gamma Balance:
     I_final(c) = pow(I_pos(c), gamma_c)
            │
            ▼
[Real-Time 60 FPS Positive Preview on Canvas]
(User sees the true finished photograph before committing to final scan)
```

### The Inversion Shader (GLSL Fragment Shader)
```glsl
precision mediump float;
varying vec2 v_texCoord;
uniform sampler2D u_image;
uniform vec3 u_rebateDensity; // Sampled from orange border
uniform vec3 u_channelGammas; // Dynamic gamma adjustments
uniform float u_exposure;
uniform float u_contrast;

void main() {
    vec4 raw = texture2D(u_image, v_texCoord);
    
    // 1. Subtract film base rebate mask
    vec3 normalized = clamp((raw.rgb - u_rebateDensity) / (vec3(1.0) - u_rebateDensity), 0.0, 1.0);
    
    // 2. Invert negative to positive
    vec3 positive = vec3(1.0) - normalized;
    
    // 3. Apply channel-specific gamma correction to eliminate color cast
    vec3 balanced = pow(positive, u_channelGammas);
    
    // 4. Exposure & contrast curve adjustments
    vec3 exposed = balanced * u_exposure;
    vec3 contrasted = (exposed - 0.5) * u_contrast + 0.5;
    
    gl_FragColor = vec4(clamp(contrasted, 0.0, 1.0), 1.0);
}
```

---

## 5. Virtual 8×10 Contact Sheet Canvas & Strip Reordering

The core interface of the GUI reflects the physical paper constraints of `streetscissors`:

### Virtual Canvas Specifications
* **Aspect Ratio:** Strictly locked to an 8×10 inch portrait sheet ($2400 \times 3000\text{ px}$ at 300 DPI, aspect ratio $0.80$).
* **Canvas Background:** Pure Black (`#000000`), emulating unexposed photographic contact paper.
* **Layout Grid Rules:**
  * **120 / 620 Film:** 4 vertical columns with `@margin 75px` ($0.25\text{ in}$) and `@gap 24px` ($2\text{ mm}$).
  * **35mm Film:** 6 horizontal rows with `@margin 75px` and `@gap 24px`.

### Strip Reordering Interaction
When film strips are placed on the glass bed:
* A photographer may accidentally place Strip 2 on the left of Strip 1, or lay a strip backwards.
* The Virtual Canvas allows the user to **click and drag strips** into the correct chronological order, and click a **Flip $180^\circ$** toggle.
* When the user clicks "Assemble Roll", the GUI writes the files with corrected numbering:
  * Slot 1 on canvas $\rightarrow$ `001.tiff`
  * Slot 2 on canvas $\rightarrow$ `002.tiff`
  * Slot 3 on canvas $\rightarrow$ `003.tiff`
  * Slot 4 on canvas $\rightarrow$ `004.tiff`
This guarantees that alphabetical order strictly matches visual layout, fulfilling the fundamental assumption of `Web.Negatives.SheetLayout`.

---

## 6. Site-Conformance Engine & Automated Verification

Before a newly scanned roll is finalized, the GUI runs the **Site-Conformance Pipeline**:

```
+-----------------------------------------------------------------------+
|                    SITE CONFORMANCE VALIDATION                        |
|                                                                       |
|  [Step 1] File Structure Check:                                       |
|           • Format directory exists (e.g. 120 Film/)                  |
|           • Roll folder named: rollNNN_YYYY-MM-DD_FORMAT_COLOR        |
|           • Strip scans named 001.tiff..N.tiff (all > 0 bytes)        |
|                                                                       |
|  [Step 2] Metadata & Analysis Generation:                             |
|           • film-develop analyze executed                             |
|           • frames.json written with frame regions & quality scores   |
|                                                                       |
|  [Step 3] Contact Sheet Composition:                                  |
|           • GIMP Script-Fu renders Contact Sheets/rollNNN.png         |
|           • Black background (#000000) verified                       |
|                                                                       |
|  [Step 4] LiveView Gate Pre-Flight Tests:                             |
|           • Gate 1: Web.Negatives.Sheet.verify_gate_1(roll_dir) == :ok|
|           • Gate 2: Web.Negatives.Sheet.verify_gate_2(png_path) == :ok|
|                                                                       |
|  [Step 5] Downscaled Preview Generation:                              |
|           • ImageMagick converts PNG -> Contact Sheets/previews/*.webp|
|           • Max 2000px, 82 quality                                    |
|                                                                       |
|  [Step 6] Master Catalogue Update:                                    |
|           • Row appended to catalog.csv:                              |
|             rollNNN,2026-10-02,120,bw,12,120 Film/rollNNN_...         |
+-----------------------------------------------------------------------+
```

If either Gate 1 or Gate 2 fails during pre-flight, the GUI halts, displays an explanatory diagnostic in the admin interface, and prevents publishing until corrected.

---

## 7. Single-Frame Keeper Rescan Mode

After the contact sheet is assembled and displayed in the GUI:
1. **Interactive Stickering:**
   - The user clicks on any frame on the virtual contact sheet.
   - The GUI applies a procedural red wax china-marker circle (identical to `Web.Negatives.GreasePencil`).
   - This records the frame into the roll's selects list.
2. **High-Resolution Optical Rescan:**
   - The user selects a stickered frame and clicks `[Rescan Keeper Frame]`.
   - The GUI prompts the user to place the negative into the scanner's single-frame high-resolution holder.
   - The scanner runs at **2400 DPI** or **3200 DPI** with 16-bit depth.
   - The image is developed using the strip's quality-weighted parameters (blending 70% strip profile / 30% individual frame reading).
   - Saved directly as `<frame_number>.tiff` (e.g. `3.tiff`) inside the roll's folder.
3. **Instant Web Availability:**
   - `streetscissors` detects `<frame_number>.tiff` at request time.
   - The individual frame page [`/negatives/roll/NNN/frame/<N>`](https://streetscissors.com/negatives) becomes immediately functional with high-resolution zooming and metadata.

---

## 8. Implementation Roadmap

The custom scanner GUI can be rolled out in four progressive milestones:

### Phase 1: The SANE & Driver Bridge
* Implement `Web.Scanner.Driver` GenServer supervising an asynchronous port to `scanimage`.
* Support USB device detection and Transparency Unit (TPU) mode switching.
* Implement flatbed low-DPI preview capture streaming into LiveView.

### Phase 2: LiveView Studio Console (`/admin/scanner`)
* Build the `/admin/scanner` LiveView template under `WebWeb.AdminLive.Scanner`.
* Add the **"Darkroom"** section and navigation link in `WebWeb.AdminNav`.
* Embed the HTML5 Canvas / WebGL real-time inversion shader with the interactive rebate pipette.

### Phase 3: The Virtual Contact Canvas & Strip Segmentation
* Implement the interactive 8×10 virtual contact sheet canvas.
* Implement drag-and-drop strip sequencing and orientation toggles.
* Connect strip cropping coordinates directly to 300 DPI scan passes.

### Phase 4: Automated Assembly & Conformance Gatekeeper
* Integrate automated execution of `film-develop analyze` and GIMP Script-Fu compositing.
* Integrate pre-flight execution of `Web.Negatives.Sheet` Gate 1 and Gate 2.
* Wire the keeper rescan helper to save `<frame_number>.tiff` directly into the roll folder.
