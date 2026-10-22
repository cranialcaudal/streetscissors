defmodule Mix.Tasks.Fitness.Export do
  @shortdoc "Writes the training log and check-ins as CSV for R"

  @moduledoc """
  Writes `fitness_logs.csv`, `fitness_checkins.csv` and `fitness_rides.csv`
  (`Web.Fitness.Export`) into a folder, for `analysis/fitness_models.R` and the
  Quarto report, with no browser and no cookie. The rides file is the Komoot
  activities, which stand for the cycling stats.

      mix fitness.export --db PATH             # into ./tmp/fitness
      mix fitness.export DIR --db PATH

  `--db` is required: left to the config, the task read the development
  database, which on this machine is nearly empty, and wrote a CSV that looked
  like a training log with nothing in it. Name the file you mean (the live one
  is `DATABASE_PATH` in the unit).

  This machine is the server too, so the task **never boots the site**: it
  starts the Repo alone and opens the file read-only, which is safe beside the
  running release.
  """
  use Mix.Task

  require Logger

  alias Web.Fitness

  @impl true
  def run(args) do
    {opts, rest, _} = OptionParser.parse(args, strict: [db: :string])
    dir = Path.expand(List.first(rest) || "tmp/fitness")

    Mix.Task.run("app.config")
    Logger.configure(level: :info)

    db = Path.expand(opts[:db] || Mix.raise("which database? mix fitness.export --db PATH"))
    File.regular?(db) || Mix.raise("no database at #{db}")
    config = Application.get_env(:web, Web.Repo)

    Application.put_env(
      :web,
      Web.Repo,
      Keyword.merge(config, database: db, mode: :readonly, pool_size: 1)
    )

    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:ecto_sqlite3)
    {:ok, _} = Web.Repo.start_link()

    File.mkdir_p!(dir)
    logs = Fitness.list_exercise_logs()
    checkins = checkins()

    File.write!(Path.join(dir, "fitness_logs.csv"), Fitness.Export.logs_csv(logs))

    File.write!(
      Path.join(dir, "fitness_checkins.csv"),
      Fitness.Export.checkins_csv(checkins, Fitness.Checks.all())
    )

    rides = rides()
    File.write!(Path.join(dir, "fitness_rides.csv"), Fitness.Export.rides_csv(rides))

    Mix.shell().info(
      "#{length(logs)} entries, #{length(checkins)} check-ins and #{length(rides)} rides written to #{dir}"
    )
  end

  # A database from before the rides' migration has no table for them.
  defp rides do
    Web.Rides.list_rides()
  rescue
    Exqlite.Error -> []
  end

  # A database from before the check-ins' migration has no table for them.
  defp checkins do
    Web.Repo.all(Fitness.Checkin)
  rescue
    Exqlite.Error -> []
  end
end
