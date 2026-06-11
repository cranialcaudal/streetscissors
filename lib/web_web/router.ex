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
      live "/audio", AudioLive
      get "/about", PageController, :about
      live "/contact", NewsletterLive, :contact
      live "/newsletter", NewsletterLive, :newsletter

      # Manuscripts
      get "/manuscripts", ManuscriptController, :index
      get "/manuscripts/:category/:slug", ManuscriptController, :show
      get "/blog/:category", ManuscriptController, :category_index
      get "/manuscripts/:category/audio/:filename", ManuscriptController, :serve_audio

      # Other features
      live "/pc", PcLive
      live "/archive", ArchiveLive
      live "/guestbook", GuestbookLive
      live "/fitness", FitnessBlogLive.Index, :index
      live "/fitness/wiki", FitnessLive.Wiki, :index
      live "/fitness/wiki/:slug", FitnessLive.Show, :show
      live "/fitness/regimen", FitnessLive.Regimen, :index

      get "/fitness/export/csv", FitnessController, :export_csv
      live "/fitness/biometrics", FitnessLive.Biometrics, :index
      get "/fitness/biometrics/export", FitnessController, :export_biometrics_csv

      # Rides — must stay above the /fitness/:slug catch-all
      live "/fitness/rides", RidesLive.Index, :index
      live "/fitness/rides/:id", RidesLive.Show, :show

      live "/fitness/:slug", FitnessBlogLive.Show, :show

      # Legacy ride paths (the section briefly lived at /rides)
      get "/rides", RideRedirectController, :index
      get "/rides/:id", RideRedirectController, :show
    end

    live_session :admin,
      layout: {WebWeb.Layouts, :admin},
      on_mount: {WebWeb.AdminAuth, :ensure_admin} do
      # Admin
      live "/admin/dashboard", AdminLive.Dashboard
      live "/admin/content", AdminLive.ContentManager
      live "/admin/fitness", AdminLive.FitnessManager
      live "/admin/guestbook", AdminLive.GuestbookManager
      live "/admin/newsletter", AdminLive.Newsletter
      live "/admin/rides", AdminLive.RidesManager
    end
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:web, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: WebWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
