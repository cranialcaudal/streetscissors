"""film-develop against the known-answer model: does it find the frames the
model laid down, read the film base the model set, and print the patches in
the order the scene had them?

The rolls here are synth's strips at the size of real 35mm film (a 36 mm
frame at 300 dpi), not write_roll's default 6 mm frames: film-develop works in
millimetres of film, and on a strip that small its 38 mm grid has nothing to
find and the glass's edge outweighs the film base.

film-develop calls ImageMagick 7's `magick`. Where only ImageMagick 6 is
installed (Ubuntu, Debian), its `convert` takes the same arguments for
everything film-develop asks, so a `magick` that runs it is put on the PATH.
"""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

import numpy as np
import pytest

import synth

FILM_DEVELOP = Path(__file__).resolve().parent.parent / "bin" / "film-develop"
MODES = {"c41": "color", "bw": "bw", "e6": "slide"}
FRAMES = 4
# a 426 px frame and a 24 px gap: 38.1 mm apart at 300 dpi
LAYOUT = synth.Layout(patch_px=71)
# film-develop reads a scan value v over the glass's 255 as 1.8 * log10(255 / v)
SCAN_GAMMA = 1.8


@pytest.fixture(scope="session")
def env(tmp_path_factory):
    env = dict(os.environ)
    if shutil.which("magick"):
        return env
    convert = shutil.which("convert")
    if not convert:
        pytest.skip("no ImageMagick (film-develop needs magick, or IM6's convert)")
    shim = tmp_path_factory.mktemp("shim")
    (shim / "magick").write_text(f'#!/bin/sh\nexec "{convert}" "$@"\n')
    (shim / "magick").chmod(0o755)
    env["PATH"] = f"{shim}{os.pathsep}{env.get('PATH', '')}"
    return env


def film_develop(env, *args):
    r = subprocess.run([sys.executable, str(FILM_DEVELOP), *map(str, args)],
                       capture_output=True, text=True, env=env, timeout=300)
    assert r.returncode == 0, r.stdout + r.stderr
    return r.stdout


@pytest.fixture(scope="module", params=list(MODES))
def roll(request, tmp_path_factory, env):
    """A 35mm strip of four frames, analysed. The folder is named as the
    archive names rolls: number, format."""
    process = request.param
    out = tmp_path_factory.mktemp(process) / f"roll001_35mm_{process}"
    out.mkdir()
    film, scanner = synth.Film.for_process(process), synth.Scanner()
    image, truth = synth.strip(film, scanner, LAYOUT, FRAMES, seed=7)
    synth.write_tiff(out / "strip-01.tiff", image, f"{synth.STUDIO_MARK}; synth {process} seed 7")
    (out / "truth.json").write_text(json.dumps(truth, indent=1) + "\n")
    film_develop(env, "analyze", out, "--mode", MODES[process])
    doc = json.loads((out / "frames.json").read_text())
    return process, out, truth, image, doc


def iou(a, b):
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    w = max(0, min(ax + aw, bx + bw) - max(ax, bx))
    h = max(0, min(ay + ah, by + bh) - max(ay, by))
    return w * h / float(aw * ah + bw * bh - w * h)


def read_png(env, path):
    """(height, width, 3) 8-bit pixels of a print, through ImageMagick."""
    run = lambda *a: subprocess.run(["magick", str(path), *a], capture_output=True,
                                    env=env, check=True).stdout
    w, h = map(int, run("-format", "%w %h", "info:").split())
    return np.frombuffer(run("-depth", "8", "rgb:-"), np.uint8).reshape(h, w, 3).astype(float)


def patch_mean(image, rect, origin, inset=8):
    x, y, w, h = rect
    x, y = x - origin[0], y - origin[1]
    return image[y + inset:y + h - inset, x + inset:x + w - inset].reshape(-1, 3).mean(axis=0)


def neutral(scene):
    s = np.asarray(scene)
    return np.ptp(s) <= 0.02 * s.max()


def test_analyze_names_the_film_it_was_given(roll):
    """c41 is asked for as colour, which film-develop also looks at for itself."""
    process, _, _, _, doc = roll
    assert doc["mode"] == MODES[process]
    assert doc["strips"][0]["source"] == "glass"


def test_analyze_finds_every_frame_where_the_model_put_it(roll):
    _, _, truth, _, doc = roll
    frames = doc["strips"][0]["frames"]
    assert [f["frame"] for f in frames] == [f["frame"] for f in truth["frames"]]
    for got, want in zip(frames, truth["frames"]):
        assert iou(got["region"], want["rect"]) > 0.8, (got["region"], want["rect"])


