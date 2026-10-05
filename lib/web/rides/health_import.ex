defmodule Web.Rides.HealthImport do
  @moduledoc """
  Runs an Apple Health import in the background and remembers how it went.

  An export is hundreds of megabytes and takes the better part of a minute
  to read, which is too long to hold a page open for and too long to tie to
  the browser tab that started it. `start/1` hands the file to a supervised
  task and returns at once; the task reads it
  (`Web.Rides.import_health_export/1`), **deletes it whatever happens** —
  it is the most personal file the site is ever handed, and it is wanted for
  exactly as long as it takes to read — and leaves the outcome in one
  `site_settings` row. The admin's page hears about it on `"rides:health"`.

  **The file waits somewhere nothing serves.** An upload is written straight
  into an inbox (`reserve!/0`, by `WebWeb.HealthExportWriter`) that sits
  beside the uploads root, not inside it: everything under `uploads/` is
  handed out by the proxy to anyone who knows its name, and `/tmp`, where an
  upload would otherwise land, is shared and on this machine is memory. The
  inbox is this user's alone, and so is each file in it.

  **Only one import runs at a time**, and the import is whichever process
  holds this module's name. That makes "is one running" a question the VM
  answers rather than a row: the name is free again the moment the process
  ends, however it ends. A record still saying "running" with nobody holding
  the name belongs to an import that a restart interrupted; it is read as a
  failure, and `clear_inbox/0` removes the file it left when the site boots.
  """

  require Logger

  alias Web.Rides
  alias Web.SiteSettings

  @setting "health_import"
  @topic "rides:health"

  def subscribe, do: Phoenix.PubSub.subscribe(Web.PubSub, @topic)

  @doc "Where an export waits to be read: beside the uploads root, never under it."
  def inbox do
    Application.get_env(:web, :health_inbox_path) ||
      Path.join(Path.dirname(Path.expand(Web.Uploads.root())), "health-inbox")
  end

  @doc """
  Makes an empty file in the inbox for an export to be written into, readable
  by this user alone, and returns where it is.
  """
  def reserve! do
    File.mkdir_p!(inbox())
    File.chmod!(inbox(), 0o700)
    path = Path.join(inbox(), Base.encode16(:crypto.strong_rand_bytes(8), case: :lower))
    File.write!(path, "")
    File.chmod!(path, 0o600)
    path
  end

  @doc """
  Empties the inbox. Run at boot, when nothing can be reading from it: an
  import cut short by a restart never reached the line that deletes its file.
  Always `:ok`.
  """
  def clear_inbox do
    with {:ok, files} <- File.ls(inbox()) do
      for file <- files, do: File.rm(Path.join(inbox(), file))
    end

    :ok
  end

  @doc """
  Starts importing the export at `path`, which is deleted when the import
  ends. `{:error, :running}` when one is already under way — the file is
  deleted in that case too, since nothing will read it.
  """
  def start(path) do
    # The task waits to be told to read, so the name is claimed and the
    # record written before anything can finish and broadcast.
    {:ok, pid} =
      Task.Supervisor.start_child(Web.TaskSupervisor, fn ->
        receive do
          :read -> read(path)
        end
      end)

    if claim(pid) do
      record(%{"status" => "running"})
      send(pid, :read)
      :ok
    else
      Process.exit(pid, :kill)
      File.rm(path)
      {:error, :running}
    end
  end

  defp claim(pid) do
    Process.register(pid, __MODULE__)
  rescue
    # The name is taken: an import is running.
    ArgumentError -> false
  end

  defp read(path) do
    outcome =
      try do
        Rides.import_health_export(path)
      rescue
        error -> {:error, Exception.message(error)}
      after
        File.rm(path)
      end

    finish(outcome)
  end

  @doc """
  The last import: `%{status: :running | :ok | :failed, at: DateTime, …}` with
  the summary's counts when it succeeded and `reason` when it did not, or nil
  if there has never been one.
  """
  def last do
    with json when is_binary(json) <- SiteSettings.get_setting(@setting),
         {:ok, %{"status" => status, "at" => at} = record} <- Jason.decode(json),
         {:ok, at, _offset} <- DateTime.from_iso8601(at) do
      case status do
        "running" ->
          if running?(),
            do: %{status: :running, at: at},
            else: %{status: :failed, at: at, reason: "it was interrupted before it finished"}

        "ok" ->
          %{
            status: :ok,
            at: at,
            in_export: record["in_export"],
            matched: record["matched"],
            heart_samples: record["heart_samples"]
          }

        _failed ->
          %{status: :failed, at: at, reason: record["reason"]}
      end
    else
      _ -> nil
    end
  end

  @doc "True while an import is being read."
  def running?, do: Process.whereis(__MODULE__) != nil

  defp finish({:ok, summary}) do
    Logger.info("Apple Health import: #{inspect(summary)}")

    record(%{
      "status" => "ok",
      "in_export" => summary.in_export,
      "matched" => summary.matched,
      "heart_samples" => summary.heart_samples
    })
  end

  defp finish({:error, reason}) do
    Logger.warning("Apple Health import failed: #{inspect(reason)}")
    record(%{"status" => "failed", "reason" => explain(reason)})
  end

  defp record(fields) do
    now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    SiteSettings.put_setting(@setting, Jason.encode!(Map.put(fields, "at", now)))
    Phoenix.PubSub.broadcast(Web.PubSub, @topic, :health_import)
    :ok
  end

  defp explain(:not_an_export),
    do: "that is not an Apple Health export (it holds no HealthData)"

  defp explain(:no_export_in_zip), do: "the zip has no export.xml in it"
  defp explain(:unzip_missing), do: "this machine has no unzip to open the archive with"
  defp explain({:unzip, status}), do: "the archive could not be read (unzip exited #{status})"
  defp explain(:unzip_stalled), do: "the archive stopped yielding data"
  defp explain(reason) when is_binary(reason), do: reason
  defp explain(reason), do: inspect(reason)
end
