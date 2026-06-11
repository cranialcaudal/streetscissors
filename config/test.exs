import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :web, Web.Repo,
  database: Path.expand("../web_test.db", __DIR__),
  pool_size: 5,
  pool: Ecto.Adapters.SQL.Sandbox

# Oban runs no queues, plugins, or notifier during tests; enqueue jobs are
# asserted manually instead of executed against the Ecto sandbox.
config :web, Oban, testing: :manual

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :web, WebWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "L2k6+BXcCQXlci+Mgg27BZbBeMjj1pnRbcgaH5EFU7wljDApESM0C5E8c8ATe602",
  server: false

# In test we don't send emails
config :web, Web.Mailer, adapter: Swoosh.Adapters.Test

# Admin dashboard password used in tests
config :web, :admin_password, "test-admin"

# Komoot auto-sync: fake credentials + Req.Test stub for the HTTP layer
config :web, :komoot, email: "test@example.com", password: "test-password"
config :web, :komoot_req_options, plug: {Req.Test, Web.Komoot.Client}

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
