# lib/

**All of the website's own code is in this folder.** Everything else in the repository is
either something this code reads (`content/`, `priv/`), something that checks it (`test/`),
something that builds or runs it (`assets/`, `config/`, `ops/`), or a program it calls
(`tools/`, `analysis/`).

The code is written in [Elixir](https://elixir-lang.org) with the
[Phoenix](https://www.phoenixframework.org) web framework. If you have never read Elixir, the
official [Getting Started guide](https://hexdocs.pm/elixir/introduction.html) takes an
afternoon, and the first eight chapters are enough to follow this code.

## Two halves

| Folder | What it is | A good first file |
|---|---|---|
| [`web/`](web/) | **What the site knows and does**: reading blog posts off disk, storing a recording, working out the day's prayers, developing a roll of film, backing up the database. Nothing here knows about web pages, HTTP or browsers. | [`web/blog.ex`](web/blog.ex) |
| [`web_web/`](web_web/) | **The website itself**: the address of every page (the router), the code that answers each request, the HTML templates, the components pages are built from, and the live pages that update without reloading. | [`web_web/router.ex`](web_web/router.ex) |
| [`mix/tasks/`](mix/tasks/) | Two commands added to `mix` for jobs done at the terminal: `mix fitness.export` (the training log as CSV for R) and `mix fitness.film` (filming the exercise figures). | — |

The names are Phoenix's convention: the app is called `:web`, so its core is `Web` and its web
layer is `WebWeb`. (`WebWeb` reads oddly, but every Phoenix app has the same pattern, such as
`MyApp` and `MyAppWeb`.)

**The rule for which half something goes in:** if it would still make sense with the website
replaced by something else (a phone app, a command-line tool), it belongs in `web/`. A function
that reads a roll of film off the disk goes in `web/negatives.ex`; the page that shows it goes in
`web_web/live/negatives_live.ex`.

## How a request travels through it

1. A browser asks for an address, for example `/blog/tides-out`.
2. [`web_web/router.ex`](web_web/router.ex) matches the address and picks the code that answers
   it: here `WebWeb.BlogController`, function `show`.
3. On the way, the request passes through the **plugs** of its pipeline
   ([`web_web/plugs/`](web_web/plugs/)), which count the visit, load the site's settings, and
   check for an admin session.
4. The controller asks the core for what it needs (`Web.Blog.get_post("tides-out")`), which reads
   the markdown file from `content/blog/`.
5. The controller hands the post to a template (`web_web/controllers/blog_html/show.html.heex`),
   which turns it into HTML.
6. The HTML goes back to the browser.

A **LiveView** page (in [`web_web/live/`](web_web/live/)) starts the same way, then keeps a
connection open so that it can change in place: the admin pages, the negatives archive, the
training log. [`docs/how-to.md`](../docs/how-to.md) Part 5 tells this whole journey in more
detail.

## Finding your way

- Every module starts with a `@moduledoc`: a paragraph or more saying what it is for and what
  is not obvious about it. Read that before the code.
- The longest modules open with a **"How this file is laid out"** list, and banner comments
  (`# ── Part name ───`) mark each part in the code.
- [`web/README.md`](web/README.md) and [`web_web/README.md`](web_web/README.md) list every
  module group with a sentence each, so you can find anything from one page.
- [`CLAUDE.md`](../CLAUDE.md) at the top of the repository lists the traps: the things that look
  safe to change and are not.
