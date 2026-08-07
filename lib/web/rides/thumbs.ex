defmodule Web.Rides.Thumbs do
  @moduledoc """
  Local cache of Komoot static-map thumbnails, one JPEG per ride. Komoot's
  image URLs are signed and expire, and hotlinking would leak visitor IPs,
  so the sync downloads them once and the site serves the copies.
  """

  require Logger

  @default_dir "priv/ride_thumbs"

  def dir, do: Application.get_env(:web, :ride_thumbs_path, @default_dir)

  def path(%{id: id}), do: Path.join(dir(), "#{id}.jpg")

  def exists?(ride), do: File.regular?(path(ride))

  def store(ride, binary) do
    File.mkdir_p!(dir())
    File.write!(path(ride), binary)
    :ok
  rescue
    error ->
      Logger.warning(
        "ride thumbnail write failed for ride #{ride.id}: #{Exception.message(error)}"
      )

      :error
  end

  def delete(ride) do
    File.rm(path(ride))
    :ok
  end
end
