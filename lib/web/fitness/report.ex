defmodule Web.Fitness.Report do
  @moduledoc """
  The weekly training report: `analysis/fitness_report.qmd` (Quarto and R;
  the block's Stage 0 models in `analysis/fitness_models.R`) rendered to one
  self-contained page, kept in `fitness-reports/<YYYY-MM-DD>.html` beside
  the uploads root (never under it: the proxy serves that), and shown to
  the admin at `/admin/fitness/report` (`WebWeb.FitnessReportController`).

  It renders every Sunday evening (`config/config.exs`) and on demand from
  the block report. The training log and the check-ins are written for it
  by `Web.Fitness.Export` first; the rides are read from the database
  read-only. The scripts are in the repository's `analysis/` folder; a
  machine without Quarto (or R) renders nothing and says why.

  Configure with `:quarto_bin` (`quarto` on the PATH), `:fitness_scripts_path`
  (`analysis` in the working directory) and `:fitness_reports_path`.
  """

  require Logger

  alias Web.Fitness
  alias Web.Fitness.{Checks, Export}

  @name ~r/\A\d{4}-\d{2}-\d{2}\.html\z/

  def dir do
    Application.get_env(:web, :fitness_reports_path) ||
      Web.Uploads.root() |> Path.expand() |> Path.dirname() |> Path.join("fitness-reports")
  end

  defp scripts, do: Application.get_env(:web, :fitness_scripts_path) || Path.expand("analysis")
  defp quarto, do: Application.get_env(:web, :quarto_bin) || "quarto"

  @doc "The Quantum entry."
  def run_scheduled do
    case render(Web.Clock.local_today()) do
      {:ok, path} -> Logger.info("fitness report: #{path}")
      {:error, reason} -> Logger.warning("fitness report: #{inspect(reason)}")
    end
  end

  @doc """
  Renders the report for a day: `{:ok, path}` or `{:error, reason}`. Never
  raises. One render at a time: a second while one runs is `:busy`.
  """
  def render(%Date{} = date) do
    :global.trans({__MODULE__, :render}, fn -> do_render(date) end, [node()], 0) ||
      {:error, :busy}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp do_render(date) do
    qmd = Path.join(scripts(), "fitness_report.qmd")

    with true <- File.regular?(qmd) || {:error, :no_report_script},
         :ok <- mkdir_private(dir()),
         data = Path.join(dir(), ".data"),
         :ok <- mkdir_private(data),
         :ok <-
           File.write(
             Path.join(data, "fitness_logs.csv"),
             Export.logs_csv(Fitness.list_exercise_logs())
           ),
         :ok <-
           File.write(
             Path.join(data, "fitness_checkins.csv"),
             Export.checkins_csv(Fitness.checkins_between(~D[2000-01-01], date), Checks.all())
           ),
         out = Path.join(dir(), ".render"),
         _ = File.rm_rf(out),
         {_, 0} <-
           System.cmd(
             quarto(),
             [
               "render",
               qmd,
               "--output-dir",
               out,
               "-P",
               "csv:" <> Path.join(data, "fitness_logs.csv"),
               "-P",
               "db:" <> database(),
               "-P",
               "block:" <> block_file(date)
             ],
             stderr_to_stdout: true,
             cd: scripts()
           ),
         [html] <- Path.wildcard(Path.join(out, "*.html")) do
      target = Path.join(dir(), Date.to_iso8601(date) <> ".html")
      :ok = File.rename(html, target)
      File.chmod(target, 0o600)
      File.rm_rf(out)
      {:ok, target}
    else
      {:error, _} = error ->
        error

      {output, status} when is_integer(status) ->
        {:error, {:quarto, status, String.slice(output, -600, 600)}}

      other ->
        {:error, other}
    end
  catch
    :exit, {:enoent, _} -> {:error, :no_quarto}
  end

  @doc "The rendered reports, newest first, as dates."
  def list do
    case File.ls(dir()) do
      {:ok, names} ->
        for name <- names,
            Regex.match?(@name, name),
            {:ok, date} <- [Date.from_iso8601(Path.rootname(name))] do
          date
        end
        |> Enum.sort({:desc, Date})

      _ ->
        []
    end
  end

  @doc "A rendered report's path from its date (a URL part), or `:error`."
  def path(date) when is_binary(date) do
    with {:ok, _} <- Date.from_iso8601(date),
         path = Path.join(dir(), date <> ".html"),
         true <- File.regular?(path) do
      {:ok, path}
    else
      _ -> :error
    end
  end

  def path(_), do: :error

  # The block the report is about: the one running on the day, else the
  # last one to have run. Its file, whatever it is named.
  defp block_file(date) do
    case Fitness.Block.latest(date) do
      %{slug: slug} -> Path.join([Fitness.Vault.base_path(), "blocks", slug <> ".md"])
      nil -> ""
    end
  end

  # The report reads the rides from the live database, read-only.
  defp database,
    do: Application.get_env(:web, Web.Repo)[:database] |> to_string() |> Path.expand()

  defp mkdir_private(path), do: with(:ok <- File.mkdir_p(path), do: File.chmod(path, 0o700))
end
