# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :web,
  ecto_repos: [Web.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :web, WebWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: WebWeb.ErrorHTML, json: WebWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Web.PubSub,
  live_view: [signing_salt: "j8lP5Vig"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :web, Web.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  web: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  web: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :web, Web.Scheduler,
  jobs: [
    # Run every Sunday at 8:23 PM (20:23)
    {"23 20 * * 0", {Web.Newsletter.Generator, :generate_weekly_draft, []}}
  ]

config :web, Oban,
  repo: Web.Repo,
  plugins: [Oban.Plugins.Pruner],
  queues: [default: 10, mailers: 20],
  notifier: Oban.Notifiers.Poll

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
