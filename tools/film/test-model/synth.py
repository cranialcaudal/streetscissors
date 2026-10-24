#!/usr/bin/env python3
"""The colour pipeline's known-answer test model: film and scanner run forward.

A scene of patches with known linear light is exposed onto a film whose every
number is chosen here, and the film is "scanned" by a model of a white-light
flatbed (the Epson V550's kind). Every inversion stage of the pipeline
(film-develop's density maths, LightCraft's `film.invert`, the paper LUTs) is
tested by getting this file's numbers back out of the TIFF it writes, within
the tolerances in docs/colour/contracts.md.

The model, per pixel, in this order:

    E   = S @ scene                    exposure through the layers' sensitivity
                                       (S: 3x3, rows R G B; crosstalk off-diagonal)
    H   = log10(E) + log10(exposure)   log exposure
    d_c = gamma_c * (H_c - H0_c) + toe the dye each layer forms (shoulderless,
                                       with an optional soft toe). H0 and the
                                       toe may be one number or one a layer: an
                                       aged film's layers lose speed unequally
    D   = Dmin + A @ d                 density the scanner's channels read: the
                                       base (orange mask) plus the dyes, each
                                       seen a little by the other channels (A)
    T   = 10^-D                        transmittance
    T'  = T + flare * mean(T)          scanner flare (veiling light)
    v   = T'^(1/scanner_gamma)         the scanner's encoding (1.0 is linear)
    out = round(65535 * v + noise)     16 bits a channel

A strip is frames of patches with 2 mm gaps of clear film (D = Dmin) between
them and a little bare glass (T = 1) at each end, as the scanner studio's
strips are. Everything is deterministic for a given seed.

Usage:
    synth.py roll OUT_DIR [--process c41|bw|e6] [--frames N] [--seed S]
        writes strip-01.tiff and truth.json (every number above, the patches'
        scene values and where each patch lies in the TIFF)

This file is ours (MIT, with the site). It depends on numpy only, and writes
its TIFFs itself so that nothing else is needed to read the result back.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path

import numpy as np

STUDIO_MARK = "streetscissors scanner studio"

# Linear-light sRGB of the ColorChecker Classic's 24 patches (D65), from the
# published sRGB values of BabelColor's 2012 average, linearised. Used only as
# a varied, realistic set of scene colours; nothing is calibrated against it.
CHECKER_SRGB8 = [
    (115, 82, 68), (194, 150, 130), (98, 122, 157), (87, 108, 67),
    (133, 128, 177), (103, 189, 170), (214, 126, 44), (80, 91, 166),
    (193, 90, 99), (94, 60, 108), (157, 188, 64), (224, 163, 46),
    (56, 61, 150), (70, 148, 73), (175, 54, 60), (231, 199, 31),
    (187, 86, 149), (8, 133, 161), (243, 243, 242), (200, 200, 200),
    (160, 160, 160), (122, 122, 121), (85, 85, 85), (52, 52, 52),
]


def srgb_to_linear(c: np.ndarray) -> np.ndarray:
    c = np.asarray(c, dtype=np.float64) / 255.0
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


@dataclass
class Film:
    """A film's numbers. Defaults are a plausible C-41 negative."""

    process: str = "c41"
    dmin: list[float] = field(default_factory=lambda: [0.25, 0.60, 0.85])
    gamma: list[float] = field(default_factory=lambda: [0.55, 0.60, 0.65])
    h0: float | list[float] = -2.2
    toe: float | list[float] = 0.0
    sensitivity: list[list[float]] = field(
        default_factory=lambda: [[0.92, 0.07, 0.01], [0.06, 0.88, 0.06], [0.01, 0.10, 0.89]]
    )
    crosstalk: list[list[float]] = field(
        default_factory=lambda: [[1.00, 0.08, 0.02], [0.10, 1.00, 0.12], [0.03, 0.25, 1.00]]
    )

    @staticmethod
    def for_process(process: str) -> "Film":
        if process == "c41":
            return Film()
        if process == "bw":
            ident = [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]
            third = [[1 / 3] * 3] * 3
            return Film("bw", [0.30] * 3, [0.62] * 3, -2.2, 0.0, third, ident)
        if process == "e6":
            # A slide is a positive: density falls as exposure rises.
            return Film(
                "e6", [0.15, 0.15, 0.20], [-1.6, -1.6, -1.6], -0.6, 0.0,
                [[0.95, 0.05, 0.0], [0.04, 0.92, 0.04], [0.0, 0.06, 0.94]],
                [[1.00, 0.06, 0.02], [0.08, 1.00, 0.10], [0.02, 0.15, 1.00]],
            )
        raise ValueError(f"unknown process {process!r}")

    def aged(self) -> "Film":
        """The same film kept warm for years: its blue-sensitive layer, the
        top one, has lost most of a stop and gained a soft toe, so the
        yellow dye starts late and then catches up. The layers no longer
        build density in proportion, which no single power per channel
        undoes. (Which layer goes first varies by film and keeping; the top
        layer is the usual one, but this is a test case, not a claim.)"""
        h0 = np.broadcast_to(np.asarray(self.h0, dtype=np.float64), (3,)).tolist()
        h0[2] += 0.6
        return Film(self.process, list(self.dmin), list(self.gamma), h0, [0.0, 0.0, 0.25],
                    [list(r) for r in self.sensitivity], [list(r) for r in self.crosstalk])


