defmodule Web.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WebWeb.Telemetry,
      Web.Repo,
      {Ecto.Migrator, repos: Application.fetch_env!(:web, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:web, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Web.PubSub},
      # Finch for Swoosh (email sending via HTTP APIs like Resend)
      {Finch, name: Swoosh.Finch},
      # Start a worker by calling: Web.Worker.start_link(arg)
      # {Web.Worker, arg},
      {Task.Supervisor, name: Web.TaskSupervisor},
      # Owns the ETS table guarding login attempts, subscribe/guestbook/contact
      # writes and the LanguageTool relay. Must start before the Endpoint.
      Web.RateLimit,
      # Oban background job processing (mailers queue). Must start after Repo.
      {Oban, Application.fetch_env!(:web, Oban)},

      # Quantum scheduled (cron) jobs
      Web.Scheduler,
      # Catch up a backup the schedule slept through. Quantum does not make up
      # missed runs, so on a laptop every night the lid is closed produces
      # nothing at all. Temporary child: it runs once, then exits normally and
      # is not restarted. After Repo (it needs a connection), and it must not
      # delay the Endpoint — the task returns immediately and works in its own
      # process.
      {Task, &Web.Backup.run_on_boot/0},
      # Backs the site up onto the external drive as soon as it is plugged in,
      # rather than waiting for the next scheduled run. Returns :ignore when no
      # mirror is configured, so it costs nothing on a checkout that is not the
      # server.
      Web.Backup.MirrorWatcher,
      # Start to serve requests, typically the last entry
      WebWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Web.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    WebWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
