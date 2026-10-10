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
| `/search` | One search across every section. Nothing is indexed: each query reads the content as it stands. |
| `/how-to` | The manual. Rendered from [`docs/how-to.md`](docs/how-to.md), so it reads here and on the site. |

`/blog` sorts by most recent or most witnessed, `/logs` by most recent or most viewed, and both filter by keyword —
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

**Use `./redeploy.sh`.** Not `mix phx.server`, not a bare `mix release`.

The live site is a compiled `MIX_ENV=prod` release, run by a systemd user unit behind
Caddy. The script builds the minified, digested assets, keeps the release that is serving,
builds the new one, restarts the service, and then will not call itself successful until it
has checked what has gone wrong silently before: that the homepage answers, that `/dev/*`
is closed, that the stylesheet being served byte-matches the one on disk, that every
colocated hook made it into the bundle, and that a page which needs the database shows
real data.

Three things worth knowing:

1. **Assets are built before the release**, because a release packages `priv/` into
   itself. Built afterwards, they change the checkout and not the thing being served.
2. **`config/runtime.exs` is evaluated at boot**, so a changed value in `.env` or in the
   unit takes only a restart. The file itself is packed into the release, so editing it,
   like anything in `lib/` or `config/`, takes a deploy.
3. **Content needs no deploy.** Posts, the fitness vault and the negatives are read from
   disk on each request.

**If a deploy goes wrong, `./rollback.sh`.** It swaps the release that was serving before
the deploy back in and restarts, which takes seconds and compiles nothing. Run it again
and the newer release is back. It does not touch the checkout and it does not undo a
database migration; the script's header says what that means.

## Architecture

**New here? Read [`docs/how-to.md`](docs/how-to.md)** — the same file the site serves at
[/how-to](https://streetscissors.com/how-to). It explains the whole thing in parts. The
first four assume nothing: what the project is for, how a roll of film becomes a page, how
a markdown file becomes a post. The rest is for someone who programs and wants to know how
the site is run: the path a request takes, the processes and what each is for,
configuration, the deploy step by step, backups and how to restore from them, what the
machine checks about itself, and what to look at first when something breaks.

`CLAUDE.md` is the map — the non-obvious wiring, the design system, the file-based content
systems and their gotchas. `AGENTS.md` covers Phoenix/LiveView conventions.
[`ops/systemd/`](ops/systemd) holds the two unit files that run the live site.

Worth knowing up front: the design is hand-written CSS only. Tailwind runs with
`source(none)`, so no utility classes generate and heroicons must be safelisted in
`assets/css/app.css`.

## Licence

Split, deliberately.

- **The software is MIT** — `lib/`, `assets/`, `config/`, `test/`, `priv/repo/`, `docs/`,
  `mix.exs` and the root scripts. Take it, learn from it, build on it.
- **The content is all rights reserved, and is not in this repository** — the posts, the
  photographs, the recordings and the training notes stay on the machine that serves them
  (`content/` and `priv/static/images/` are ignored by git). A clone builds, boots and
  passes its tests without them.

Full terms in [`LICENSE`](LICENSE).
