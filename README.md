# streetscissors

A personal site: written work, spoken work, film photographs, and a training log.
Phoenix 1.8 / LiveView on SQLite. Live at [streetscissors.com](https://streetscissors.com).

## What's here

| Section | What it is |
|---|---|
| `/blog` | Written work. Markdown read off disk at request time, authored in an Obsidian vault. |
| `/logs` | Captain's logs — spoken pieces, each with its own address. |
| `/negatives` | Contact sheets and individual frames, scanned from film. |
| `/fitness` | The training regimen, plus GPS rides synced from Komoot. |
| `/pc` | A terminal that navigates the site by the filenames things actually have on disk. Type `roll007`, press Enter. |

Both `/blog` and `/logs` sort by most recent or most witnessed, and filter by keyword —
keywords normalise through one shared module so `"New York"` and `new-york` are one token.

## Running it locally

```bash
mix setup          # deps, database, assets
mix phx.server     # http://localhost:4000
```

You'll want a `.env` for the optional integrations (Komoot sync, mail, the newsletter
generator) — see `.env.example`. Nothing in it is required to boot locally.

```bash
mix precommit      # the gate: warnings-as-errors, format, full test suite
```

## Deploying

**Use `./redeploy.sh`.** Not `mix phx.server`, not a bare `mix compile`.

The live site runs `mix phx.server` under `MIX_ENV=dev` with `PUBLIC_DEPLOY=true`, which
makes `config/dev.exs` behave as production config: dev routes off, `debug_errors` off,
code reloader off, secure cookies, real `check_origin`, and secrets required from the
environment rather than any committed fallback.

Two traps that script exists to prevent:

1. **Config is compile-time.** Mix does not recompile when only an environment variable
   changes, so `PUBLIC_DEPLOY` has to be set for a forced compile. Get it wrong and
   Phoenix's compile-env validator refuses to boot — correct behaviour, but it crash-loops.
2. **`mix assets.build` compiles the project too**, so running it with a different
   `PUBLIC_DEPLOY` than the compile step is exactly how the build and the runtime end up
   disagreeing.

The service compiles into its own `MIX_BUILD_PATH` so local `mix` runs can't clobber it.
`redeploy.sh` verifies afterwards that `/dev/*` returns 404 and that the served
stylesheet byte-matches disk, and fails loudly if not.

## Architecture

`CLAUDE.md` is the map — the non-obvious wiring, the design system, the file-based content
systems and their gotchas. `AGENTS.md` covers Phoenix/LiveView conventions.

Worth knowing up front: the design is hand-written CSS only. Tailwind runs with
`source(none)`, so no utility classes generate and heroicons must be safelisted in
`assets/css/app.css`.

## Licence

Split, deliberately.

- **The software is MIT** — `lib/`, `assets/`, `config/`, `test/`, `priv/repo/`, `mix.exs`
  and the root scripts. Take it, learn from it, build on it.
- **The content is all rights reserved** — everything under `content/` and
  `priv/static/images/`. The posts, the photographs, the recordings and the training notes
  are here so the site can be built, not licensed for reuse.

Full terms in [`LICENSE`](LICENSE).
