"""The test model tests itself: if its own exact inverse cannot get its
numbers back, no stage tested against it can be trusted."""

import json
import subprocess

import numpy as np
import pytest

import synth


@pytest.fixture(scope="module", params=["c41", "bw", "e6"])
def roll(request, tmp_path_factory):
    out = tmp_path_factory.mktemp(request.param)
    truth = synth.write_roll(out, request.param, frames=3, seed=7)
    image, desc = synth.read_tiff(out / "strip-01.tiff")
    return out, truth, image, desc


def patch_mean(image, rect, inset=2):
    x, y, w, h = rect
    return image[y + inset:y + h - inset, x + inset:x + w - inset].reshape(-1, 3).mean(axis=0)


def test_tiff_round_trips_and_carries_the_studio_mark(roll):
    out, truth, image, desc = roll
    assert image.dtype == np.uint16
    assert desc.startswith(synth.STUDIO_MARK)
    frame = truth["frames"][-1]["rect"]
    assert image.shape[1] >= frame[0] + frame[2]


def test_the_same_seed_gives_the_same_bytes(tmp_path):
    a = synth.write_roll(tmp_path / "a", "c41", 2, 3)
    b = synth.write_roll(tmp_path / "b", "c41", 2, 3)
    assert a["frames"] == b["frames"]
    assert (tmp_path / "a/strip-01.tiff").read_bytes() == (tmp_path / "b/strip-01.tiff").read_bytes()


def test_glass_reads_as_bare_and_gaps_as_the_base(roll):
    _, truth, image, _ = roll
    scanner = synth.Scanner(**truth["scanner"])
    mean_t = np.array(truth["flare_mean_t"])
    x, y, w, h = truth["glass"][0]
    glass = synth.reference_density(image[y:y + h, x:x + w].reshape(-1, 3).mean(0), scanner, mean_t)
    assert np.all(np.abs(glass) < 0.01)

    f = truth["frames"][0]["rect"]
    gap_x = f[0] - truth["layout"]["gap_px"] // 2
    gap = synth.reference_density(image[f[1]:f[1] + f[3], gap_x].mean(0), scanner, mean_t)
    np.testing.assert_allclose(gap, truth["film"]["dmin"], atol=0.01)


def test_the_exact_inverse_recovers_every_patch_density(roll):
    _, truth, image, _ = roll
    scanner = synth.Scanner(**truth["scanner"])
    mean_t = np.array(truth["flare_mean_t"])
    for frame in truth["frames"]:
        for patch in frame["patches"]:
            got = synth.reference_density(patch_mean(image, patch["rect"]), scanner, mean_t)
            # Dense patches sit near the scanner's floor, where noise dominates.
            tol = np.where(np.array(patch["density"]) > 2.5, 0.08, 0.01)
            assert np.all(np.abs(got - patch["density"]) <= tol), (frame["frame"], patch)


def test_undoing_the_film_recovers_the_scene_up_to_exposure():
    """Density → dye (A⁻¹) → log exposure (γ) → scene (S⁻¹), noise-free."""
    film = synth.Film.for_process("c41")
    scene = synth.srgb_to_linear(np.array(synth.CHECKER_SRGB8[:18]))
    d = synth.dye(film, scene, 1.0)
    dens = synth.density(film, d)
    dye_back = np.linalg.solve(np.array(film.crosstalk), (dens - film.dmin).T).T
    h = dye_back / np.array(film.gamma) + film.h0
    e = 10.0 ** h
    back = np.linalg.solve(np.array(film.sensitivity), e.T).T
    np.testing.assert_allclose(back, scene, rtol=1e-6, atol=1e-9)


def test_imagemagick_reads_the_tiff_when_it_is_there(roll, tmp_path):
    out, truth, image, _ = roll
    tool = next((t for t in ("magick", "identify") if subprocess.run(
        ["which", t], capture_output=True).returncode == 0), None)
    if tool is None:
        pytest.skip("no ImageMagick")
    args = [tool, "identify"] if tool == "magick" else [tool]
    info = subprocess.run(args + ["-format", "%w %h %z", str(out / "strip-01.tiff")],
                          capture_output=True, text=True, check=True).stdout.split()
    assert info == [str(image.shape[1]), str(image.shape[0]), "16"]
    json.loads((out / "truth.json").read_text())
