# lib/web/

**The core of the site: what it knows and what it does, with no web pages involved.** In Phoenix
this layer is made of **contexts**: one module per area of the site (`Web.Blog`, `Web.Rides`,
`Web.Scanner`…) that the rest of the code goes through, and a folder of the same name holding its
helpers.

So `Web.Blog` (in `blog.ex`) is the front door for everything about posts, and
`blog/embeds.ex`, `blog/images.ex` and so on are the rooms behind it. When the website needs
something, it calls the front door; it should rarely need to reach into the folder.

## Where things come from

The site keeps its information in three kinds of place, and each context says which it uses:

- **Files on disk, read when a page is asked for.** Blog posts, the training plan and the
  exercise wiki are markdown files in `content/` (an [Obsidian](https://obsidian.md) vault). The
  photographs are the negatives archive (`NEGATIVES_PATH`). Nothing is copied into the database,
  so editing a file changes the page at once.
- **The database** (SQLite, one file). Things the site itself records: recordings, rides, page
  visits, guestbook signatures, letters, the training log. Its tables are defined by the
  `schema` modules in these folders and built by the migrations in `priv/repo/migrations/`.
- **Other programs and services.** ffmpeg, ImageMagick, the film tools, LightCraft, Komoot's API,
  the scanner. See [`tools/README.md`](../../tools/README.md).

## Every context, by area

### Writing

| Module | File / folder | What it does |
|---|---|---|
| `Web.Blog` | `blog.ex`, `blog/` | Posts: markdown files in `content/blog/`, read at request time. Drafts, the editor's safe saving, photo and ride embeds (`blog/embeds.ex`), the image library |
| `Web.Keywords` | `keywords.ex`, `keywords/` | The one keyword vocabulary shared by posts and logs, so "New York" and `new-york` are the same word. Renaming one everywhere (`keywords/index.ex`) |
| `Web.ContentHealth` | `content_health.ex` | Finds broken links, missing images and other faults in the writing, by asking the site itself |
| `Web.Docs` | `docs.ex` | Renders a long markdown document as a page with a contents list (the manual, the roadmap) |

### Recordings and the cutting room

| Module | File / folder | What it does |
|---|---|---|
| `Web.Audio` | `audio.ex`, `audio/` | The captain's logs: recordings (video or audio), each titled by the day it was made |
| `Web.Media` | `media.ex`, `media/` | Converting a recording into one file browsers can play (`media/transcoder.ex` runs ffmpeg one job at a time; `media/ffmpeg.ex` builds every ffmpeg command) |
| `Web.Uploads` | `uploads.ex` | Where uploaded files live on disk |
| `Web.Cuts` | `cuts.ex`, `cuts/` | The cutting room: a log edited from several takes, photographs, titles and music, rendered by one ffmpeg command (`cuts/render.ex`) |

### Photographs

| Module | File / folder | What it does |
|---|---|---|
| `Web.Negatives` | `negatives.ex`, `negatives/` | The negatives archive: rolls, contact sheets, single frames, web-sized copies. `negatives/sheet_layout.ex` works out where each frame sits on a contact sheet so it can be circled |
| `Web.Scanner` | `scanner.ex`, `scanner/` | The scanner page: driving the flatbed (`scanner/bed.ex`, `scanner/driver.ex`) and taking a roll from scans to a published sheet (`scanner/pipeline.ex`) |
| `Web.Darkroom` | `darkroom.ex`, `darkroom/` | The print editor: edits kept as recipes, LightCraft for every adjustment, repair, the film-based colour starting point (`darkroom/prior.ex`) and the learned taste (`darkroom/taste.ex`) |
| `Web.ShareCard` | `share_card.ex` | The picture a link shows when shared: drawn from the work itself |

### Training and rides

| Module | File / folder | What it does |
|---|---|---|
| `Web.Fitness` | `fitness.ex`, `fitness/` | The training plan and the exercise wiki (`fitness/vault.ex` reads them from `content/fitness/`), the training log, training blocks and their maths (`fitness/progression.ex`, `fitness/training.ex`), the exercise figures and their films (`fitness/figure.ex`, `fitness/clip.ex`) |
| `Web.Rides` | `rides.ex`, `rides/` | Activities mirrored from Komoot every hour (`rides/komoot_sync.ex`), with heart rate from Apple Health, and the privacy checks that decide what a stranger may see |
| `Web.Komoot` | `komoot/` | Logging in to Komoot and keeping the token |
| `Web.Clock` | `clock.ex` | Today's date in US Pacific time, without a time-zone database |

### The prayer pages

| Module | File / folder | What it does |
|---|---|---|
| `Web.Bible` | `bible.ex`, `bible/` | The Bible the site hosts, from `priv/bible/` |
| `Web.Liturgy.*` | `liturgy/` | Working out the liturgical day from the date, the readings at Mass, the Hours, the saints, the Carmelite fast |

### Readers and correspondence

| Module | File / folder | What it does |
|---|---|---|
| `Web.General` | `general.ex`, `general/` | The guestbook (with its encrypted contact details, `general/contact.ex`) and contact messages |
| `Web.Contact` | `contact.ex`, `contact/` | The contact form's messages |
| `Web.Letters` | `letters.ex` | A reader writing about one particular piece, published only with both sides' consent |
| `Web.Newsletter`, `Web.Email`, `Web.Mailer` | `newsletter.ex`, `newsletter/`, `email.ex`, `mailer.ex` | The newsletter: subscribers, drafts, sending, unsubscribing |
| `Web.Webmentions` | `webmentions.ex`, `webmentions/` | Other sites telling this one they linked to it, and this one telling them |
| `Web.Pieces` | `pieces.ex` | One name for "a piece of work", whatever section it is in |
| `Web.Almanac` | `almanac.ex` | The daybook: every week and day, with what was made on it |
| `Web.Search` | `search.ex` | One search across every section. Every public page must be findable |
| `Web.Nearby` | `nearby.ex` | What a visitor who hit a missing page was probably looking for |
| `Web.Happening` | `happening.ex` | The homepage's "Happening" section |
| `Web.Author` | `author.ex` | What the site says about its author, from settings rather than code |

### Running the machine

| Module | File / folder | What it does |
|---|---|---|
| `Web.Application` | `application.ex` | What starts when the site starts, and in what order (the supervision tree) |
| `Web.Repo` | `repo.ex` | The connection to the database |
| `Web.Backup` | `backup.ex`, `backup/` | Nightly database snapshots, versions of the written content, copies to an external drive, and a weekly rehearsal of a restore |
| `Web.Monitor` | `monitor.ex`, `monitor/` | Every 15 minutes: the certificate, the proxy, DNS, the disk and the services. Mails the author when something fails |
| `Web.SystemStatus` | `system_status.ex` | The machine's state as the admin overview shows it |
| `Web.Scheduler` | `scheduler.ex` | Jobs that run on a clock (the times are in `config/config.exs`) |
| `Web.Workers.*` | `workers/` | Jobs that run in the background, queued with Oban |
| `Web.Analytics` | `analytics.ex`, `analytics/` | Counting visits, by a hash of the address, never the address itself |
| `Web.RateLimit` | `rate_limit.ex` | Stopping one visitor from asking for too much too fast |
| `Web.SiteSettings` | `site_settings.ex`, `site_settings/` | Settings changed from the admin without a deploy |
| `Web.Notify` | `notify.ex` | The site writing to its author |
| `Web.Studio` | `studio.ex` | What the admin's front page shows for each part of the site |
| `Web.Warm` | `warm.ex` | Loading slow things once at start-up, so the first visitor does not wait |
| `Web.Release` | `release.ex` | Running migrations in a compiled release |
| `Web.Pc.Index` | `pc/` | Everything the `/pc` terminal can jump to, by the name it has on disk |
| `Web.Language.Grammar` | `language/` | A spelling and grammar check on the guestbook and contact forms. **It sends the visitor's text to LanguageTool's public service**, so it runs only when the visitor presses the check button (rate-limited) |

## If you want to change…

- **How a post is read or shown**: start at `blog.ex`; the page itself is in
  `lib/web_web/controllers/blog_html/`.
- **What gets backed up**: `backup/content.ex` (`@default_sources`).
- **When a scheduled job runs**: `config/config.exs`, the `Web.Scheduler` section.
- **A new database table**: `mix ecto.gen.migration name_in_snake_case`, then a schema module in
  the right context's folder.
- **Anything near privacy** (rides, the guestbook's contact details, what is public): read the
  context's `@moduledoc` and `CLAUDE.md` first. The rules there are tested, and the tests say
  why.
