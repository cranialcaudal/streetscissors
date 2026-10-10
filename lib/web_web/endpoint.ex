defmodule WebWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :web

  # The session is a signed cookie: readable by the client, not tamperable,
  # so long as the secret_key_base stays secret. That was once hardcoded in
  # config/dev.exs, in a public repo, while the site ran in dev mode, which
  # made an admin cookie (`%{"admin_user" => true}`) forgeable without the
  # password. Production now takes SECRET_KEY_BASE from the environment
  # (config/runtime.exs) and will not boot without it. The salt is not a
  # secret; it only keeps keys derived for different purposes apart.
  @session_options [
    store: :cookie,
    key: "_web_key",
    signing_salt: Application.compile_env(:web, :session_signing_salt, "dev_only_salt"),
    same_site: "Lax",
    # Never send the admin cookie over plaintext: true in config/prod.exs.
    secure: Application.compile_env(:web, :secure_cookies?, false),
    # Bounds the damage of a stolen cookie; there is no server-side session
    # store to revoke against.
    max_age: 60 * 60 * 24 * 14
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [:peer_data, :x_headers, session: @session_options]],
    longpoll: [connect_info: [:peer_data, :x_headers, session: @session_options]]

  # Serve media files with Range request support for seeking/scrubbing
  plug WebWeb.Plugs.MediaServe

  # Serve at "/" the static files from "priv/static" directory.
  #
  # `gzip` must stay OFF unless `mix phx.digest` runs as part of the deploy.
  # It was previously `not code_reloading?`, which meant disabling the code
  # reloader for the public deploy silently switched it on — and Plug.Static
  # then served `app.css.gz` from a `phx.digest` run months earlier, in
  # preference to the freshly built `app.css`. The whole site rendered with an
  # old stylesheet, and only for clients sending `Accept-Encoding: gzip`
  # (i.e. every browser, but not curl by default).
  #
  # ./redeploy.sh does digest now (`mix assets.deploy`), so the .gz files are
  # fresh on every deploy; it stays off all the same, because Caddy compresses
  # on the wire and a second source of compressed bytes is a second way to
  # serve the wrong ones.
  plug Plug.Static,
    at: "/",
    from: :web,
    gzip: Application.compile_env(:web, :serve_gzip_assets?, false),
    only: WebWeb.static_paths(),
    raise_on_missing_only: code_reloading?

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :web
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug WebWeb.Router
end
