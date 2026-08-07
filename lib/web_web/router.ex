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

    live_session :default, layout: {WebWeb.Layouts, :app} do
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
      get "/england2026", EnglandController, :show
      get "/england2026/call", EnglandController, :call_times
      get "/about", PageController, :about
      get "/calendar-markdown", PageController, :calendar_markdown
      live "/contact", NewsletterLive, :contact
      live "/newsletter", NewsletterLive, :newsletter

      # Blog (streetscissors) — strictly typed work
      get "/blog", BlogController, :index
      get "/blog/:slug", BlogController, :show

      # Captain's logs — spoken work, decoupled from the blog
      live "/logs", LogsLive.Index, :index
      live "/logs/:slug", LogsLive.Show, :show

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
      # A single published frame, addressable so it can be linked to on its own
      # and carry the sheet it was cut from. Above the image routes below, which
      # serve bytes rather than pages.
      live "/negatives/roll/:roll/frame/:frame", NegativesLive, :frame
      get "/negatives/image/:filename", NegativesController, :serve_image
      get "/negatives/preview/:filename", NegativesController, :serve_preview
      get "/negatives/frame/:roll/:frame", NegativesController, :serve_frame
      live "/pc", PcLive
      live "/archive", NegativesLive, :index
      live "/guestbook", GuestbookLive
      live "/fitness", FitnessLive.Index, :index
      live "/fitness/wiki", FitnessLive.Wiki, :index
      live "/fitness/wiki/:slug", FitnessLive.Show, :show
      get "/fitness/regimen", LegacyRedirectController, :fitness_regimen

      get "/fitness/export/csv", FitnessController, :export_csv
      live "/fitness/biometrics", FitnessLive.Biometrics, :index
      get "/fitness/biometrics/export", FitnessController, :export_biometrics_csv

      # Rides — must stay above the /fitness/:slug catch-all
      live "/fitness/rides", RidesLive.Index, :index
      # And /fitness/rides/live above :id, or "live" gets captured as a ride id
      live "/fitness/rides/live", RidesLive.LiveRide, :show
      live "/fitness/rides/:id", RidesLive.Show, :show
      get "/fitness/rides/:id/thumb", RideThumbController, :show

      # Old fitness-blog post URLs — must stay last among /fitness routes
      get "/fitness/:slug", LegacyRedirectController, :fitness_slug

      # Legacy ride paths (the section briefly lived at /rides)
      get "/rides", RideRedirectController, :index
      get "/rides/:id", RideRedirectController, :show
      get "/live", RideRedirectController, :live
    end

    live_session :admin,
      layout: {WebWeb.Layouts, :admin},
      on_mount: {WebWeb.AdminAuth, :ensure_admin} do
      # Admin
      live "/admin/dashboard", AdminLive.Dashboard
      # The old single "content" hub routed uploads by file extension; blog and
      # logs each own their ingestion now.
      live "/admin/blog", AdminLive.BlogManager
      live "/admin/logs", AdminLive.LogsManager
      live "/admin/fitness", AdminLive.FitnessManager
      live "/admin/guestbook", AdminLive.GuestbookManager
      live "/admin/newsletter", AdminLive.Newsletter
      live "/admin/rides", AdminLive.RidesManager
    end
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", WebWeb do
    pipe_through :api
    post "/health/ingest", HealthWebhookController, :ingest
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
