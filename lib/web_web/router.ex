defmodule WebWeb.Router do
  @moduledoc """
  Every address the site answers, and which code answers it. **Start here to
  find the code behind any page**: search this file for the address.

  The file is read top to bottom:

  1. **Pipelines** (`pipeline :browser` and the others) are the steps a request
     passes through before its page: for an ordinary page, counting the visit,
     noting whether the visitor is the admin, today's visitor figure, and the
     site's settings, plus Phoenix's own session and CSRF protection.
  2. **The public site** (`scope "/"` with `pipe_through :browser`): every page
     anyone can visit, then the old addresses that redirect.
  3. **The admin**, in two blocks, one after the other. `live_session :admin`
     holds every `/admin` page: its `on_mount {WebWeb.AdminAuth, :ensure_admin}`
     line turns away anyone not logged in. A `live_session` guards pages only,
     so the admin's controller routes (downloads, and files served to the admin
     alone) are in the scope below it, piped through `:admin_only`, which
     answers the site's 404 before any action runs. **A new admin page goes in
     the first block and a new admin controller route in the second**:
     `test/web_web/router_admin_test.exs` fails for an `/admin` address that is
     in neither.
  4. **Addresses for other programs**, each in its own small scope with only
     what it needs: one-click unsubscribe, webmentions, the `/seen` beacon,
     `/health` and the share pictures. Most have no session and set no cookie.
  5. **Development only** (`/dev`): Phoenix's dashboard and a preview of sent
     mail, admin only, and absent from the live site.

  Every public page must also be findable by search: `test/web/search_test.exs`
  walks these routes and fails for any public address `Web.Search` cannot find.
  """

  use WebWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {WebWeb.Layouts, :root}
    plug :put_layout, html: {WebWeb.Layouts, :app}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :put_csrf_token_in_session
    plug WebWeb.Plugs.OwnerMark
    plug WebWeb.Plugs.Analytics
    plug WebWeb.Plugs.SetCurrentUser
  end

  defp put_csrf_token_in_session(conn, _) do
    token = Phoenix.Controller.get_csrf_token()
    put_session(conn, "csrf_token", token)
  end

  # What the admin's controller routes pass through after :browser. A plain
  # `get` gets nothing from a `live_session`'s `on_mount` hooks, so without
  # this each action would have to ask the session itself.
  pipeline :admin_only do
    plug WebWeb.Plugs.RequireAdmin
  end

  scope "/", WebWeb do
    pipe_through :browser

    live_session :default,
      layout: {WebWeb.Layouts, :app},
      on_mount: [{WebWeb.FreshAssets, :default}] do
      # The admin's door (WebWeb.AdminSessionController). Logging out is a
      # DELETE and nothing else, so a link or a picture on another page cannot
      # log the admin out.
      live "/admin/login", AdminLoginLive, :new
      post "/admin/login", AdminSessionController, :create
      delete "/admin/logout", AdminSessionController, :delete

      # Feeds & Static
      get "/feed", FeedController, :index
      get "/sitemap.xml", SitemapController, :index

      # Main pages
      get "/", PageController, :home
      get "/about", PageController, :about
      # The prayer pages (WebWeb.ChristController): the liturgical day, the
      # Hours, the readings at Mass, the Rosary and the Bible they are read
      # from. Unlisted: out of the sitemap and `noindex`, yet searchable.
      get "/Christ", ChristController, :index
      get "/Christ/hours/:hour", ChristController, :hour
      get "/Christ/angelus", ChristController, :angelus
      get "/Christ/readings", ChristController, :readings
      get "/Christ/rosary", ChristController, :rosary
      get "/Christ/saints/:symbol", ChristController, :saint
      get "/Christ/calendar", ChristController, :calendar
      get "/Christ/bible", ChristController, :bible
      get "/Christ/bible/go", ChristController, :go
      get "/Christ/bible/:book", ChristController, :book
      get "/Christ/bible/:book/:chapter", ChristController, :chapter
      # The pages were built at /faith, and an address typed by hand is
      # lower case.
      get "/faith/*rest", LegacyRedirectController, :christ
      get "/christ/*rest", LegacyRedirectController, :christ
      # The manual: how the site and the film pipeline work, rendered from
      # docs/how-to.md so the same file reads on GitHub.
      get "/how-to", PageController, :how_to
      # One search across every section (Web.Search). The query is the URL.
      get "/search", PageController, :search
      # What the search field offers while it is being typed in (JSON).
      get "/search/suggest", PageController, :suggest
      # The roadmap: where the site is going, rendered from
      # docs/roadmap.md the same way.
      get "/roadmap", PageController, :roadmap

      # The site read by date: one day whole, one year at once (Web.Daybook).
      get "/day/:date", DaybookController, :day
      get "/daybook", DaybookController, :index
      get "/daybook/:year", DaybookController, :year
      get "/daybook/:year/week/:week", DaybookController, :week
      # The year's essays as a book (Web.Daybook.Book), once it is built.
      get "/daybook/:year/book.epub", DaybookController, :book_epub
      get "/daybook/:year/book.pdf", DaybookController, :book_pdf
      # It was "the almanac" until 2026-10-07; an almanac looks ahead, and
      # this keeps a record. Old links follow.
      get "/almanac", LegacyRedirectController, :almanac
      get "/almanac/*rest", LegacyRedirectController, :almanac

      live "/contact", NewsletterLive, :contact
      live "/newsletter", NewsletterLive, :newsletter

      # Blog (streetscissors) — strictly typed work
      get "/blog", BlogController, :index
      get "/blog/:slug", BlogController, :show

      # Captain's logs — spoken work, decoupled from the blog
      live "/logs", LogsLive.Index, :index
      live "/logs/:slug", LogsLive.Show, :show

      # Unsubscribe. Deliberately POST to act — mail clients and scanners
      # prefetch links, and a GET that unsubscribed would remove people whose
      # provider merely looked at the message.
      get "/unsubscribe/:token", UnsubscribeController, :show
      post "/unsubscribe/:token", UnsubscribeController, :update

      # The logs lived at /audio before they became their own section
      get "/audio", LegacyRedirectController, :audio
      get "/admin/content", LegacyRedirectController, :admin_content

      # Legacy manuscripts URLs — the section merged into /blog
      get "/manuscripts", LegacyRedirectController, :manuscripts_index
      get "/manuscripts/:category", LegacyRedirectController, :manuscripts_category
      get "/manuscripts/:category/:slug", LegacyRedirectController, :manuscripts_show
      get "/manuscripts/:category/audio/:filename", LegacyRedirectController, :manuscripts_audio

      # Other features
      live "/negatives", NegativesLive, :index
      # A roll and a frame each have their own address, the frame nested under
      # the roll it was cut from. Both sit above the image routes below, which
      # serve bytes rather than pages.
      live "/negatives/roll/:roll", NegativesLive, :sheet
      live "/negatives/roll/:roll/frame/:frame", NegativesLive, :frame
      get "/negatives/image/:filename", NegativesController, :serve_image
      get "/negatives/preview/:filename", NegativesController, :serve_preview
      get "/negatives/frame/:roll/:frame", NegativesController, :serve_frame
      # The print itself rather than the downscaled copy the page shows.
      get "/negatives/frame/:roll/:frame/original", NegativesController, :serve_frame_original
      live "/pc", PcLive
      # An old alias for the archive. It used to diverge — sorting from it
      # rewrote the address bar to /negatives — so it now carries the same
      # routes rather than half of them.
      live "/archive", NegativesLive, :index
      live "/archive/roll/:roll", NegativesLive, :sheet
      live "/guestbook", GuestbookLive
      live "/fitness", FitnessLive.Index, :index
      # One weekday of the regimen, whatever today is. /fitness is today.
      live "/fitness/day/:day", FitnessLive.Index, :day
      # Any other session, for the admin; a visitor is sent to /fitness.
      live "/fitness/session/:slug", FitnessLive.Index, :session
      live "/fitness/wiki", FitnessLive.Wiki, :index
      live "/fitness/wiki/:slug", FitnessLive.Show, :show
      get "/fitness/regimen", LegacyRedirectController, :fitness_regimen

      # Rides — must stay above the /fitness/:slug catch-all
      live "/fitness/rides", RidesLive.Index, :index
      # The live page is gone — above :id so old links redirect rather than 404
      get "/fitness/rides/live", RideRedirectController, :index
      live "/fitness/rides/:id", RidesLive.Show, :show
      get "/fitness/rides/:id/thumb", RideThumbController, :show

      # Old fitness-blog post URLs — must stay last among /fitness routes
      get "/fitness/:slug", LegacyRedirectController, :fitness_slug

      # Legacy ride paths (the section briefly lived at /rides)
      get "/rides", RideRedirectController, :index
      get "/rides/:id", RideRedirectController, :show
      get "/live", RideRedirectController, :live
    end

    # AdminNav runs second: it feeds the rail (current page, waiting counts)
    # and has nothing to compute for a visitor AdminAuth is turning away.
    live_session :admin,
      layout: {WebWeb.Layouts, :admin},
      on_mount: [{WebWeb.AdminAuth, :ensure_admin}, {WebWeb.AdminNav, :default}] do
      # Admin
      live "/admin/dashboard", AdminLive.Dashboard
      live "/admin/readers", AdminLive.Readers
      # A set, a check-in or a note in a few taps (also the phone's shortcuts).
      live "/admin/quick", AdminLive.QuickAdd
      # The old single "content" hub routed uploads by file extension; blog and
      # logs each own their ingestion now.
      live "/admin/blog", AdminLive.BlogManager
      live "/admin/blog/:slug/edit", AdminLive.BlogEditor
      # Papers (Web.Writing.Papers): the same workbench, never published.
      live "/admin/writing", AdminLive.WritingDesk
      live "/admin/writing/:slug", AdminLive.PaperEditor
      # A Zotero document read and annotated (Web.Writing.Zotero.Reader).
      live "/admin/zotero/:item", AdminLive.ZoteroReader
      live "/admin/keywords", AdminLive.Keywords
      live "/admin/health", AdminLive.ContentHealth
      live "/admin/logs", AdminLive.LogsManager
      # The cutting room (Web.Cuts): a log assembled from takes, prints, titles
      # and sound.
      live "/admin/cuts", AdminLive.Cuts
      live "/admin/cuts/:id", AdminLive.CuttingRoom
      live "/admin/fitness", AdminLive.FitnessManager
      live "/admin/fitness/fueling", AdminLive.Fueling
      # The training block's report, with its progress photographs.
      live "/admin/fitness/block", AdminLive.BlockReport
      live "/admin/scanner", AdminLive.Scanner
      # The print editor (Web.Darkroom): the prints roll by roll, and one print
      # on the bench.
      live "/admin/darkroom", AdminLive.Darkroom
      # Two grades of one print and a choice, to teach Web.Darkroom.Taste.
      live "/admin/darkroom/taste", AdminLive.Taste
      live "/admin/darkroom/:roll/:frame", AdminLive.DarkroomEditor
      live "/admin/inbox", AdminLive.Inbox
      live "/admin/guestbook", AdminLive.GuestbookManager
      live "/admin/citations", AdminLive.Citations
      live "/admin/newsletter", AdminLive.Newsletter
      live "/admin/rides", AdminLive.RidesManager
      live "/admin/settings", AdminLive.Settings
    end
  end

  # The admin's controller routes: what the admin downloads, and the files the
  # admin's pages show. :admin_only answers the site's 404 to anyone without
  # the admin session before the action runs, so no action here asks again.
  scope "/", WebWeb do
    pipe_through [:browser, :admin_only]

    # Pandoc's Word, PDF or LaTeX of a paper or a post (Web.Writing.Export).
    get "/admin/writing/:slug/export/:format", WritingExportController, :paper
    get "/admin/blog/:slug/export/:format", WritingExportController, :post
    # A Zotero attachment's file, for the reader (Web.Writing.Zotero.Reader).
    get "/admin/zotero/file/:key/:md5", ZoteroFileController, :show
    # The cutting room's proxies (Web.Cuts).
    get "/admin/cuts/:id/media/:file", CutMediaController, :show
    # Progress photographs (Web.Fitness.Photos) and the weekly Quarto report
    # (Web.Fitness.Report): the newest, or one by its date.
    get "/admin/fitness/photos/:date/:file", FitnessPhotoController, :show
    get "/admin/fitness/report", FitnessReportController, :show
    get "/admin/fitness/report/:date", FitnessReportController, :show
    # The print editor's pictures (Web.Darkroom): the bench's, a frame's repair
    # mask, the frame as developed, and Stable Diffusion's fill of it.
    get "/admin/darkroom/picture/:token/:file", DarkroomController, :picture
    get "/admin/darkroom/mask/:roll/:frame", DarkroomController, :mask
    get "/admin/darkroom/developed/:roll/:frame", DarkroomController, :developed
    get "/admin/darkroom/candidate/:roll/:frame", DarkroomController, :candidate
    # The subscriber list and the training log, as CSV.
    get "/admin/subscribers/export", NewsletterController, :export_csv
    get "/fitness/export/csv", FitnessController, :export_csv

    # The kitchen, rendered from content/fitness/meals.md. Admin only because
    # it holds body figures and the household's schedule. Unlisted as well:
    # nothing links to it, it is out of the sitemap, robots.txt and the search,
    # and it sends `noindex, nofollow`. Its first address, /fitness/meals,
    # falls through the /fitness/:slug catch-all and redirects to the blog
    # like any other retired fitness address.
    get "/food", PageController, :food
  end

  # RFC 8058 one-click unsubscribe. The POST comes from a mail client or the
  # sending provider — no session, no CSRF token, so it cannot go through
  # :browser. The signed token in the URL is what authorises it, and the action
  # is idempotent and only ever removes consent, so there is nothing for a
  # forged request to gain. Its answer is a status with no body, which is why
  # it carries none of the browser's security headers.
  # sobelow_skip ["Config.Headers"]
  pipeline :one_click do
    plug :accepts, ["html", "json"]
  end

  scope "/", WebWeb do
    pipe_through :one_click
    post "/unsubscribe/:token/one-click", UnsubscribeController, :one_click
  end

  # Webmention receiving (W3C Webmention). Like one-click unsubscribe, the
  # POST comes from another server with no session or CSRF token, so it
  # cannot go through :browser; nothing it carries is trusted until the
  # source has been fetched and the author has approved the mention. No
  # `accepts` plug: senders vary in what they send as Accept, and the answer
  # is always a line of plain text.
  scope "/", WebWeb do
    post "/webmention", WebmentionController, :create
  end

  # A prefetched page reporting that it was actually shown
  # (WebWeb.SeenController). A beacon has no CSRF token, so it cannot go
  # through :browser; it needs the session only to tell the admin apart.
  # sobelow_skip ["Config.CSRF"]
  pipeline :beacon do
    plug :fetch_session
  end

  scope "/", WebWeb do
    pipe_through :beacon
    post "/seen", SeenController, :create
  end

  # The health check, asked by the uptime check from outside and by
  # Web.Monitor through the proxy. No pipeline, for the opposite reason to the
  # two above: there is nothing to protect and nothing worth recording, so it
  # sets no session and logs no analytics hit however often it is asked.
  scope "/", WebWeb do
    get "/health", HealthController, :show
    # The IndexNow key (Web.IndexNow), likewise asked by machines only.
    get "/indexnow.txt", IndexNowController, :show
  end

  # Share cards: the picture a link to a post, frame or roll unfurls with
  # (Web.ShareCard). Asked for by unfurlers, not by people, so like /health
  # they pass through no pipeline: no session, and no hit to count.
  scope "/share", WebWeb do
    get "/post/:file", ShareController, :post
    get "/frame/:roll/:file", ShareController, :frame
    get "/roll/:file", ShareController, :roll
  end

  # LiveDashboard and the Swoosh mailbox preview.
  #
  # Two independent gates, because one is not enough: `dev_routes` is false on a
  # public deploy (config/dev.exs) so these compile away entirely, AND the scope
  # is piped through an admin check so a stale build cannot re-expose them.
  # Both previously failed — /dev/dashboard served the process inspector, ETS
  # browser and ecto_stats to anyone on the internet.
  if Application.compile_env(:web, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:browser, :admin_only]

      live_dashboard "/dashboard",
        metrics: WebWeb.Telemetry,
        on_mount: [{WebWeb.AdminAuth, :ensure_admin}]

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
