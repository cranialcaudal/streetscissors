# test/

**The automated checks.** `mix test` runs every one of them (about 1,600) and prints a dot for
each that passes. They are the project's safety net: before any change counts as done,
`mix precommit` must pass, and that runs all of these.

## How it is laid out

The folders mirror `lib/`:

| Folder | What it tests |
|---|---|
| [`web/`](web/) | The core (`lib/web/`): `web/blog_test.exs` tests `Web.Blog`, and so on |
| [`web_web/`](web_web/) | The website (`lib/web_web/`): pages, controllers, LiveViews, the router |
| [`support/`](support/) | Not tests, but what the tests stand on (below) |
| `private/` | Checks against the **real** content on the live machine. Not in git, and skipped when absent |
| `test_helper.exs` | Starts the test run |

## Tests never touch real things

This is the rule that makes the suite safe to run anywhere, including on the live server:

- **Content is invented.** `config/test.exs` points every content path at
  [`support/fixtures/`](support/fixtures/): sample blog posts, a sample training plan, a sample
  roll of film, sample emails. None of them is real, and none names a real person or place.
- **Outside programs are stand-ins.** `support/stub_ffmpeg`, `stub_magick`, `stub_lightcraft`,
  `stub_film_develop`, `stub_scanimage` and the rest are tiny scripts that answer the way the real
  program would, instantly. `config/test.exs` points the site at them instead of the real ones.
  A few tests that need the real program on purpose (rendering a real video in
  `web/cuts_render_test.exs`, measuring the figure in `web/fitness_measure_test.exs`) skip
  themselves when it is not installed.
- **The network is never used.** Komoot, webmentions and mail are faked (`Req.Test`,
  `support/webmentions_test_resolver.ex`, Swoosh's test adapter).
- **The database is a separate file** (`tmp/db/web_test.db`), and each test's changes are undone
  when it ends (`support/data_case.ex`).

## Running some of them

```bash
mix test                                         # everything
mix test test/web/blog_test.exs                  # one file
mix test test/web/blog_test.exs:42               # the test on line 42
mix test --failed                                # only those that failed last time
```

## Writing one

- Put it in the file that matches the module (`lib/web/keywords.ex` → `test/web/keywords_test.exs`).
- `use Web.DataCase` for core tests, `use WebWeb.ConnCase` for page tests (both in `support/`).
- For a LiveView, use `Phoenix.LiveViewTest` and find elements by their `id`: give the
  elements you test an id in the template.
- Need sample content? Add it to `support/fixtures/`, invented, never copied from the real
  vault.
- Name the test by what should be true ("a draft is not in the feed"), so a failure reads as a
  sentence.
- Many tests carry a comment saying *why* the rule exists, often a bug that once happened. Read
  it before changing a test that fails.
