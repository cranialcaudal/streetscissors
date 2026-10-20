# ops/

**Everything for running the live site**, as opposed to developing it. On your own computer you
start the site with `mix phx.server` and never need this folder. On the server, these files are
what keep it up.

| File | What it is | When you use it |
|---|---|---|
| [`redeploy.sh`](redeploy.sh) | **The deploy.** Builds a new release and swaps it in, then checks that it really works before saying so | Every time code changes on the live site |
| [`rollback.sh`](rollback.sh) | **The undo.** Puts back the release that was running before the last deploy, in seconds. Run it twice to go forward again | When a deploy went wrong |
| [`start_prod.sh`](start_prod.sh) | Starts the release by hand in a terminal, with the same settings the service uses, to see its output directly | Rarely; for debugging. It refuses to run while the service is up |
| [`systemd/streetscissors.service`](systemd/streetscissors.service) | The service that runs the site and restarts it if it stops | Installed once (below) |
| [`systemd/caddy-streetscissors.service`](systemd/caddy-streetscissors.service) | The service that runs Caddy, the web server in front of the site | Installed once |
| [`caddy/Caddyfile`](caddy/Caddyfile) | Caddy's settings: the domain names, HTTPS certificates, serving uploaded media straight from disk, blocking AI scrapers, the access log | Edited rarely; `systemctl --user reload caddy-streetscissors` applies a change |

Each file opens with a comment explaining itself; read it before running anything.

## How the pieces fit

```
  the internet ──▶ Caddy (ports 80, 443; HTTPS) ──▶ the site (127.0.0.1:4000 only)
                   caddy-streetscissors.service       streetscissors.service
                   ops/caddy/Caddyfile                 the release in _build/prod/rel/web
```

The site itself listens only on the machine's own address, so the only way in from outside is
through Caddy. Both run as **systemd user services**: they belong to an ordinary user, not to the
system administrator, and start at boot because of `loginctl enable-linger`.

## A deploy

```bash
ops/redeploy.sh
```

In order, it: builds the stylesheet and scripts, sets the running release aside as
`web.previous`, builds the new release, waits until the scanner is not in the middle of a scan
(a restart would cut it off), restarts the service, and then checks that the homepage answers, that development-only pages are closed, that the
stylesheet being served is the one just built, and that a page needing the database shows real
data. If any check fails it says so, and `ops/rollback.sh` puts the previous release back.

**Content needs no deploy.** Posts, the training plan, the manual and the photographs are read
from disk on each request.

## Installing the services on a new machine

The unit files use `%h` (your home folder) and `%u` (your user name), so no personal path is
written into the repository. systemd fills them in.

```bash
cp ops/systemd/*.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable --now caddy-streetscissors streetscissors
loginctl enable-linger "$USER"          # keep them running when nobody is logged in
```

Before that: fill in `.env` (copy `.env.example`), build a first release with
`ops/redeploy.sh`, and point your domain's DNS at the machine. The installed copies in
`~/.config/systemd/user/` and these must be kept the same: a change to one belongs in the
other.

**Never start Caddy any other way** (`sudo caddy start`, or the `caddy` command on its own): a
second Caddy takes the ports and silently breaks the supervised one.

## Where to read more

[`docs/how-to.md`](../docs/how-to.md) Part 6 ("How it is run") explains each service, a deploy
step by step, migrations, logs, certificates, what happens after a reboot, and what to check
first when something is wrong. Part 7 covers backups and restoring them.
