defmodule WebWeb.HealthExportWriter do
  @moduledoc """
  Writes an uploading Apple Health export straight into the import's inbox
  (`Web.Rides.HealthImport.reserve!/0`) rather than LiveView's temp file.

  The default writer puts an upload in `/tmp`, which every account on the
  machine can list and which here is memory, so a few hundred megabytes of
  export would sit in RAM, in a shared place, to be copied out again. This
  one writes the chunks where the import will read them, in a folder only
  this user can open.

  An upload that is cancelled, or fails part-way, takes its file with it.
  One that completes is left for `Web.Rides.HealthImport.start/1`, which
  deletes it when it has been read.
  """

  @behaviour Phoenix.LiveView.UploadWriter

  alias Web.Rides.HealthImport

  @impl true
  def init(_opts) do
    path = HealthImport.reserve!()

    with {:ok, file} <- File.open(path, [:binary, :append]) do
      {:ok, %{path: path, file: file}}
    end
  end

  @impl true
  def meta(state), do: %{path: state.path}

  @impl true
  def write_chunk(data, state) do
    case IO.binwrite(state.file, data) do
      :ok -> {:ok, state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  @impl true
  def close(state, reason) do
    File.close(state.file)
    if reason != :done, do: File.rm(state.path)
    {:ok, state}
  end
end
