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

## Where to start

**New to the project?** These, in order:

1. [`docs/setup.md`](docs/setup.md): install what it needs and run it on your own machine, step by
   step. No Elixir knowledge assumed.
2. [`docs/how-to.md`](docs/how-to.md): what every part of the site is for and how it works, in plain
   language (also at [/how-to](https://streetscissors.com/how-to)).
3. The README in each folder, which says what the folder holds and where to begin in it:

| Folder | What it holds |
|---|---|
| [`lib/`](lib/README.md) | The site's code: [`lib/web/`](lib/web/README.md) is what it knows and does, [`lib/web_web/`](lib/web_web/README.md) is the web pages and every address |
| [`assets/`](assets/README.md) | Stylesheets and browser code |
| [`config/`](config/README.md) | Settings for development, tests and production |
| [`priv/`](priv/README.md) | Files the site reads that are not code: migrations, the Bible, calendars, static files |
| [`test/`](test/README.md) | The automated checks, and the invented sample content they use |
| [`tools/`](tools/README.md) | Programs the site calls: the film darkroom's tools, the photo editor's engine, the repair models |
| [`analysis/`](analysis/README.md) | Statistics in R: the emissions charts and the training report |
| [`ops/`](ops/README.md) | Running the live site: the deploy, the rollback, the services, the web server |
| [`docs/`](docs/README.md) | The manual, the setup guide, the roadmap, and the technical notes |

[`CLAUDE.md`](CLAUDE.md) is the short list of rules and traps for anyone changing the code (it
is written for AI coding agents, and it is just as useful for people).

## Running it locally

```bash
mix setup          # libraries, database, assets
mix test           # the full suite: about 1,600 tests, all passing
mix phx.server     # http://localhost:4000 (admin password: dev-admin)
```

A development server needs no `.env`; that file is for production. [`docs/setup.md`](docs/setup.md)
§4 shows how to fill the pages with the tests' sample content, and how to try the optional
integrations (Komoot, mail).

```bash
mix precommit      # the gate before any change is done: warnings-as-errors, format, full suite
```

## Deploying

**Use `ops/redeploy.sh`.** Not `mix phx.server`, not a bare `mix release`.

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

**If a deploy goes wrong, `ops/rollback.sh`.** It swaps the release that was serving before
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

Every document is listed, with what it is for, in [`docs/README.md`](docs/README.md).

Worth knowing up front: the design is hand-written CSS only. Tailwind runs with
`source(none)`, so no utility classes generate and heroicons must be safelisted in
`assets/css/app.css`.

## Licence

Split, deliberately.

- **The software is MIT** — `lib/`, `assets/`, `config/`, `test/`, `priv/repo/`, `docs/`,
  `mix.exs`, `ops/`, `tools/` and `analysis/`. Take it, learn from it, build on it.
- **The content is all rights reserved, and is not in this repository** — the posts, the
  photographs, the recordings and the training notes stay on the machine that serves them
  (`content/` and `priv/static/images/` are ignored by git). A clone builds, boots and
  passes its tests without them.

Full terms in [`LICENSE`](LICENSE).
