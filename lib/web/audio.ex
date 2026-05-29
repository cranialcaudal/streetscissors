defmodule Web.Audio do
  import Ecto.Query, warn: false
  alias Web.Repo
  alias Web.Audio.Log
  alias Web.Audio.Play

  def list_logs do
    Repo.all(from l in Log, order_by: [desc: l.inserted_at])
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

  def delete_log(%Log{} = log) do
    Repo.delete(log)
  end

  def change_log(%Log{} = log, attrs \\ %{}) do
    Log.changeset(log, attrs)
  end

  # --- Play Tracking ---

  @doc """
  Records a play event for an audio log.
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
