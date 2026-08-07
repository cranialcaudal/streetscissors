defmodule Web.Audio do
  @moduledoc """
  Context for the captain's logs: spoken pieces, each with its own address at
  `/logs/:slug`. Independent of `Web.Blog`, which is strictly typed work.

  This context owns where log audio lands on disk (`Web.Uploads`), so
  creating and deleting a log keeps the row and the file in step.
  """

  import Ecto.Query, warn: false
  alias Web.Keywords
  alias Web.Repo
  alias Web.Audio.Log
  alias Web.Audio.Play

  @uploads_subdir "logs"

  def list_logs do
    Repo.all(from l in Log, order_by: [desc: l.recorded_on, desc: l.inserted_at])
  end

  @doc """
  Published logs only, newest recording first — what `/logs` renders.
  """
  def list_published_logs do
    Repo.all(
      from l in Log,
        where: l.published == true,
        order_by: [desc: l.recorded_on, desc: l.inserted_at]
    )
  end

  @doc """
  Fetches one published log by its slug. Unpublished logs are invisible here
  so a draft's URL 404s rather than leaking.
  """
  def get_published_log_by_slug(slug) do
    case Repo.one(from l in Log, where: l.slug == ^slug and l.published == true) do
      nil -> {:error, :not_found}
      log -> {:ok, log}
    end
  end

  @doc """
  Every keyword in use across published logs, most-used first. Powers the
  filter bar on `/logs`.
  """
  def list_keywords do
    list_published_logs() |> Enum.map(&Log.keyword_list/1) |> Keywords.tally()
  end

  def get_log!(id), do: Repo.get!(Log, id)

  def create_log(attrs \\ %{}) do
    %Log{}
    |> Log.changeset(attrs)
    |> Repo.insert()
  end

  def update_log(%Log{} = log, attrs) do
    log
    |> Log.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a log and the audio file it owns, so purging from the admin does
  not leave the upload orphaned on disk forever.
  """
  def delete_log(%Log{} = log) do
    with {:ok, deleted} <- Repo.delete(log) do
      delete_upload(deleted.file_path)
      {:ok, deleted}
    end
  end

  def change_log(%Log{} = log, attrs \\ %{}) do
    Log.changeset(log, attrs)
  end

  @doc """
  Copies a freshly uploaded file into the logs upload directory under a
  collision-proof name and returns the public URL it will be served at
  (by `WebWeb.Plugs.MediaServe`, which supports range requests so listeners
  can seek).
  """
  def store_upload(source_path, client_name) do
    ext = client_name |> Path.extname() |> String.downcase()

    base =
      case client_name |> Path.basename(ext) |> Keywords.slugify() do
        "" -> "log"
        slug -> slug
      end

    filename = "#{base}-#{System.unique_integer([:positive])}#{ext}"
    dir = Web.Uploads.dir(@uploads_subdir)

    File.mkdir_p!(dir)
    File.cp!(source_path, Path.join(dir, filename))

    Web.Uploads.web_path(@uploads_subdir, filename)
  end

  @doc """
  Removes a stored upload. Only ever deletes a file this context wrote — the
  path has to sit directly inside the logs upload dir — so a hand-edited
  `file_path` cannot be turned into an arbitrary delete.

  Used to clean up when a log fails to insert after its file was already
  copied into place, so a rejected save leaves nothing behind.
  """
  def discard_upload(web_path), do: delete_upload(web_path)

  defp delete_upload(nil), do: :ok

  defp delete_upload(web_path) do
    prefix = Web.Uploads.web_path(@uploads_subdir, "")

    if String.starts_with?(web_path, prefix) do
      case web_path |> Path.basename() |> Path.safe_relative() do
        {:ok, name} -> File.rm(Path.join(Web.Uploads.dir(@uploads_subdir), name))
        :error -> :ok
      end
    end

    :ok
  end

  # --- Play Tracking ---

  @doc """
  Records a play event for an audio log. This is the "witnessed" count for a
  log — the hook fires on the audio element's `play` event, once per mount,
  so seeking does not inflate it.
  """
  def record_play(audio_log_id, ip_address, user_agent \\ nil) do
    %Play{}
    |> Play.changeset(%{
      audio_log_id: audio_log_id,
      ip_address: ip_address,
      user_agent: user_agent
    })
    |> Repo.insert()
  end

  @doc """
  Gets the total play count for a specific audio log.
  """
  def get_play_count(audio_log_id) do
    Repo.one(from p in Play, where: p.audio_log_id == ^audio_log_id, select: count(p.id)) || 0
  end

  @doc """
  Gets play counts for all audio logs as a map of {audio_log_id => count}.
  """
  def get_all_play_counts do
    Repo.all(
      from p in Play,
        group_by: p.audio_log_id,
        select: {p.audio_log_id, count(p.id)}
    )
    |> Map.new()
  end

  @doc """
  Lists all plays for a specific audio log.
  """
  def list_plays_for_log(audio_log_id) do
    Repo.all(
      from p in Play,
        where: p.audio_log_id == ^audio_log_id,
        order_by: [desc: p.inserted_at]
    )
  end

  @doc """
  Gets all plays with location data for map visualization.
  """
  def get_plays_with_location do
    Repo.all(
      from p in Play,
        where: not is_nil(p.latitude) and not is_nil(p.longitude),
        preload: [:audio_log],
        order_by: [desc: p.inserted_at]
    )
  end

  @doc """
  Gets unique IP addresses and their play counts.
  """
  def get_unique_listeners do
    Repo.all(
      from p in Play,
        group_by: p.ip_address,
        select: {p.ip_address, count(p.id)},
        order_by: [desc: count(p.id)]
    )
  end

  @doc """
  Updates a play record with geolocation data.
  """
  def update_play_location(play_id, location_data) do
    play = Repo.get!(Play, play_id)

    play
    |> Play.changeset(location_data)
    |> Repo.update()
  end
end