@dataclass
class Scanner:
    gamma: float = 1.8
    flare: float = 0.004
    noise: float = 2.0  # standard deviation, in 16-bit steps
    dpi: int = 300


@dataclass
class Layout:
    patch_px: int = 12
    cols: int = 6
    rows: int = 4
    gap_px: int = 24  # 2 mm at 300 dpi
    glass_px: int = 30
    margin_px: int = 6  # clear film above and below the frames


def dye(film: Film, scene: np.ndarray, exposure: float) -> np.ndarray:
    """The dye amounts each layer forms, (..., 3)."""
    s = np.asarray(film.sensitivity)
    e = np.einsum("ij,...j->...i", s, scene)
    h = np.log10(np.maximum(e, 1e-6)) + np.log10(exposure)
    g = np.asarray(film.gamma)
    d = g * (h - np.asarray(film.h0))
    toe = np.broadcast_to(np.asarray(film.toe, dtype=np.float64), g.shape)
    if (toe > 0).any():
        soft = np.maximum(toe, 1e-9)
        d = np.where(toe > 0, soft * np.logaddexp(0.0, d / soft), d)
    if film.process == "e6":
        # A slide's dye is full where unexposed and clears with exposure; the
        # curve is clipped to its maximum density.
        return np.clip(d + 3.0, 0.0, 3.0)
    return np.maximum(d, 0.0)


def density(film: Film, d: np.ndarray) -> np.ndarray:
    a = np.asarray(film.crosstalk)
    return np.asarray(film.dmin) + np.einsum("ij,...j->...i", a, d)


def scan(scanner: Scanner, dens: np.ndarray, rng: np.random.Generator):
    """The 16-bit scan, and the mean transmittance its flare was taken from."""
    t = 10.0 ** (-dens)
    mean_t = t.mean(axis=(0, 1))
    t = t + scanner.flare * mean_t
    v = np.clip(t, 0.0, 1.0) ** (1.0 / scanner.gamma)
    out = 65535.0 * v + rng.normal(0.0, scanner.noise, v.shape)
    return np.clip(np.rint(out), 0, 65535).astype(np.uint16), mean_t


def frame_scene(layout: Layout, frame: int) -> tuple[np.ndarray, list[list[float]]]:
    """A frame's patches: the checker, rolled by frame so frames differ."""
    lin = srgb_to_linear(np.array(CHECKER_SRGB8))
    order = np.roll(np.arange(24), frame * 5)
    patches = lin[order][: layout.cols * layout.rows]
    p = layout.patch_px
    img = np.zeros((layout.rows * p, layout.cols * p, 3))
    for i, rgb in enumerate(patches):
        r, c = divmod(i, layout.cols)
        img[r * p:(r + 1) * p, c * p:(c + 1) * p] = rgb
    return img, patches.tolist()


def strip(film: Film, scanner: Scanner, layout: Layout, frames: int, seed: int,
          exposures: list[float] | None = None):
    """The strip's 16-bit image and everything known about it."""
    rng = np.random.default_rng(seed)
    exposures = exposures or [2.0 ** ((i % 3) - 1) for i in range(frames)]
    p = layout.patch_px
    fh, fw = layout.rows * p, layout.cols * p
    h = fh + 2 * layout.margin_px
    w = 2 * layout.glass_px + frames * fw + (frames + 1) * layout.gap_px

    dens = np.tile(np.asarray(film.dmin, dtype=np.float64), (h, w, 1))
    dens[:, : layout.glass_px] = 0.0
    dens[:, w - layout.glass_px:] = 0.0

    truth_frames = []
    x = layout.glass_px + layout.gap_px
    for i in range(frames):
        scene, patches = frame_scene(layout, i)
        d = dye(film, scene, exposures[i])
        dens[layout.margin_px:layout.margin_px + fh, x:x + fw] = density(film, d)
        rects = []
        for k in range(len(patches)):
            r, c = divmod(k, layout.cols)
            rects.append([x + c * p, layout.margin_px + r * p, p, p])
        truth_frames.append({
            "frame": i + 1,
            "rect": [x, layout.margin_px, fw, fh],
            "exposure": exposures[i],
            "patches": [
                {"scene": patches[k], "rect": rects[k],
                 "density": density(film, dye(film, np.array(patches[k]), exposures[i])).tolist()}
                for k in range(len(patches))
            ],
        })
        x += fw + layout.gap_px

    image, mean_t = scan(scanner, dens, rng)
    truth = {
        "model": "streetscissors synth 1",
        "seed": seed,
        "film": asdict(film),
        "scanner": asdict(scanner),
        "layout": asdict(layout),
        "flare_mean_t": mean_t.tolist(),
        "glass": [[0, 0, layout.glass_px, h], [w - layout.glass_px, 0, layout.glass_px, h]],
        "frames": truth_frames,
    }
    return image, truth


