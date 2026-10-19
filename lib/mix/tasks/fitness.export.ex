defmodule Mix.Tasks.Fitness.Export do
  @shortdoc "Writes the training log and check-ins as CSV for R"

  @moduledoc """
  Writes `fitness_logs.csv` and `fitness_checkins.csv` (`Web.Fitness.Export`)
  into a folder, for `scripts/fitness_models.R` and the Quarto report, with
  no browser and no cookie.

      mix fitness.export                       # ./tmp/fitness, the dev database
      mix fitness.export DIR --db PATH         # another database, read-only

  This machine is the server too, so the task **never boots the site**: it
  starts the Repo alone, and with `--db` opens that file read-only, which is
  safe beside the running release (the live file is `DATABASE_PATH` in the
  unit).
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

    if db = opts[:db] do
      db = Path.expand(db)
      File.regular?(db) || Mix.raise("no database at #{db}")
      config = Application.get_env(:web, Web.Repo)

      Application.put_env(
        :web,
        Web.Repo,
        Keyword.merge(config, database: db, mode: :readonly, pool_size: 1)
      )
    end

    {:ok, _} = Application.ensure_all_started(:ecto_sql)
    {:ok, _} = Application.ensure_all_started(:ecto_sqlite3)
    {:ok, _} = Web.Repo.start_link()

    File.mkdir_p!(dir)
    logs = Fitness.list_exercise_logs()
    checkins = checkins()

    File.write!(Path.join(dir, "fitness_logs.csv"), Fitness.Export.logs_csv(logs))
    File.write!(Path.join(dir, "fitness_checkins.csv"), Fitness.Export.checkins_csv(checkins))

    Mix.shell().info(
      "#{length(logs)} entries and #{length(checkins)} check-ins written to #{dir}"
    )
  end

  # A database from before the check-ins' migration has no table for them.
  defp checkins do
    Web.Repo.all(Fitness.Checkin)
  rescue
    Exqlite.Error -> []
  end
end
