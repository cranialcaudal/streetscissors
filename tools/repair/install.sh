#!/usr/bin/env bash
#
# tools/repair/install.sh — set up the print editor's Repair tab.
#
# WHAT IT IS FOR
#
#   The print editor (/admin/darkroom) can repair a scanned photograph: take out
#   the coloured lines a scanner sometimes leaves, fill in dust and scratches,
#   and (as a suggestion you then keep or throw away) paint over large damage.
#   The work is done by priv/repair/film_repair.py, a Python program the site
#   starts when you press a button (Web.Darkroom.Repair). It needs:
#
#     * LaMa, a model that fills in small marked areas. It runs on onnxruntime,
#       which is light: one environment of numpy, OpenCV and onnxruntime, and
#       one 208 MB model file.
#     * Stable Diffusion 1.5 inpainting, for large damage. It needs PyTorch,
#       which is heavy: a second environment of about 1 GB and 2 GB of model
#       files. It runs on the CPU; no graphics card is needed.
#
#   They are kept in two separate Python environments ("venvs") so the heavy
#   one can be left out or rebuilt without touching the light one.
#
# WHERE THINGS GO
#
#   Everything goes in ~/.local/share/film-repair/, which is where the site
#   looks by default (see lib/web/darkroom/repair.ex):
#
#     venv/              Python for LaMa            (:film_repair_python)
#     lama_fp32.onnx     the LaMa model             (:lama_model)
#     sd-venv/           Python for Stable Diffusion (:sd_python)
#     sd15-inpaint/      the Stable Diffusion model  (:sd_model)
#
#   Nothing here is in git: the models are large and have their own licences
#   (LaMa: Apache-2.0; Stable Diffusion 1.5: CreativeML OpenRAIL-M).
#
# HOW TO RUN IT
#
#   tools/repair/install.sh            both parts
#   tools/repair/install.sh --lama     only the light part (enough for line and dust repair)
#
#   It is safe to run again: a model already downloaded is checked, not
#   fetched again. Allow 10 to 20 minutes and about 4 GB of disk the first time.
#
# WHAT YOU NEED FIRST
#
#   python3 with the venv module (Fedora: sudo dnf install python3;
#   Ubuntu: sudo apt install python3-venv), and an internet connection.
#
# THE VERSIONS
#
#   Pinned to the versions the live site was measured with on 2026-10-20.
#   Newer ones will probably work; if you change them, run a repair on a test
#   print and compare.
#
set -euo pipefail

DEST="${FILM_REPAIR_HOME:-$HOME/.local/share/film-repair}"

LAMA_URL="https://huggingface.co/Carve/LaMa-ONNX/resolve/main/lama_fp32.onnx"
LAMA_SHA256="1faef5301d78db7dda502fe59966957ec4b79dd64e16f03ed96913c7a4eb68d6"

SD_REPO="stable-diffusion-v1-5/stable-diffusion-inpainting"
SD_REVISION="8a4288a76071f7280aedbdb3253bdb9e9d5d84bb"

only_lama=no
[ "${1:-}" = "--lama" ] && only_lama=yes

mkdir -p "$DEST"

# ── Part 1: LaMa ──────────────────────────────────────────────────────────────

echo "==> LaMa: Python environment in $DEST/venv"
if [ ! -x "$DEST/venv/bin/python" ]; then
  python3 -m venv "$DEST/venv"
fi
"$DEST/venv/bin/pip" install --quiet --upgrade pip
"$DEST/venv/bin/pip" install --quiet \
  numpy==2.5.4 \
  opencv-python-headless==5.0.0.93 \
  onnxruntime==1.31.0

echo "==> LaMa: the model ($DEST/lama_fp32.onnx, 208 MB)"
if [ ! -f "$DEST/lama_fp32.onnx" ]; then
  # Download beside the final name and rename only when complete, so a broken
  # download never looks like a model.
  curl --fail --location --progress-bar -o "$DEST/lama_fp32.onnx.part" "$LAMA_URL"
  mv "$DEST/lama_fp32.onnx.part" "$DEST/lama_fp32.onnx"
fi
echo "$LAMA_SHA256  $DEST/lama_fp32.onnx" | sha256sum --check --quiet \
  || { echo "The LaMa file does not match its checksum. Delete it and run this again." >&2; exit 1; }

if [ "$only_lama" = yes ]; then
  echo "Done (LaMa only). Stable Diffusion was skipped."
  exit 0
fi

# ── Part 2: Stable Diffusion ──────────────────────────────────────────────────

echo "==> Stable Diffusion: Python environment in $DEST/sd-venv (about 1 GB)"
if [ ! -x "$DEST/sd-venv/bin/python" ]; then
  python3 -m venv "$DEST/sd-venv"
fi
"$DEST/sd-venv/bin/pip" install --quiet --upgrade pip
# PyTorch's CPU-only build comes from PyTorch's own index; the default one
# would pull in gigabytes of graphics-card libraries this machine never uses.
"$DEST/sd-venv/bin/pip" install --quiet \
  --index-url https://download.pytorch.org/whl/cpu torch==2.14.1
"$DEST/sd-venv/bin/pip" install --quiet \
  numpy==2.5.4 \
  opencv-python-headless==5.0.0.93 \
  diffusers==0.41.0 \
  transformers==5.20.1 \
  accelerate==1.15.0 \
  safetensors==0.8.0 \
  huggingface_hub==1.33.0

echo "==> Stable Diffusion: the model ($DEST/sd15-inpaint, about 2 GB)"
# Only the half-precision weights and the small configuration files are
# fetched. film_repair.py loads exactly these.
"$DEST/sd-venv/bin/python" - "$SD_REPO" "$SD_REVISION" "$DEST/sd15-inpaint" <<'PY'
import sys
from huggingface_hub import snapshot_download

repo, revision, dest = sys.argv[1:4]
snapshot_download(
    repo_id=repo,
    revision=revision,
    local_dir=dest,
    allow_patterns=["*.json", "*.txt", "README.md", "*.fp16.safetensors"],
)
print("model at", dest)
PY

echo
echo "Done. The print editor's Repair tab can now find everything it needs."
