defmodule Web.Rides.Thumbs do
  @moduledoc """
  Local cache of Komoot static-map thumbnails, one JPEG per ride. Hotlinking
  would leak visitor IPs to Komoot's CDN, so the sync downloads each image
  once and the site serves the copy.

  The image URL encodes the route's own polyline and the CDN answers
  `cache-control: max-age=86400, public, immutable` with no ETag — so a URL
  that has not changed cannot return different bytes, and the sync skips the
  download entirely rather than re-fetching on every metadata edit.
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