def test_analyze_reads_the_film_base_to_the_density_tolerance(roll):
    """Contract: density recovered from a synth scan, D < 2.5, within 0.02.
    A slide's "base" is its white, not its clear film, so it is not checked."""
    process, _, truth, _, doc = roll
    if process == "e6":
        pytest.skip("a slide's channels carry its white, not the film base")
    bases = [ch["base"] for ch in doc["film"]["channels"]]
    dmin = truth["film"]["dmin"][:len(bases)]
    got = [SCAN_GAMMA * np.log10(255.0 / b) for b in bases]
    np.testing.assert_allclose(got, dmin, atol=0.02)


@pytest.fixture(scope="module")
def developed(roll, env):
    """Frame 2 (exposure 1) cut from the strip as a single, and developed."""
    process, out, truth, image, doc = roll
    frame = truth["frames"][1]
    x, y, w, h = frame["rect"]
    raw = out / "raw-frames" / "frame-02.tiff"
    raw.parent.mkdir()
    synth.write_tiff(raw, np.ascontiguousarray(image[y:y + h, x:x + w]), synth.STUDIO_MARK)
    film_develop(env, "develop", raw, "--roll", out, "--frame", 2)
    return process, out, frame, read_png(env, out / "frames" / "02.png")


def test_develop_prints_the_single_at_its_own_size(developed):
    _, _, frame, png = developed
    assert png.shape == (frame["rect"][3], frame["rect"][2], 3)
    assert 5 < png.mean() < 250


def test_develop_keeps_the_grey_scale_in_order(developed):
    """Brighter grey in the scene, brighter grey in the print, step by step.
    The model's slides are nearly opaque (D 1.9 to 3.7), so all print black."""
    process, _, frame, png = developed
    if process == "e6":
        pytest.skip("synth's e6 frames are too dense to print a grey scale")
    greys = sorted((p for p in frame["patches"] if neutral(p["scene"])),
                   key=lambda p: p["scene"][1])
    assert len(greys) == 6
    lum = [patch_mean(png, p["rect"], frame["rect"]).mean() for p in greys]
    assert all(b > a + 2 for a, b in zip(lum, lum[1:])), lum


def test_develop_keeps_greys_near_neutral(developed):
    """No colour model of the film's crosstalk yet, so not to a ΔE: no
    channel of a grey more than 32 of 255 from another (c41 sits near 22)."""
    process, _, frame, png = developed
    if process == "e6":
        pytest.skip("synth's e6 frames are too dense to print a grey scale")
    for p in frame["patches"]:
        if neutral(p["scene"]):
            rgb = patch_mean(png, p["rect"], frame["rect"])
            assert np.ptp(rgb) <= 32, (p["scene"], rgb)


def test_develop_keeps_the_patches_in_order_of_lightness(developed):
    """No patch a stop or more brighter in the scene (the mean of its light,
    as the film's three layers see it) prints darker. Closer than that, the
    film's crosstalk, which film-develop does not undo, may swap colours."""
    process, _, frame, png = developed
    if process == "e6":
        pytest.skip("synth's e6 frames are too dense to print a grey scale")
    scene = [np.mean(p["scene"]) for p in frame["patches"]]
    lum = [patch_mean(png, p["rect"], frame["rect"]).mean() for p in frame["patches"]]
    swapped = [(a, b) for a, la in zip(scene, lum) for b, lb in zip(scene, lum)
               if b >= 2 * a and lb <= la]
    assert not swapped, swapped


def test_develop_writes_sixteen_bits_when_asked(roll, env, tmp_path):
    process, out, truth, image, _ = roll
    x, y, w, h = truth["frames"][0]["rect"]
    raw = tmp_path / "frame-01.tiff"
    synth.write_tiff(raw, np.ascontiguousarray(image[y:y + h, x:x + w]), synth.STUDIO_MARK)
    film_develop(env, "develop", raw, "--roll", out, "--frame", 1, "--out", tmp_path, "--depth", 16)
    depth = subprocess.run(["magick", str(tmp_path / "01.png"), "-format", "%z", "info:"],
                           capture_output=True, text=True, env=env, check=True).stdout
    assert depth.strip() == "16"


def test_preview_develops_a_frame_off_the_strip(roll, env, tmp_path):
    _, out, _, _, doc = roll
    region = doc["strips"][0]["frames"][2]["region"]
    film_develop(env, "preview", "--roll", out, "--frame", 3, "--out", tmp_path / "p.png",
                 "--max", 200)
    png = read_png(env, tmp_path / "p.png")
    assert max(png.shape[:2]) == 200
    assert png.shape[1] / png.shape[0] == pytest.approx(region[2] / region[3], rel=0.02)


