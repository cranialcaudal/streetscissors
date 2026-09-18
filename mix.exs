defmodule Web.MixProject do
  use Mix.Project

  def project do
    [
      app: :web,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      releases: releases()
    ]
  end

  # The production artifact. `mix release` would work without this block, but
  # naming it pins the path the systemd unit and start_prod.sh both point at:
  # _build/prod/rel/web/bin/web.
  #
  # Note that a release ships priv/ *inside itself* and replaces it wholesale on
  # every build. Anything the application writes at runtime therefore has to
  # live outside it — see UPLOADS_PATH and RIDE_THUMBS_PATH in config/runtime.exs.
  defp releases do
    [
      web: [
        include_executables_for: [:unix],
        applications: [runtime_tools: :permanent]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Web.Application, []},
      extra_applications: [:logger, :runtime_tools, :quantum]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.3"},
      {:phoenix_ecto, "~> 4.5"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, ">= 0.0.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"},
      {:earmark, "~> 1.4"},
      {:quantum, "~> 3.0"},
      {:castore, ">= 0.0.0"},
      {:oban, "~> 2.17"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  # esbuild names split chunks by content hash and never deletes the ones it
  # has stopped emitting, so a dev build's unminified chunks sit in
  # priv/static until something removes them — and `mix release` packages
  # priv/ wholesale. That shipped 4 MB of dead JavaScript, twice, before this
  # existed.
  #
  # Only chunks are pruned, and only ones the freshly built app.js does not
  # import. app.js keeps its own previous digested copies, which is the grace
  # `phx.digest.clean --keep 1` in redeploy.sh relies on.
  defp prune_stale_chunks(_args) do
    dir = Path.join(~w(priv static assets js))
    entry = Path.join(dir, "app.js")

    if File.regular?(entry) do
      imported =
        ~r/["']\.\/([\w.\-]+\.js)["']/
        |> Regex.scan(File.read!(entry))
        |> MapSet.new(fn [_whole, name] -> name end)

      for name <- File.ls!(dir), chunk?(name), not MapSet.member?(imported, name) do
        # The chunk and any digested or gzipped copy of it.
        [Path.join(dir, name) | Path.wildcard(Path.join(dir, Path.rootname(name) <> "-*"))]
        |> Enum.each(&File.rm/1)

        File.rm(Path.join(dir, name <> ".gz"))
        Mix.shell().info("pruned stale chunk #{name}")
      end
    end

    :ok
  end

  # An esbuild chunk ends in its own 8-character hash. A phx.digest copy ends
  # in 32 lowercase hex, so this never matches one of those.
  defp chunk?(name) do
    name != "app.js" and Regex.match?(~r/-[A-Z0-9]{8}\.js$/, name)
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind web", "esbuild web"],
      # Compile first: colocated hooks are extracted during compilation, and
      # esbuild can only bundle the ones that already exist on disk.
      "assets.deploy": [
        "compile",
        "tailwind web --minify",
        "esbuild web --minify",
        &prune_stale_chunks/1,
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end
