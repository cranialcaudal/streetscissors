"""film_repair: finds and repairs the marks a scan carries, for the print editor.

    film_repair.py detect IMAGE MASK --lines
    film_repair.py lama IMAGE MASK OUT --model LAMA_ONNX
    film_repair.py diffuse IMAGE MASK OUT --model SD_INPAINT_DIR [--steps N]

detect writes a mask (white where a mark is) of what plain image processing
finds, for the author to look at and correct; it never repairs anything.

* A scanner line is a row (or column) of the scan that differs from its
  neighbours along most of the picture's width: its median, per channel, is
  set against a running median of the rows around it.
* Scratches and hairs are painted by hand. A finder for them was tried
  (thin, long marks standing out of a small median) and on the author's
  prints every mark it found was a real thing: branches, railings, a wire,
  a highlight along a shelf. So it was taken out.

lama first takes out the scanner's lines, then repairs what is left of the
mask with LaMa.

* A line is a run of rows (or columns) the mask covers the whole way along.
  It is a fault of the scanner, the same all along, so the picture under it
  is still there: each row, each channel, is a gain and an offset away from
  what the rows on both sides say it should be, fitted along the row and
  undone. The clock and the television under the Powell Camera print's line
  come back as they were, where LaMa painted plausible ones.
* What a line took past bringing back goes to LaMa: pixels it pushed to
  black or white, rows it all but blanked, and rows a gain and offset do
  not explain (a scratch along the film, which varies as it goes).

LaMa (Suvorov et al., big-lama, as the Apache-2.0 ONNX port
Carve/LaMa-ONNX) runs on the CPU by onnxruntime:

* at the picture's own resolution, in 512-pixel windows over the marked
  places (a long line takes several, overlapping), never on the whole frame;
* only the marked pixels are taken from LaMa, eased in over two pixels;
* LaMa paints smooth where film has grain, so grain is put back: the noise
  of the unmarked ring around each place (the picture less a light blur) is
  measured per channel and drawn again into what was repaired.

diffuse repairs large damage with Stable Diffusion 1.5 inpainting
(CreativeML OpenRAIL-M), lines corrected first as lama does, in the same
windows, with the same easing and grain. It invents what was there, so its
result is only ever a candidate the author looks at before keeping, and it
runs under a Python of its own (PyTorch on the CPU, diffusers). The prompt
asks for nothing but the film; the seed is fixed, so the same mask gives the
same candidate. It peaks at 2.1 GB (the site runs it under a 3 GB cap), and
takes about two minutes a window at 15 steps on this machine.
FILM_REPAIR_MEMORY=1 prints the memory it holds at each stage.

Prints one JSON line saying what was done. Nothing is downloaded.
"""

import argparse
import json
import sys

import cv2
import numpy as np

WINDOW = 512
STRIDE = 448


def read(path):
    image = cv2.imread(path, cv2.IMREAD_UNCHANGED)
    if image is None:
        sys.exit(f"cannot read {path}")
    if image.ndim == 2:
        image = cv2.cvtColor(image, cv2.COLOR_GRAY2BGR)
    if image.shape[2] == 4:
        image = image[:, :, :3]
    return image


def as_float(image):
    top = 65535.0 if image.dtype == np.uint16 else 255.0
    return image.astype(np.float32) / top, top


# ── Detection ──────────────────────────────────────────────────────────


