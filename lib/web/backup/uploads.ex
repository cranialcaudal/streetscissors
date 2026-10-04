defmodule Web.Backup.Uploads do
  @moduledoc """
  Copies the captain's logs' media onto the external drive.

  A recording's source is deleted once it has been transcoded (`Web.Media`), so
  the rendition under the uploads root is the only copy of that recording
  there is. The database snapshot holds the entry's row and nothing of its
  sound or picture; without this, one failed disk would leave every log a
  title over a missing file.

  The copy is `Web.Backup.Tree`'s: rsync, incremental, and with no `--delete`.
  A re-transcode writes a new directory and drops the old one, so the mirror
  keeps both — the same accumulation the negatives' mirror has, and the reason
  a deletion made by mistake is still recoverable from the drive.

  `staging/` is left behind. It holds uploads that are still arriving or still
  waiting on ffmpeg: large, short-lived, and re-made if the take is recorded
  again. Copying them would leave every raw take on the drive for good.
  `cards/` is left behind too: `Web.ShareCard` redraws those from the work.

  Configure with `:uploads_mirror_path`; `nil` disables it. The folder is made
  on first use if the folder it sits in is there (`Web.Backup.claim_mirror/1`),
  and never otherwise.
  """

  require Logger

  alias Web.Backup
  alias Web.Backup.Tree

  @doc "The configured destination, or `nil`. Empty string counts as unset."
  @spec mirror_dir() :: String.t() | nil
  def mirror_dir do
    case Application.get_env(:web, :uploads_mirror_path) do
      nil -> nil
      "" -> nil
      dir -> dir
    end
  end

  @doc "True when a destination is configured and its drive is there."
  @spec available?() :: boolean()
  def available?, do: Backup.mirror_reachable?(mirror_dir())

  @doc """
  Syncs the uploads root to the mirror.

  Returns `{:ok, summary}` with file counts, `:skipped` when the destination is
  unconfigured or absent, or `{:error, reason}`. Never raises — a backup problem
  must not take down the caller, which is a supervised watcher process.
  """
  @spec sync() :: {:ok, map()} | :skipped | {:error, term()}
  def sync do
    source = Web.Uploads.root()

    case Backup.claim_mirror(mirror_dir()) do
      :absent ->
        :skipped

      {:ok, dest} ->
        if File.dir?(source) do
          Tree.sync(source, dest, label: "recordings", exclude: ["/staging/", "/cards/"])
        else
          {:error, {:source_missing, source}}
        end
    end
  rescue
    error ->
      Logger.error("recordings backup crashed: #{Exception.message(error)}")
      {:error, error}
  end
end
