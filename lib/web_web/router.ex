defmodule WebWeb.Router do
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
    plug WebWeb.Plugs.Analytics
    plug WebWeb.Plugs.SetCurrentUser
    plug WebWeb.Plugs.FetchStats
    plug WebWeb.Plugs.LoadSiteSettings
  end

  defp put_csrf_token_in_session(conn, _) do
    token = Phoenix.Controller.get_csrf_token()
    put_session(conn, "csrf_token", token)
  end

  scope "/", WebWeb do
    pipe_through :browser

    live_session :default,
      layout: {WebWeb.Layouts, :app},
      on_mount: [{WebWeb.FreshAssets, :default}] do
      # Admin auth
      live "/admin/login", AdminLoginLive, :new
      get "/admin/logout", AdminSessionController, :delete
      delete "/admin/logout", AdminSessionController, :delete
      post "/admin/login", AdminSessionController, :create

      # Feeds & Static
      get "/feed", FeedController, :index
      get "/sitemap.xml", SitemapController, :index

      # Main pages
      get "/", PageController, :home
      # A finished trip, kept as it was. Deliberately unlisted, like /food
      # below: nothing links to either page, both are out of the sitemap and
      # robots.txt, and both send `noindex, nofollow`.
      get "/england2026", EnglandController, :show
      get "/england2026/call", EnglandController, :call_times
      get "/about", PageController, :about
      # The prayer pages (WebWeb.FaithController): the liturgical day, the
      # Hours, the readings at Mass, the Rosary and the Bible they are read
      # from. Unlisted like /food below.
      get "/Christ", FaithController, :index
      get "/Christ/hours/:hour", FaithController, :hour
      get "/Christ/angelus", FaithController, :angelus
      get "/Christ/readings", FaithController, :readings
      get "/Christ/rosary", FaithController, :rosary
      get "/Christ/saints/:symbol", FaithController, :saint
      get "/Christ/calendar", FaithController, :calendar
      get "/Christ/bible", FaithController, :bible
      get "/Christ/bible/go", FaithController, :go
      get "/Christ/bible/:book", FaithController, :book
      get "/Christ/bible/:book/:chapter", FaithController, :chapter
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

      # The site read by date: one day whole, one year at once (Web.Almanac).
      get "/day/:date", AlmanacController, :day
      get "/daybook", AlmanacController, :index
      get "/daybook/:year", AlmanacController, :year
      get "/daybook/:year/week/:week", AlmanacController, :week
      # It was "the almanac" until 2026-10-07; an almanac looks ahead, and
      # this keeps a record. Old links follow.
      get "/almanac", LegacyRedirectController, :almanac
      get "/almanac/*rest", LegacyRedirectController, :almanac

      # The kitchen, rendered from content/fitness/meals.md. Deliberately
      # unlisted: nothing links to it, it is out of the sitemap and robots.txt,
      # and it sends `noindex, nofollow`. It used to live at /fitness/meals and
      # in the fitness tab row; that route is gone, so the old path now falls
      # through the /fitness/:slug catch-all and 301s to the blog like any other
      # retired fitness URL. Unlisted is not private — anyone who types /food
      # still gets it. Put it behind `live_session :admin` if that stops being
      # good enough.
      get "/food", PageController, :food
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
      live "/fitness/wiki", FitnessLive.Wiki, :index
      live "/fitness/wiki/:slug", FitnessLive.Show, :show
      get "/fitness/regimen", LegacyRedirectController, :fitness_regimen

      get "/fitness/export/csv", FitnessController, :export_csv

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
      # The old single "content" hub routed uploads by file extension; blog and
      # logs each own their ingestion now.
      live "/admin/blog", AdminLive.BlogManager
      live "/admin/blog/:slug/edit", AdminLive.BlogEditor
      live "/admin/keywords", AdminLive.Keywords
      live "/admin/health", AdminLive.ContentHealth
      live "/admin/logs", AdminLive.LogsManager
      live "/admin/fitness", AdminLive.FitnessManager
      # The week as calendar events, from content/notes/calendar.md. It names
      # venues and times, so it is the author's own reference rather than a
      # page: the action 404s without the admin session.
      get "/admin/fitness/calendar", PageController, :calendar
      live "/admin/scanner", AdminLive.Scanner
      live "/admin/inbox", AdminLive.Inbox
      live "/admin/guestbook", AdminLive.GuestbookManager
      live "/admin/citations", AdminLive.Citations
      live "/admin/newsletter", AdminLive.Newsletter
      get "/admin/subscribers/export", NewsletterController, :export_csv
      live "/admin/rides", AdminLive.RidesManager
      live "/admin/settings", AdminLive.Settings
    end
  end

  # RFC 8058 one-click unsubscribe. The POST comes from a mail client or the
  # sending provider — no session, no CSRF token, so it cannot go through
  # :browser. The signed token in the URL is what authorises it, and the action
  # is idempotent and only ever removes consent, so there is nothing for a
  # forged request to gain.
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
  pipeline :beacon do
    plug :fetch_session
  end

  scope "/", WebWeb do
    pipe_through :beacon
    post "/seen", SeenController, :create
  end

  # Apple Health workouts, posted by an app on the phone as they are recorded
  # (WebWeb.HealthWebhookController). A server-to-server POST with a bearer
  # token: no session, no CSRF. It refuses everything until a token is made.
  pipeline :health_ingest do
    plug :accepts, ["json"]
  end

  scope "/api", WebWeb do
    pipe_through :health_ingest
    post "/health/ingest", HealthWebhookController, :ingest
  end

  # The health check, asked by the uptime check from outside and by
  # Web.Monitor through the proxy. No pipeline, for the opposite reason to the
  # two above: there is nothing to protect and nothing worth recording, so it
  # sets no session and logs no analytics hit however often it is asked.
  scope "/", WebWeb do
    get "/health", HealthController, :show
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
      pipe_through [:browser, WebWeb.Plugs.RequireAdmin]

      live_dashboard "/dashboard",
        metrics: WebWeb.Telemetry,
        on_mount: [{WebWeb.AdminAuth, :ensure_admin}]

      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