def find_lines(f):
    """Rows and columns that stand out from the rows on both sides, the whole way along.

    Rows are smoothed along their length (41 pixels), which averages grain
    away and keeps a scanner's line, which runs the whole width. A row is a
    line where, along most of its length, it differs from the rows above it
    and from the rows below it in the same direction, by more than four times
    this picture's own row-to-row noise: an edge (the frame's, a horizon)
    differs from one side only, and grain from neither, once smoothed.
    The outer 2% of the frame is left out.
    """
    mask = np.zeros(f.shape[:2], np.uint8)
    for axis in (0, 1):
        img = np.ascontiguousarray(f if axis == 0 else f.transpose(1, 0, 2))
        h, w, _ = img.shape
        smooth = cv2.blur(img, (41, 1))
        margin = max(int(h * 0.02), 10)
        rows = range(margin, h - margin)
        up = {r: np.median(smooth[r - 8 : r - 2], axis=0) for r in rows}
        down = {r: np.median(smooth[r + 3 : r + 9], axis=0) for r in rows}
        # This picture's row-to-row noise, robustly.
        sample = np.concatenate([(smooth[r] - (up[r] + down[r]) / 2).ravel() for r in rows[:: max(len(rows) // 200, 1)]])
        sigma = 1.4826 * np.median(np.abs(sample - np.median(sample))) + 1e-4
        cores = []
        for r in rows:
            du, dd = smooth[r] - up[r], smooth[r] - down[r]
            same = np.sign(du) == np.sign(dd)
            strength = np.where(same, np.minimum(np.abs(du), np.abs(dd)), 0.0).max(axis=1)
            if np.mean(strength > 4 * sigma) > 0.6:
                cores.append(r)
        # A line's fringe and echo can run well past its core: on the Powell
        # Camera print a fainter copy lies 16 to 22 rows below, with a few
        # nearly clean rows between. Grow each core while rows still lean
        # the line's way against the background beyond any echo (rows 30 to
        # 45 away), stepping over gaps of up to three rows, up to 28 rows.
        # Only the channels the line is in are looked at (that one is a loss
        # of red; green and blue are untouched and would only add noise).
        for r in cores:
            far = np.median(np.concatenate([smooth[max(r - 45, 0) : max(r - 29, 0)], smooth[r + 30 : r + 46]]), axis=0)
            core = np.median(smooth[r] - far, axis=0)
            channels = np.abs(core) > 4 * sigma
            if not channels.any():
                channels = np.abs(core) == np.abs(core).max()
            lean = np.sign(smooth[r] - far)[:, channels]
            first, last = r, r
            for step in (-1, 1):
                k, j, gap = r, r, 0
                while abs(j + step - r) <= 28 and 0 <= j + step < h and gap <= 3:
                    j += step
                    row = (smooth[j] - far)[:, channels]
                    if np.mean((np.sign(row) == lean) & (np.abs(row) > 2 * sigma)) > 0.5:
                        k, gap = j, 0
                    else:
                        gap += 1
                first, last = (k, last) if step < 0 else (first, k)
            band = slice(max(first - 1, 0), last + 2)
            if axis == 0:
                mask[band, :] = 255
            else:
                mask[:, band] = 255
    # Several cores grow into one band: a line is a band.
    return mask, len(line_bands(mask))


def detect(args):
    image = read(args.image)
    f, _ = as_float(image)
    mask = np.zeros(f.shape[:2], np.uint8)
    said = {}
    if args.lines:
        m, n = find_lines(f)
        mask |= m
        said["lines"] = n
    cv2.imwrite(args.mask, mask)
    said["marked"] = float(np.mean(mask > 0))
    print(json.dumps(said))


# ── Repair ─────────────────────────────────────────────────────────────


def windows(mask):
    """512-pixel windows that together cover every marked pixel. A mark
    already inside a window (a line's clipped pixels lie scattered along it)
    gets none of its own."""
    h, w = mask.shape
    count, labels, stats, _ = cv2.connectedComponentsWithStats((mask > 0).astype(np.uint8))
    out = []
    margin = 16
    for i in range(1, count):
        x, y, bw, bh, _ = stats[i]
        if any(
            wx + margin <= x and x + bw <= wx + WINDOW - margin and wy + margin <= y and y + bh <= wy + WINDOW - margin
            for wx, wy in out
        ):
            continue
        xs = range(x, x + bw, STRIDE) if bw > WINDOW else [x + bw // 2 - WINDOW // 2]
        ys = range(y, y + bh, STRIDE) if bh > WINDOW else [y + bh // 2 - WINDOW // 2]
        for wx in xs:
            for wy in ys:
                wx0 = int(min(max(wx, 0), max(w - WINDOW, 0)))
                wy0 = int(min(max(wy, 0), max(h - WINDOW, 0)))
                out.append((wx0, wy0))
    return sorted(set(out))


def line_bands(mask):
    """Runs of rows (axis 0) or columns (axis 1) the mask covers nearly the
    whole way along: the scanner's lines, as `detect --lines` marks them."""
    bands = []
    for axis in (0, 1):
        full = (mask > 0).mean(axis=1 - axis) > 0.95
        edges = np.flatnonzero(np.diff(np.concatenate([[0], full.astype(np.int8), [0]])))
        bands += [(axis, int(a), int(b) - 1) for a, b in zip(edges[::2], edges[1::2])]
    return bands


def correct_line(f, first, last):
    """Undoes a scanner line in rows first..last of f (floats, changed in
    place). The rows beyond it on both sides, smoothed along their length and
    blended across the band, say what each row should be; each channel of
    each row is fitted to that as a gain and an offset (least squares, then
    again on the best 70%, so the picture's own differences do not count)
    and the fit undone. Returns, as a mask the size of f, what could not be
    brought back, for LaMa."""
    h, w, _ = f.shape
    lost = np.zeros((h, w), np.uint8)
    lo, hi = max(first - 6, 0), min(last + 7, h)
    smooth = cv2.blur(np.ascontiguousarray(f[lo:hi]), (41, 1))
    above = smooth[: max(first - 1 - lo, 0)]
    below = smooth[last + 2 - lo :]
    if len(above) == 0 and len(below) == 0:
        lost[first : last + 1] = 1
        return lost
    above = above.mean(axis=0) if len(above) else below.mean(axis=0)
    below = below.mean(axis=0) if len(below) else above
    # How much the picture itself changes across the band, per channel.
    across = np.median(np.abs(above - below), axis=0) + 1 / 255
    for j in range(first, last + 1):
        t = (j - first + 1) / (last - first + 2)
        expected = (1 - t) * above + t * below
        raw = f[j].copy()
        for c in range(f.shape[2]):
            x, y = smooth[j - lo, :, c], expected[:, c]
            fit = np.stack([y, np.ones_like(y)], 1)
            ab = np.linalg.lstsq(fit, x, rcond=None)[0]
            for _ in range(3):
                off = np.abs(fit @ ab - x)
                keep = off < np.quantile(off, 0.7)
                ab = np.linalg.lstsq(fit[keep], x[keep], rcond=None)[0]
            gain, offset = ab
            residue = np.median(np.abs(fit @ ab - x))
            departure = np.median(np.abs(x - y))
            # Far off, and not by a gain and offset: a scratch, not a line.
            if departure > 4 * across[c] and residue > 0.5 * departure:
                lost[j] = 1
                break
            # Off by no more than the picture's own differences: untouched.
            if departure <= 2 * residue or (abs(gain - 1) <= 0.03 and abs(offset) <= 2 / 255):
                continue
            # Blanked past bringing back.
            if gain < 0.35:
                lost[j] = 1
                break
            f[j, :, c] = (raw[:, c] - offset) / gain
            lost[j] |= ((raw[:, c] <= 1 / 255) | (raw[:, c] >= 254 / 255)).astype(np.uint8)
        if lost[j].all():
            f[j] = raw
    return lost


def grain(f, hole, near):
    """Per-channel noise of the ring around a hole: the picture less a light blur."""
    detail = f - cv2.GaussianBlur(f, (0, 0), 1.2)
    ring = (near > 0) & (hole == 0)
    if ring.sum() < 50:
        return np.zeros(3, np.float32)
    return detail[ring].std(axis=0)


def repair(args, fill=None, fill_all=None):
    """Fills what the mask covers, window by window, taking only the marked
    pixels, eased in, with the grain put back. `fill(rgb, hole)` fills one
    window at a time, each seeing what the windows before it filled;
    `fill_all([(rgb, hole), ...])` is given every window at once, as made
    before any is filled (Stable Diffusion, which loads its parts one after
    another)."""
    image = read(args.image)
    f, top = as_float(image)
    mask = cv2.imread(args.mask, cv2.IMREAD_GRAYSCALE)
    if mask is None or mask.shape != f.shape[:2]:
        sys.exit("the mask does not match the picture")
    mask = (mask > 127).astype(np.uint8)
    h, w = mask.shape
    out = f.copy()
    rng = np.random.default_rng(7)
    done = 0

    # The scanner's lines are corrected, not painted; LaMa gets what they lost.
    bands = line_bands(mask)
    lost = np.zeros_like(mask)
    for axis, first, last in bands:
        if axis == 0:
            lost |= correct_line(out, first, last)
            mask[first : last + 1, :] = 0
        else:
            lost |= correct_line(out.transpose(1, 0, 2), first, last).T
            mask[:, first : last + 1] = 0
    if lost.any():
        mask |= cv2.dilate(lost, np.ones((3, 3), np.uint8))

    cw, ch = min(WINDOW, w), min(WINDOW, h)

    def prepare(wx, wy):
        crop = out[wy : wy + ch, wx : wx + cw].copy()
        hole = mask[wy : wy + ch, wx : wx + cw]
        pad_img = crop[:, :, ::-1]
        pad_mask = hole.astype(np.float32)
        if ch < WINDOW or cw < WINDOW:
            pad_img = cv2.copyMakeBorder(pad_img, 0, WINDOW - ch, 0, WINDOW - cw, cv2.BORDER_REFLECT)
            pad_mask = cv2.copyMakeBorder(pad_mask, 0, WINDOW - ch, 0, WINDOW - cw, cv2.BORDER_CONSTANT, value=0)
        return crop, hole, np.ascontiguousarray(pad_img, np.float32), pad_mask

    def blend(wx, wy, crop, hole, filled):
        filled = filled[:ch, :cw, ::-1].astype(np.float32)
        near = cv2.dilate(hole, np.ones((15, 15), np.uint8))
        sigma = grain(crop, hole, near)
        noise = rng.standard_normal(filled.shape).astype(np.float32)
        noise = cv2.GaussianBlur(noise, (0, 0), 0.6)
        noise /= noise.std() + 1e-6
        filled = filled + noise * sigma
        soft = cv2.GaussianBlur(cv2.dilate(hole, np.ones((3, 3), np.uint8)).astype(np.float32), (0, 0), 1.0)
        soft = np.clip(soft * 1.5, 0, 1)[:, :, None]
        out[wy : wy + ch, wx : wx + cw] = crop * (1 - soft) + filled * soft

    places = [(wx, wy) for wx, wy in windows(mask) if mask[wy : wy + ch, wx : wx + cw].any()]
    if fill_all is not None:
        jobs = [(wx, wy) + prepare(wx, wy) for wx, wy in places]
        if jobs:
            for (wx, wy, crop, hole, _, _), filled in zip(jobs, fill_all([(j[4], j[5]) for j in jobs])):
                blend(wx, wy, crop, hole, filled)
        done = len(jobs)
    else:
        for wx, wy in places:
            crop, hole, pad_img, pad_mask = prepare(wx, wy)
            blend(wx, wy, crop, hole, fill(pad_img, pad_mask))
            done += 1

    out = np.clip(out, 0, 1)
    result = (out * top + 0.5).astype(image.dtype)
    if cv2.imread(args.image, cv2.IMREAD_UNCHANGED).ndim == 2:
        result = cv2.cvtColor(result, cv2.COLOR_BGR2GRAY)
    cv2.imwrite(args.out, result)
    print(json.dumps({"lines": len(bands), "windows": done, "repaired": float(mask.mean())}))


def lama(args):
    import onnxruntime as ort

    session = ort.InferenceSession(args.model, providers=["CPUExecutionProvider"])

    def fill(rgb, hole):
        # The mark itself must not be seen: LaMa is given the picture with
        # the marked pixels blank, as its training gave it.
        feed = {
            "image": (rgb * (1.0 - hole[:, :, None])).transpose(2, 0, 1)[None],
            "mask": hole[None, None],
        }
        result = session.run(None, feed)[0][0].transpose(1, 2, 0)
        return result / 255.0 if result.max() > 2 else result

    repair(args, fill)


PROMPT = "a photograph on film, natural film grain"
NEGATIVE = "text, letters, watermark, face, person, frame, border"


def diffuse(args):
    """Stable Diffusion 1.5 inpainting on the CPU in under 3 GB. The model's
    parts are loaded one after another and each let go before the next: the
    image encoder (every window's picture, masked), the text encoder (the
    prompt), the UNet (every window's fill), the image decoder. The UNet is
    kept at half precision and each layer worked at full precision as it is
    reached, since this CPU does no half-precision arithmetic of its own and
    the whole UNet at full precision is 3.4 GB. A window's latent mask covers
    a cell more than the mark; only the mark is taken back."""
    import ctypes
    import gc
    import os

    # Two allocator pools, not one per thread: with PyTorch's dozen threads
    # each keeping its own, memory let go is scattered where no part can use it.
    libc = ctypes.CDLL("libc.so.6")
    libc.mallopt(-8, 2)  # M_ARENA_MAX

    import torch
    import torch.nn.functional as F
    from diffusers import AutoencoderKL, DPMSolverMultistepScheduler, UNet2DConditionModel
    from transformers import CLIPTextModel, CLIPTokenizer

    torch.set_num_threads(max(1, (os.cpu_count() or 2) - 2))
    model = args.model
    half = {"variant": "fp16"}

    # Memory let go is handed back to the system, or the next part loads on
    # top of the last one: freed, the image encoder kept the process at 0.9 GB.
    def let_go():
        gc.collect()
        libc.malloc_trim(0)

    def lift(layer):
        """A convolution or linear layer works at full precision on a copy of
        its weights made as it is reached and dropped after; its own weights
        stay as loaded, at half precision. (diffusers' layerwise casting
        writes a new half-precision copy of every layer after each use, and
        the allocator's fragments grew the process past 3 GB in 30 steps.)
        The norms, under a megabyte, are simply kept at full precision."""
        if isinstance(layer, (torch.nn.GroupNorm, torch.nn.LayerNorm)):
            layer.to(torch.float32)
        elif isinstance(layer, (torch.nn.Conv2d, torch.nn.Linear)):
            kept = {name: p.data for name, p in layer.named_parameters(recurse=False)}

            def before(module, _inputs):
                for name, data in kept.items():
                    getattr(module, name).data = data.float()

            def after(module, _inputs, _output):
                for name, data in kept.items():
                    getattr(module, name).data = data

            layer.register_forward_pre_hook(before)
            layer.register_forward_hook(after)

    def rss(what):
        if os.environ.get("FILM_REPAIR_MEMORY"):
            kb = int(open("/proc/self/status").read().split("VmRSS:")[1].split()[0])
            print(f"memory {what}: {kb // 1024} MB", file=sys.stderr, flush=True)

    def fill_all(jobs):
        with torch.inference_mode():
            # The pictures, masked, as the image encoder sees them.
            rss("start")
            vae = AutoencoderKL.from_pretrained(model, subfolder="vae", torch_dtype=torch.float32, **half)
            rss("vae loaded")
            scale = vae.config.scaling_factor
            prepared = []
            for rgb, hole in jobs:
                wide = cv2.dilate((hole > 0).astype(np.uint8), np.ones((17, 17), np.uint8)).astype(np.float32)
                image = torch.from_numpy(np.clip(rgb, 0, 1)).permute(2, 0, 1)[None] * 2 - 1
                marked = torch.from_numpy(wide)[None, None]
                masked = vae.encode(image * (marked < 0.5)).latent_dist.mode() * scale
                small = F.interpolate(marked, size=masked.shape[-2:], mode="nearest")
                prepared.append((masked, small))
            rss("pictures encoded")
            del vae
            let_go()
            rss("vae let go")

            # The words.
            tokenizer = CLIPTokenizer.from_pretrained(model, subfolder="tokenizer")
            text = CLIPTextModel.from_pretrained(model, subfolder="text_encoder", torch_dtype=torch.float32, **half)

            def embed(words):
                ids = tokenizer(words, padding="max_length", max_length=tokenizer.model_max_length, truncation=True, return_tensors="pt").input_ids
                return text(ids)[0]

            context = torch.cat([embed(NEGATIVE), embed(PROMPT)])
            del text, tokenizer
            let_go()
            rss("words done")

            # The fills.
            unet = UNet2DConditionModel.from_pretrained(model, subfolder="unet", torch_dtype=torch.float16, **half)
            rss("unet loaded")
            for layer in unet.modules():
                lift(layer)
            rss("unet hooked")
            scheduler = DPMSolverMultistepScheduler.from_pretrained(model, subfolder="scheduler")
            latents_out = []
            for masked, small in prepared:
                scheduler.set_timesteps(args.steps)
                generator = torch.Generator().manual_seed(7)
                latents = torch.randn(masked.shape, generator=generator) * scheduler.init_noise_sigma
                for t in scheduler.timesteps:
                    pair = scheduler.scale_model_input(torch.cat([latents] * 2), t)
                    feed = torch.cat([pair, torch.cat([small] * 2), torch.cat([masked] * 2)], dim=1)
                    noise = unet(feed, t, encoder_hidden_states=context).sample
                    plain, guided = noise.chunk(2)
                    latents = scheduler.step(plain + 6.0 * (guided - plain), t, latents).prev_sample
                    rss(f"step {t}")
                latents_out.append(latents)
                rss("window filled")
            del unet
            let_go()
            rss("unet let go")

            # The pictures again.
            vae = AutoencoderKL.from_pretrained(model, subfolder="vae", torch_dtype=torch.float32, **half)
            filled = []
            rss("vae loaded again")
            for latents in latents_out:
                image = vae.decode(latents / scale).sample[0]
                rss("decoded")
                filled.append(((image.permute(1, 2, 0).numpy() + 1) / 2).clip(0, 1).astype(np.float32))
            return filled

    repair(args, fill_all=fill_all)


def main():
    parser = argparse.ArgumentParser(prog="film_repair")
    sub = parser.add_subparsers(dest="command", required=True)
    d = sub.add_parser("detect")
    d.add_argument("image")
    d.add_argument("mask")
    d.add_argument("--lines", action="store_true")
    l = sub.add_parser("lama")
    l.add_argument("image")
    l.add_argument("mask")
    l.add_argument("out")
    l.add_argument("--model", required=True)
    g = sub.add_parser("diffuse")
    g.add_argument("image")
    g.add_argument("mask")
    g.add_argument("out")
    g.add_argument("--model", required=True)
    g.add_argument("--steps", type=int, default=15)
    args = parser.parse_args()
    {"detect": detect, "lama": lama, "diffuse": diffuse}[args.command](args)


if __name__ == "__main__":
    main()
