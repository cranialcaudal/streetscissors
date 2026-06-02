# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Street Scissors** is a single-author personal website + CMS on Phoenix 1.8 / LiveView 1.1
(Elixir ~> 1.15), backed by **SQLite** (`ecto_sqlite3`). The OTP app is `:web`; the web layer namespace
is `WebWeb`. `AGENTS.md` is the Phoenix 1.8 coding-conventions / usage-rules reference (Elixir, LiveView,
HEEx, Ecto idioms) — consult it for *how to write* code; this file covers *how this app is wired*.

## Commands

```bash
mix setup                       # deps.get + ecto.setup (create/migrate/seed) + assets.setup + build
mix phx.server                  # dev server at localhost:4000
iex -S mix phx.server           # dev server with IEx

mix test                        # ecto.create --quiet + ecto.migrate --quiet, then the suite
mix test test/web/general_test.exs            # single file
mix test test/web/general_test.exs:42         # single test by line number
mix test --failed                             # rerun last failures

mix format
mix precommit                   # compile --warnings-as-errors + deps.unlock --unused + format + test
mix ecto.migrate / mix ecto.reset
mix ecto.gen.migration name_in_snake_case     # always generate migrations this way

mix assets.build                # tailwind + esbuild (dev)
mix assets.deploy               # minified assets + phx.digest (production)
```

**Run `mix precommit` before considering any change done** — it is the project gate
(warnings-as-errors compile, unused-dep check, format, full test run).

## Architecture — the non-obvious parts

Standard Phoenix layering: contexts + Ecto schemas in `lib/web/<context>/`; controllers, LiveViews,
components, plugs in `lib/web_web/`. The pieces that take reading several files to understand:

- **Admin auth is per-LiveView, not a router pipeline.** There is no `:require_admin` pipeline or
  `on_mount` hook. Login (`AdminSessionController`) checks a single password via
  `Plug.Crypto.secure_compare` against `Application.get_env(:web, :admin_password)` and sets
  `session["admin_user"] = true`. Each admin LiveView must guard **itself** in `mount/3`
  (`if session["admin_user"] do ... else push_navigate(to: "/")`). The `SetCurrentUser` plug only
  exposes `@admin_mode` to templates — **it does not protect routes.** When adding an admin route under
  `live_session :admin`, you must replicate the `mount/3` session check or it will be public.

- **Two parallel content systems:**
  - **DB-backed blog posts** (`blog_posts` table), authored in the admin Content Manager.
  - **File-based manuscripts** read from disk by `Web.Manuscripts` (Markdown → HTML via Earmark).
    The base path is **hard-coded** to `/home/cesar/Documents/Obsidian Vault/manuscripts` and the
    category list is hard-coded (`fiction`, `reflections`, `sensus`, `physical`, `faith`). Audio is
    served through `ManuscriptController` / `media_serve` plug with a `Path.safe_relative`
    directory-traversal guard. **This path must exist on any host or the manuscripts section breaks.**

- **Every browser request runs the plug chain** `Analytics` → `SetCurrentUser` → `FetchStats` →
  `LoadSiteSettings` (see `router.ex` `:browser` pipeline). So analytics hit-logging and site-settings
  loading happen on all HTML routes; `Analytics` and the guestbook persist client IP addresses.
  Site settings are key/value rows (`SiteSettings.get_setting/2`) read on every request.

- **Supervision tree** (`lib/web/application.ex`): Repo, an `Ecto.Migrator` that auto-runs migrations
  **only in releases** (`RELEASE_NAME` set), PubSub, `Finch` (named `Swoosh.Finch`, for email over HTTP
  e.g. Resend), a `Task.Supervisor`, and `Web.Scheduler` (**Quantum** cron jobs). **Oban caveat:** it is
  configured (`config/config.exs`) and `workers/newsletter_sender.ex` is an `Oban.Worker`, but `{Oban, …}`
  is **not** in the supervision tree — so jobs enqueued via `Oban.insert/1` are persisted yet never
  executed. Adding `Oban` to `application.ex` children is required to actually process them.

- **Feature areas** beyond the blog/manuscripts: fitness tracker (`Web.Fitness` — exercises, logs,
  workout sessions/sets, biometrics, CSV export), newsletter + subscribers (`Web.Newsletter`,
  `workers/newsletter_sender.ex`, generator), audio "captain's log" (`Web.Audio`, recorder/player JS),
  guestbook, contact messages, analytics, a `/pc` terminal LiveView, RSS feed + sitemap controllers,
  and a custom captcha (`lib/web_web/captcha.ex`, not reCAPTCHA).

- **Frontend**: Tailwind v4 + DaisyUI, esbuild bundling `assets/js/` (only `app.js`/`app.css` are
  served — vendor deps must be imported into them, never referenced as external `<script>`/`<link>`).
  Many feature-specific JS/CSS files (`audio_recorder.js`, `pc_terminal.js`, `markdown_editor.js`, etc).

## Deployment

Containerized (`Dockerfile`, `docker-compose.yml`); `deploy.sh` / `start_prod.sh` drive releases
(`rel/`); **Caddy** is the reverse proxy (`Caddyfile`, `Caddyfile.prod`). Production secrets/config
resolve at runtime in `config/runtime.exs` (`:admin_password`, mailer, etc. come from env there).
SQLite DB files live in the repo root (`web_dev.db`, `web_test.db`, `street_scissors_prod.db`);
migrations auto-run on release boot via the supervised `Ecto.Migrator`.