# ── Reading back: the reference inversion the oracle tests itself with ──────

def reference_density(values: np.ndarray, scanner: Scanner, flare_mean_t: np.ndarray) -> np.ndarray:
    """Exact inverse of `scan` (without the noise): 16-bit values to density."""
    v = values.astype(np.float64) / 65535.0
    t = np.maximum(v, 1e-9) ** scanner.gamma - scanner.flare * flare_mean_t
    return -np.log10(np.maximum(t, 1e-9))


# ── TIFF: baseline, uncompressed, RGB, 16 bits a channel ───────────────────

def write_tiff(path: Path, image: np.ndarray, description: str, dpi: int = 300) -> None:
    h, w, spp = image.shape
    assert image.dtype == np.uint16 and spp == 3
    pixels = image.astype("<u2").tobytes()
    desc = description.encode("ascii") + b"\0"

    entries = []  # (tag, type, count, value-or-offset bytes)
    extra = bytearray()
    header = 8
    n_tags = 13
    ifd_size = 2 + n_tags * 12 + 4
    base = header + ifd_size

    def put(data: bytes) -> int:
        off = base + len(extra)
        extra.extend(data)
        if len(extra) % 2:
            extra.append(0)
        return off

    bps = put(struct.pack("<3H", 16, 16, 16))
    desc_off = put(desc)
    res = put(struct.pack("<2I", dpi, 1))
    pix_off = base + len(extra)

    SHORT, LONG, ASCII, RATIONAL = 3, 4, 2, 5
    entries = [
        (256, LONG, 1, w), (257, LONG, 1, h), (258, SHORT, 3, bps),
        (259, SHORT, 1, 1), (262, SHORT, 1, 2), (270, ASCII, len(desc), desc_off),
        (273, LONG, 1, pix_off), (277, SHORT, 1, 3), (278, LONG, 1, h),
        (279, LONG, 1, len(pixels)), (282, RATIONAL, 1, res), (283, RATIONAL, 1, res),
        (284, SHORT, 1, 1),
    ]
    assert len(entries) == n_tags
    ifd = bytearray(struct.pack("<H", n_tags))
    for tag, typ, count, value in sorted(entries):
        if typ == SHORT and count == 1:
            ifd += struct.pack("<HHIHH", tag, typ, count, value, 0)
        else:
            ifd += struct.pack("<HHII", tag, typ, count, value)
    ifd += struct.pack("<I", 0)
    with open(path, "wb") as f:
        f.write(b"II*\0" + struct.pack("<I", header))
        f.write(ifd)
        f.write(extra)
        f.write(pixels)


def read_tiff(path: Path) -> tuple[np.ndarray, str]:
    """Reads back what `write_tiff` writes (and no other kind of TIFF)."""
    data = Path(path).read_bytes()
    assert data[:4] == b"II*\0", "not a little-endian TIFF"
    (ifd,) = struct.unpack_from("<I", data, 4)
    (n,) = struct.unpack_from("<H", data, ifd)
    tags = {}
    for i in range(n):
        tag, typ, count, value = struct.unpack_from("<HHII", data, ifd + 2 + 12 * i)
        if typ == 3 and count == 1:
            value &= 0xFFFF
        tags[tag] = (typ, count, value)
    w, h = tags[256][2], tags[257][2]
    off, length = tags[273][2], tags[279][2]
    _, dcount, doff = tags[270]
    desc = data[doff:doff + dcount].rstrip(b"\0").decode("ascii")
    img = np.frombuffer(data[off:off + length], dtype="<u2").reshape(h, w, 3)
    return img.copy(), desc


def write_roll(out: Path, process: str, frames: int, seed: int) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    film, scanner, layout = Film.for_process(process), Scanner(), Layout()
    image, truth = strip(film, scanner, layout, frames, seed)
    write_tiff(out / "strip-01.tiff", image, f"{STUDIO_MARK}; synth {process} seed {seed}")
    truth["file"] = "strip-01.tiff"
    (out / "truth.json").write_text(json.dumps(truth, indent=1) + "\n")
    return truth


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("roll")
    r.add_argument("out", type=Path)
    r.add_argument("--process", default="c41", choices=["c41", "bw", "e6"])
    r.add_argument("--frames", type=int, default=3)
    r.add_argument("--seed", type=int, default=1)
    a = ap.parse_args(argv)
    if a.cmd == "roll":
        write_roll(a.out, a.process, a.frames, a.seed)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
