defmodule Web.Release do
  @moduledoc """
  Database migrations for the compiled release, which has no `mix`. The live
  site normally migrates itself at start-up (`Ecto.Migrator` in
  `Web.Application`); these are for doing it by hand:

      _build/prod/rel/web/bin/web eval "Web.Release.migrate()"
      _build/prod/rel/web/bin/web eval "Web.Release.rollback(Web.Repo, 20260101000000)"

  Rolling back undoes migrations newer than the version given. Copy the
  database first (the manual's Part 6, "Migrations").
  """

  @app :web

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
