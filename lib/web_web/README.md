# lib/web_web/

**The website: every address, the code that answers it, and the HTML it sends back.** The work
itself (reading posts, developing film, counting visits) is done by the core in
[`../web/`](../web/README.md). This folder decides what a page looks like and how it behaves.

## The kinds of file here

| Folder or file | What it holds | In plain words |
|---|---|---|
| [`router.ex`](router.ex) | Every address the site answers, and which code answers it | **Start here.** Find the address you care about; the line tells you the file |
| [`endpoint.ex`](endpoint.ex) | The front door every request passes first: static files, sessions, the live-page socket | Rarely changed |
| [`controllers/`](controllers/) | Code for **ordinary pages**: the request comes in, the controller gathers what the page needs, a template renders it, done | Blog posts, the prayer pages, feeds, the daybook, the manual |
| `controllers/*_html/` | The **templates** (`.html.heex` files) those controllers render: HTML with `{@values}` filled in | `blog_html/show.html.heex` is a blog post's page |
| [`live/`](live/) | **LiveViews**: pages that stay connected to the server and change in place without reloading | The admin, the negatives archive, the training log, the guestbook |
| [`components/`](components/) | **Components**: pieces of HTML used on many pages (buttons, the header, the wordmark, a ride card), written as functions | `core_components.ex` and `admin_components.ex` hold most of them |
| `components/layouts/` | The **layouts**: the page frame every page sits inside (the `<head>`, the header, the flash messages) | `root.html.heex` is the outermost frame |
| [`plugs/`](plugs/) | **Plugs**: small steps every request in a pipeline goes through (counting the visit, loading settings, checking the admin session) | — |
| `captcha.ex`, `client_ip.ex`, `navigation.ex`, … | Helpers used by several pages | — |

**Controllers or LiveViews?** A controller page is sent once and is finished: fast and simple,
and it works with JavaScript off. A LiveView keeps a connection (a WebSocket) open so the server
can update the page as things change: a scan in progress, a list you are filtering. The site
uses controllers wherever a page does not need that.

## Every address, grouped

The public site:

| Address | Code | What it is |
|---|---|---|
| `/` | `PageController.home` | The homepage |
| `/blog`, `/blog/:slug` | `BlogController` | The writing |
| `/logs`, `/logs/:slug` | `LogsLive.Index`, `LogsLive.Show` | The captain's logs (recordings) |
| `/negatives`, `/negatives/roll/:roll`, `…/frame/:frame` | `NegativesLive` | The film archive: contact sheets and single photographs |
| `/negatives/image/…`, `/negatives/frame/…` | `NegativesController` | The picture files themselves |
| `/fitness`, `/fitness/day/:day` | `FitnessLive.Index` | The training plan, one day to a page |
| `/fitness/wiki`, `/fitness/wiki/:slug` | `FitnessLive.Wiki`, `FitnessLive.Show` | The exercise wiki, with its figures |
| `/fitness/rides`, `/fitness/rides/:id` | `RidesLive.Index`, `RidesLive.Show` | Activities from Komoot |
| `/daybook`, `/daybook/:year`, `…/week/:week`, `/day/:date` | `AlmanacController` | The daybook: what was made each week and day |
| `/Christ` and below | `FaithController` | The prayer pages (unlisted) |
| `/search`, `/search/suggest` | `PageController.search`, `.suggest` | Search |
| `/guestbook` | `GuestbookLive` | The guestbook |
| `/contact`, `/newsletter` | `NewsletterLive` | Writing to the author; signing up |
| `/pc` | `PcLive` | A terminal that reaches anything by its filename |
| `/how-to`, `/roadmap`, `/about` | `PageController` | The manual, the roadmap, about the site |
| `/feed`, `/sitemap.xml` | `FeedController`, `SitemapController` | For feed readers and search engines |
| `/food`, `/england2026` | `PageController.food`, `EnglandController` | Unlisted pages |
| `/share/…` | `ShareController` | The pictures a shared link shows |
| `/health` | `HealthController` | "Is the site up?" for the uptime check |
| `/webmention`, `/seen`, `/api/health/ingest`, `/unsubscribe/…` | `WebmentionController`, `SeenController`, `HealthWebhookController`, `UnsubscribeController` | Things other programs post to |
| `/manuscripts/…`, `/almanac/…`, `/faith/…`, `/rides/…` and others | `LegacyRedirectController`, `RideRedirectController` | Old addresses, sent on to where the page lives now |

The admin, all in `live/admin_live/` unless noted, and all behind the admin login:

| Address | Code | What it is |
|---|---|---|
| `/admin/dashboard` | `AdminLive.Dashboard` | The studio floor: what needs doing, and each program's state |
| `/admin/scanner` | `AdminLive.Scanner` | Scanning a roll of film |
| `/admin/darkroom`, `/admin/darkroom/:roll/:frame`, `/admin/darkroom/taste` | `AdminLive.Darkroom`, `.DarkroomEditor`, `.Taste` | Editing single prints |
| `/admin/cuts`, `/admin/cuts/:id` | `AdminLive.Cuts`, `.CuttingRoom` | The cutting room |
| `/admin/logs` | `AdminLive.LogsManager` | The recording booth |
| `/admin/blog`, `/admin/blog/:slug/edit` | `AdminLive.BlogManager`, `.BlogEditor` | Posts and the editor |
| `/admin/keywords`, `/admin/health` | `AdminLive.Keywords`, `.ContentHealth` | Tending the writing |
| `/admin/fitness`, `/admin/fitness/block`, `/admin/fitness/report` | `AdminLive.FitnessManager`, `.BlockReport`, `FitnessReportController` | The training plan, a block's report, the weekly R report |
| `/admin/rides` | `AdminLive.RidesManager` | Komoot sync and Apple Health imports |
| `/admin/inbox`, `/admin/guestbook`, `/admin/citations`, `/admin/newsletter` | `AdminLive.Inbox`, `.GuestbookManager`, `.Citations`, `.Newsletter` | Mail |
| `/admin/settings` | `AdminLive.Settings` | Settings that change without a deploy |

## How admin pages are protected

Every `/admin/*` LiveView is listed inside `live_session :admin` in the router, which runs
`WebWeb.AdminAuth` before the page loads and turns away anyone not logged in. **A new admin
page must go inside that block**; outside it, it would be public. (The `SetCurrentUser` plug only
tells templates whether the visitor is the admin. It protects nothing.)

## Styling

There are no utility CSS classes here: every page is styled by hand-written CSS in
[`assets/css/`](../../assets/css/), one file per area, using the colour and type variables
("tokens") defined in `assets/css/app.css`. A class in a template such as `blog-post-colophon`
is defined in the matching stylesheet (`writing.css`). See
[`assets/README.md`](../../assets/README.md).

## If you want to change…

- **What a public page shows**: find its address in the table, open its controller or LiveView,
  then its template (`controllers/<name>_html/` or a `.html.heex` beside the LiveView).
- **The header, footer or page frame**: `components/core_components.ex` (`blog_header`) and
  `components/layouts/`.
- **Add a public page**: a route in `router.ex`, a controller function and a template, **and an
  entry in `Web.Search`**: `test/web/search_test.exs` fails for any public page that cannot be
  found by search.
- **Add an admin page**: a route inside `live_session :admin`, a LiveView in `live/admin_live/`,
  and a link in `WebWeb.AdminNav.sections/0` (`live/admin_nav.ex`) so it appears in the rail.
