import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/web start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :web, WebWeb.Endpoint, server: true
end

config :web, WebWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if fitness_path = System.get_env("FITNESS_PATH") do
  config :web, :fitness_path, fitness_path
end

# Root directory Web.Blog reads markdown + audio from. When unset,
# Web.Blog falls back to the repo's content/blog directory.
if blog_path = System.get_env("BLOG_PATH") do
  config :web, :blog_path, blog_path
end

if config_env() == :prod do
  database_path =
    System.get_env("DATABASE_PATH") ||
      raise """
      environment variable DATABASE_PATH is missing.
      For example: /etc/web/web.db
      """

  config :web, Web.Repo,
    database: database_path,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "5")

  # Komoot static-map thumbnails live beside the database so they persist
  # on the data volume.
  config :web,
         :ride_thumbs_path,
         System.get_env("RIDE_THUMBS_PATH") ||
           Path.join(Path.dirname(database_path), "ride_thumbs")

  # Uploaded audio for the captain's logs. This MUST resolve outside the
  # release: Web.Uploads defaults to "priv/static/uploads", and a release ships
  # priv/ inside itself and replaces it wholesale on every build — so the
  # default would silently delete every uploaded recording on each deploy.
  # Beside the database, which is the one directory that already has to
  # outlive deploys.
  config :web,
         :uploads_path,
         System.get_env("UPLOADS_PATH") ||
           Path.join(Path.dirname(database_path), "uploads")

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "streetscissors.com"

  config :web,
         :admin_password,
         System.get_env("ADMIN_PASSWORD") ||
           raise("""
           environment variable ADMIN_PASSWORD is missing.
           This is the password used to log into the /admin dashboard.
           """)

  # Komoot auto-sync credentials (optional — the hourly sync simply stays
  # disabled when these are unset; manual GPX import always works).
  config :web, :komoot,
    email: System.get_env("KOMOOT_EMAIL"),
    password: System.get_env("KOMOOT_PASSWORD")

  # Health Auto Export webhook token (optional — endpoint returns 401 when unset).
  config :web, :health_webhook_token, System.get_env("HEALTH_WEBHOOK_TOKEN")

  # Off-disk copy of each database snapshot (optional — skipped when unset or
  # when the target is not mounted).
  config :web, :backup_mirror_path, System.get_env("BACKUP_MIRROR_PATH")

  # Off-disk copy of the negatives archive (optional — skipped when unset or
  # when the target is not mounted).
  config :web, :photos_mirror_path, System.get_env("PHOTOS_MIRROR_PATH")

  # Where snapshots land. Web.Backup falls back to a path under $HOME, which is
  # right for this deploy but leaves nothing to point elsewhere with — staging a
  # release against a copy of the database would otherwise write snapshots of
  # that copy straight into the real backup directory.
  if backup_path = System.get_env("BACKUP_PATH") do
    config :web, :backup_path, backup_path
  end

  config :web, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :web, WebWeb.Endpoint,
    # Caddy terminates TLS in front of us, so the canonical public URL is
    # https on 443. This drives Endpoint.url/0, which the sitemap, canonical
    # links and og:url all build on — with http/80 here they emit the
    # pre-redirect URL and search engines treat it as a separate site.
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    check_origin: ["//#{host}", "//www.#{host}"],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :web, WebWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :web, WebWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # Resend over HTTPS — the same adapter dev uses. This block previously
  # configured Gmail SMTP against an app password that was revoked and never
  # reissued, so the first real prod boot would have silently stopped sending.
  # Keep this in step with the dev mailer in config/dev.exs.
  #
  # Raised rather than defaulted to nil: a missing key otherwise fails at the
  # *send*, inside the background Task that broadcasts the newsletter, where
  # nothing surfaces it. Failing at boot is louder, and matches how
  # SECRET_KEY_BASE and ADMIN_PASSWORD are handled above.
  config :web, Web.Mailer,
    adapter: Swoosh.Adapters.Resend,
    api_key:
      System.get_env("RESEND_API_KEY") ||
        raise("""
        environment variable RESEND_API_KEY is missing.
        This sends subscriber welcome mail and the newsletter.
        Issue one at https://resend.com/api-keys
        """)
end
