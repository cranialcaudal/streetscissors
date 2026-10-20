# tools/repair/

Sets up what the print editor's **Repair** tab (`/admin/darkroom`) needs to fix damaged scans.

## What Repair does, in plain words

Old negatives and scans have flaws: a coloured line across the picture where the scanner
hiccupped, dust, scratches, a torn corner. Repair fixes them in three ways, gentlest first:

1. **Scanner lines are corrected, not painted over.** A line is usually a row of pixels where
   one colour channel came out too bright or too dark. The program compares the row with the
   rows on either side and adjusts it to match. The real picture underneath is kept.
2. **Small marks are filled in by LaMa**, an AI model trained to fill holes in photographs. You
   paint over a mark in the browser, and LaMa invents what was probably there from what is
   around it.
3. **Large damage gets a suggestion from Stable Diffusion**, a bigger AI model. Because it
   invents freely (it once added a canister to a shelf that never had one), its result is only
   ever a *candidate*: you see it beside the original and choose Keep or Discard.

The program that does all three is [`priv/repair/film_repair.py`](../../priv/repair/film_repair.py).
The site runs it when you press a button (`Web.Darkroom.Repair` in
`lib/web/darkroom/repair.ex`). This folder only installs what that program needs.

## Installing it

```bash
tools/repair/install.sh           # both models (about 4 GB, 10–20 minutes)
tools/repair/install.sh --lama    # only LaMa (about 400 MB); enough for lines and dust
```

Everything goes into `~/.local/share/film-repair/`, which is where the site looks by default.
Read the comment at the top of [`install.sh`](install.sh) for exactly what is downloaded and
from where. Every version is pinned, and the LaMa file is checked against a known checksum.

**You need first:** `python3` with its `venv` module (Fedora `sudo dnf install python3`; Ubuntu
`sudo apt install python3-venv`) and an internet connection. No graphics card: everything runs
on the processor.

## Memory, and why Stable Diffusion runs fenced in

Stable Diffusion needs about 2 GB of memory while it works. On this site's machine, which is
also the web server, an unrestricted first attempt used 5 GB and Linux stopped other programs to
make room. So the site starts it inside a memory fence (`systemd-run --user --scope -p
MemoryMax=3G`); if it ever asks for more, only it is stopped. Only one Stable Diffusion job
runs at a time. On your own machine, `config :web, :sd_memory_max` sets the fence (or `nil` for
none).

## Without it

Everything else works. The Repair tab says which part is missing. The test suite uses
`test/support/stub_film_repair` instead, so `mix test` never needs these models.

## Licences

LaMa (Suvorov et al., the `Carve/LaMa-ONNX` conversion) is Apache-2.0. Stable Diffusion 1.5
inpainting is CreativeML OpenRAIL-M, which permits this use but forbids some others; read it
before using the model for anything else. Neither model is stored in this repository.
