# tools/lightcraft/

**LightCraft** is an open-source photo editor's engine, the kind of thing behind Lightroom's
sliders: exposure, contrast, white balance, crop, straightening, dust removal. The site's print
editor (`/admin/darkroom`) uses it in two ways:

- **While you edit**, the site keeps one `lightcraft-cli` running per open editor and asks it for
  a new preview each time you move a slider (`Web.Darkroom.Session`). Each preview comes back in
  about a twentieth of a second.
- **When you save**, it runs `lightcraft-cli` once more on the full-size picture to make the
  finished print (`Web.Darkroom`).

Both use the same program with the same commands, so the preview and the print can never
disagree. That is the reason a single engine was chosen over writing every adjustment twice
(once for the browser, once for the server).

## Installing it

```bash
tools/lightcraft/install.sh      # or: tools/install.sh --lightcraft
lightcraft-cli --version         # check: prints "lightcraft-cli 0.8.0" or newer
```

What the script does, in order:

1. Downloads LightCraft's source code into `~/.cache/lightcraft` (only the first time; later
   runs just fetch what changed). It uses the site's own copy of the project
   (`cranialcaudal/lightcraft`) and falls back to the original (`storytold/lightcraft`).
2. Switches to one exact version (`LIGHTCRAFT_REF`, a commit id written at the top of the
   script). **The colour figures in `lib/web/darkroom/film.ex` were measured against that
   version**, so the version is pinned; change it only together with those figures, and run
   `mix test test/web/darkroom_film_test.exs` against the new build.
3. Compiles it with Rust's `cargo` (several minutes the first time).
4. Copies the finished program to `~/.local/bin/lightcraft-cli`. It is written under a
   temporary name first and then renamed, so the site never sees half a program.

## What you need first

- **Rust**, installed with [rustup](https://rustup.rs): `curl https://sh.rustup.rs -sSf | sh`,
  then open a new terminal so `cargo` is on your `PATH`.
- **git** and a C compiler (Fedora: `sudo dnf install git gcc`; Ubuntu:
  `sudo apt install git build-essential`).

## Settings you can change

All are environment variables, set in front of the command
(`LIGHTCRAFT_REF=abc1234 tools/lightcraft/install.sh`):

| Variable | Default | What it changes |
|---|---|---|
| `LIGHTCRAFT_REF` | the pinned commit | Which version is built |
| `LIGHTCRAFT_REPO` | `cranialcaudal/lightcraft` on GitHub | Where the source comes from |
| `LIGHTCRAFT_SRC` | `~/.cache/lightcraft` | Where the source is kept |
| `LIGHTCRAFT_BIN_DIR` | `~/.local/bin` | Where the program is installed |

## Without it

The rest of the site works normally. The print editor's page opens but cannot draw a picture,
and says why. In the test suite, `test/support/stub_lightcraft` stands in for it, so you do not
need LightCraft to run `mix test`.

## Licence

LightCraft is MIT or Apache-2.0 (your choice), which is compatible with this site's MIT licence.
