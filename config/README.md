# config/

**Settings, separated by where the code is running.** The same code runs in three situations
("environments"), and each needs different settings: a different database, different paths,
real or pretend outside programs.

| File | When it is read | What it sets |
|---|---|---|
| [`config.exs`](config.exs) | Always, first, when the code is **compiled** | Settings shared by all three: the scheduled jobs and their times, Oban's queues, the asset builders, logging |
| [`dev.exs`](dev.exs) | When you run `mix phx.server` on your own machine | The development database (`tmp/db/web_dev.db`), live reloading, the dev admin password (`dev-admin`), and keeping a dev server's backups and webmentions apart from the live site's |
| [`test.exs`](test.exs) | When you run `mix test` | The test database, and **every path pointed at invented sample content** in `test/support/fixtures/`, plus stand-in programs for ffmpeg, LightCraft and the others, so the tests never touch real files or the network |
| [`prod.exs`](prod.exs) | When the live release is **compiled** | Production-only settings fixed at build time, such as secure cookies |
| [`runtime.exs`](runtime.exs) | When the site **starts** (in every environment) | Values from environment variables: secrets, paths, the port. In production it refuses to start if a required one is missing |

## Compile time versus start time

This distinction catches everyone once:

- `config.exs`, `dev.exs`, `test.exs` and `prod.exs` are read **when the code is compiled**. For
  the live site, changing them means building and deploying a new release (`ops/redeploy.sh`).
- `runtime.exs` is read **each time the site starts**. It is copied into the release when it is
  built, so editing the file still needs a deploy, but changing a *value* it reads (in `.env`, or
  in the systemd unit) needs only a restart.

## Where the secrets go

**Never in these files.** Passwords, API keys and private paths come from environment variables,
which `runtime.exs` reads. On the live machine they are in `.env` (not in git) and in the systemd
unit (`ops/systemd/streetscissors.service`). [`.env.example`](../.env.example) lists every one,
with what it does. Each has a neutral fallback where it is optional, so a fresh copy of the code
always starts.

## If you want to change…

- **When a nightly job runs**: `config.exs`, the `Web.Scheduler` jobs list (times are UTC).
- **A path or a secret on the live site**: `.env` or the unit, then restart.
- **Where the tests look for something**: `test.exs`. Point it at a fixture in
  `test/support/fixtures/`, never at real content.
