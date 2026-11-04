defmodule Web.Rides.Power do
  @moduledoc """
  Each ride's estimated power, worked out in R (`analysis/ride_power.R`) and
  only read here.

  There is no power meter on the bike: the script puts the rider's speed and
  climb (`Web.Rides.Profile`, else the ride's totals) through the physics of
  riding a bicycle (air, tyres, drivetrain, gravity) and says how many watts
  that took. Wind and drafting are unknown to it, so every figure it gives is
  shown as an estimate.

  The script reads the database read-only, the rider's bodyweight from the
  check-ins, and the bike's settings from `content/fitness/bike.json`
  (private: masses, air and rolling resistance per Komoot sport). It writes
  one JSON file beside the uploads root (never under it), which
  `for_ride/1` reads, kept in memory until the file changes.

  It runs after a Komoot pass that brought in or changed a ride
  (`Web.Rides.KomootSync.run_scheduled/0`), every night, and by hand:

      Rscript analysis/ride_power.R --db DB --settings content/fitness/bike.json --out FILE

  A machine without R estimates nothing, and the pages show no power.
  Configure with `:rscript_bin` (`Rscript` on the PATH), `:fitness_scripts_path`
  and `:ride_power_path`.
  """
  require Logger

  def path do
    Application.get_env(:web, :ride_power_path) ||
      Web.Uploads.root() |> Path.expand() |> Path.dirname() |> Path.join("ride-power.json")
  end

  defp scripts, do: Application.get_env(:web, :fitness_scripts_path) || Path.expand("analysis")
  defp rscript, do: Application.get_env(:web, :rscript_bin) || "Rscript"
  defp settings, do: Path.join(Web.Fitness.Vault.base_path(), "bike.json")

  defp database,
    do: Application.get_env(:web, Web.Repo)[:database] |> to_string() |> Path.expand()

  @doc "The Quantum entry, and what a Komoot pass that changed something starts."
  def run_scheduled do
    case run() do
      {:ok, count} -> Logger.info("ride power: #{count} rides estimated")
      {:error, reason} -> Logger.warning("ride power: #{inspect(reason)}")
    end

    :ok
  end

  @doc """
  Runs the script: `{:ok, rides estimated}` or `{:error, reason}`. Never
  raises. One run at a time: a second while one runs is `{:error, :busy}`.
  """
  def run do
    :global.trans({__MODULE__, :run}, &do_run/0, [node()], 0) || {:error, :busy}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp do_run do
    script = Path.join(scripts(), "ride_power.R")
    out = path()
    partial = out <> ".partial"

    with true <- File.regular?(script) || {:error, :no_script},
         :ok <- File.mkdir_p(Path.dirname(out)),
         {_, 0} <-
           System.cmd(
             rscript(),
             [script, "--db", database(), "--settings", settings(), "--out", partial],
             stderr_to_stdout: true,
             cd: scripts()
           ),
         {:ok, %{"rides" => rides}} <- read(partial) do
      File.rename!(partial, out)
      {:ok, length(rides)}
    else
      {output, status} when is_integer(status) ->
        File.rm(partial)
        {:error, {:rscript, status, String.slice(output, -600, 600)}}

      error ->
        File.rm(partial)
        if match?({:error, _}, error), do: error, else: {:error, error}
    end
  catch
    :exit, {:enoent, _} -> {:error, :no_rscript}
  end

  @doc """
  What the script estimated for a ride, or nil: `%{"avg_w" => watts while
  moving, "work_kj" => the work done, "basis" => "profile" | "totals", ...}`.
  """
  def for_ride(%{id: id}), do: Map.get(estimates(), id)
  def for_ride(_), do: nil

  @doc "The model and settings the estimates were made with, or nil."
  def model, do: estimates_file()[:model]

  defp estimates, do: estimates_file()[:rides] || %{}

  # Read once per change of the file, by its modification time and size (two
  # runs in one second share a modification time).
  defp estimates_file do
    file = path()

    case File.stat(file, time: :posix) do
      {:ok, %{mtime: mtime, size: size}} ->
        case :persistent_term.get({__MODULE__, file}, nil) do
          {{^mtime, ^size}, cached} ->
            cached

          _ ->
            cached = load(file)
            :persistent_term.put({__MODULE__, file}, {{mtime, size}, cached})
            cached
        end

      _ ->
        %{}
    end
  end

  defp load(file) do
    case read(file) do
      {:ok, %{"rides" => rides} = all} ->
        %{
          rides: Map.new(for(%{"id" => id} = ride <- rides, is_integer(id), do: {id, ride})),
          model: Map.get(all, "model")
        }

      _ ->
        %{}
    end
  end

  defp read(file) do
    with {:ok, body} <- File.read(file), do: Jason.decode(body)
  end
end