# ── Aged film and thin film ───────────────────────────────────────────────

def load_film_develop():
    """film-develop as a module, for its readings without a scan."""
    import importlib.machinery
    import importlib.util
    loader = importlib.machinery.SourceFileLoader("film_develop", str(FILM_DEVELOP))
    spec = importlib.util.spec_from_loader("film_develop", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


def grey_spread(env, out, truth, image, number):
    """The widest channel spread of any grey patch, single `number` developed."""
    frame = truth["frames"][number - 1]
    x, y, w, h = frame["rect"]
    raw = out / "raw-frames" / f"frame-{number:02d}.tiff"
    raw.parent.mkdir(exist_ok=True)
    synth.write_tiff(raw, np.ascontiguousarray(image[y:y + h, x:x + w]), synth.STUDIO_MARK)
    film_develop(env, "develop", raw, "--roll", out, "--frame", number)
    png = read_png(env, out / "frames" / f"{number:02d}.png")
    return max(np.ptp(patch_mean(png, p["rect"], frame["rect"]))
               for p in frame["patches"] if neutral(p["scene"]))


@pytest.fixture(scope="module", params=[False, True], ids=["as-shot", "crossed"])
def aged(request, tmp_path_factory, env):
    """The c41 film aged (its top layer slow and soft-toed), analysed with
    roll.json saying "crossed": true or saying nothing."""
    out = tmp_path_factory.mktemp("aged") / "roll001_35mm_c41"
    out.mkdir()
    image, truth = synth.strip(synth.Film.for_process("c41").aged(), synth.Scanner(), LAYOUT,
                               FRAMES, seed=7)
    synth.write_tiff(out / "strip-01.tiff", image, f"{synth.STUDIO_MARK}; synth aged seed 7")
    if request.param:
        (out / "roll.json").write_text(json.dumps({"crossed": True}))
    film_develop(env, "analyze", out, "--mode", "color")
    doc = json.loads((out / "frames.json").read_text())
    return request.param, out, truth, image, doc


def test_a_curve_only_where_roll_json_says_crossed(aged):
    crossed, _, _, _, doc = aged
    curved = [bool(ch.get("curve")) for ch in doc["film"]["channels"]]
    assert any(curved) == crossed, curved
    assert not curved[1], "green is what the others are read against"


def test_a_crossed_roll_prints_its_greys_as_fresh_film_does(aged, env):
    """Frame 3 (a stop over) of the aged film: as shot, a grey's channels part
    by 46 of 255, yellow shadows and blue highlights; the fresh film's part by
    about 26. With its curves the aged film comes back within the same 32."""
    crossed, out, truth, image, _ = aged
    spread = grey_spread(env, out, truth, image, 3)
    if crossed:
        assert spread <= 32, spread
    else:
        assert spread > 32, f"the aged film should be crossed as shot: {spread}"


def roll_reading(fd, values, kept=10000):
    """film_model's black-and-white reading of a roll whose pictures are
    `values` (a {scan value: share} dict) and whose clear film reads 200."""
    hist = [0] * 256
    for v, share in values.items():
        hist[v] += int(kept * share)
    strip = [0] * 256
    strip[200] = kept
    return fd.film_model("bw", [([hist] * 3, hist, kept, 1.0)],
                         [([strip] * 3, strip, kept, 1.0)])


def test_a_thin_roll_is_named_and_its_contrast_held():
    """Half the picture on bare film: the middle asks for the most contrast
    there is, and gets THIN_POWER_MOST."""
    fd = load_film_develop()
    film = roll_reading(fd, {199: 0.5, 190: 0.2, 170: 0.2, 120: 0.1})
    assert film["development"]["found"] == ["thin"]
    assert film["contrast"] == fd.THIN_POWER_MOST
    assert film["development"]["held"] > fd.THIN_POWER_MOST


def test_a_flat_roll_is_named_and_left_its_contrast():
    """Little on bare film and nothing dense: flat, and the contrast is what
    the middle asks for."""
    fd = load_film_develop()
    film = roll_reading(fd, {180: 0.3, 150: 0.4, 120: 0.3})
    assert film["development"]["found"] == ["flat"]
    assert "held" not in film["development"]


def test_a_sound_roll_is_named_nothing():
    fd = load_film_develop()
    film = roll_reading(fd, {170: 0.3, 90: 0.4, 20: 0.3})
    assert film["development"]["found"] == []
