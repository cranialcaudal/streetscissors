# priv/

**Files the site reads while it runs, which are not code.** The name is Elixir's convention
("private" to the application). Everything here is packed into the release when the site is
built, so the live site carries its own copy.

| Folder | What it holds | Read by |
|---|---|---|
| [`repo/migrations/`](repo/migrations/) | The database's history: each file is one change to the tables, run in order by date. Never edit one that has already run; add a new one with `mix ecto.gen.migration` | `mix ecto.migrate`, and the release at start-up |
| `repo/seeds.exs`, `repo/seeds_recipes.exs` | Starting rows for a new database | `mix setup` |
| [`static/`](static/) | Files served exactly as they are: icons, `robots.txt`, the service worker (`sw.js`), the fonts, and the built `assets/` | The browser |
| [`bible/`](bible/) | The Bible the prayer pages read: one folder per translation, one JSON file per book. Only public-domain texts are committed (the CPDV) | `Web.Bible` |
| [`liturgy/`](liturgy/) | The Church calendars (general, US, Discalced Carmelite), the lectionary's citations and the saints' lives | `Web.Liturgy.*` |
| [`figure/`](figure/) | The "camera" that films the exercise figures: a small Node.js program driving headless Chrome (`render.mjs`, `render.html`, `figure3d.js`) and the tape measure (`measure.mjs`) | `mix fitness.film` |
| [`film/stocks.json`](film/stocks.json) | Figures from film makers' datasheets (colour balance, reciprocity), each with its source | `Web.Darkroom.Prior` |
| [`repair/film_repair.py`](repair/film_repair.py) | The Python program behind the print editor's Repair tab. See `tools/repair/README.md` | `Web.Darkroom.Repair` |
| [`fonts/`](fonts/) | Two typefaces for the share cards, drawn by ImageMagick (licences beside them) | `Web.ShareCard` |
| [`faith/guide.md`](faith/guide.md) | An essay on the Carmelite fast. Kept, but no page shows it | — |
| `gettext/` | Phoenix's translation files (the site is English only) | Phoenix |

Not in git, but expected here on a running machine: `static/images/` (the saints' pictures and
other images that are content), `ride_thumbs/`, and the two `.TXT` reading files the `/pc`
terminal shows. The site works without them.

## Things worth knowing

- **A file in `static/` is public** the moment it is there: anyone can fetch it by its path.
- **The `name-<long code>.ext` and `.gz` copies in `static/`** are made by `mix phx.digest` during
  a deploy (the code in the name changes when the file does, so browsers can keep a copy for a
  year). They are not in git, and you should not edit them; edit the plain-named file beside them.
- **A licensed Bible translation must never be committed here.** Lay it out the same way
  somewhere outside the repository and point `BIBLE_PATH` at it.
