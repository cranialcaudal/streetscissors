defmodule Web.Rides.Thumbs do
  @moduledoc """
  Local cache of Komoot static-map thumbnails, one JPEG per ride. Hotlinking
  would leak visitor IPs to Komoot's CDN, so the sync downloads each image
  once and the site serves the copy.

  **A thumbnail is named for the URL it came from**: `<ride id>-<hash>.jpg`,
  the hash taken over `map_image_url`. That URL encodes the route's own
  polyline, so it changes exactly when the picture would — and it is the
  stranger's URL, with Komoot's privacy zones already cut out of the route.
  Naming the file for it means a picture fetched from any other URL can never
  be served for the ride: not one left over from before the route was
  re-cut, and not one of the whole-route images an earlier version of the
  site cached under the bare ride id. `sweep/1` deletes those.

  The CDN answers `cache-control: max-age=86400, public, immutable` with no
  ETag, so a URL that has not changed cannot return different bytes, and the
  sync skips the download entirely rather than re-fetching on every edit.
  """

  require Logger

  @default_dir "priv/ride_thumbs"

  def dir, do: Application.get_env(:web, :ride_thumbs_path, @default_dir)

  @doc "Where the ride's thumbnail is kept, or nil when it has no map to cache."
  def path(%{id: id, map_image_url: url}) when is_binary(url) and url != "" do
    Path.join(dir(), "#{id}-#{fingerprint(url)}.jpg")
  end

  def path(_ride), do: nil

  @doc "A short, stable name for a map URL: changes when the map does."
  def fingerprint(url) do
    :sha256 |> :crypto.hash(url) |> Base.encode16(case: :lower) |> binary_part(0, 12)
  end

  def exists?(ride) do
    case path(ride) do
      nil -> false
      path -> File.regular?(path)
    end
  end

  def store(ride, binary) do
    case path(ride) do
      nil ->
        :error

      path ->
        File.mkdir_p!(dir())
        File.write!(path, binary)
        sweep(ride)
        :ok
    end
  rescue
    error ->
      Logger.warning(
        "ride thumbnail write failed for ride #{ride.id}: #{Exception.message(error)}"
      )

      :error
  end

  @doc "Removes every thumbnail kept for a ride, whatever URL it came from."
  def delete(%{id: id}) do
    for file <- files(), owner(file) == id, do: File.rm(Path.join(dir(), file))
    :ok
  end

  @doc """
  Removes the ride's thumbnails other than the current one: earlier cuts of
  the route, and anything cached under the bare `<id>.jpg`.
  """
  def sweep(%{id: id} = ride) do
    keep = ride |> path() |> then(&(&1 && Path.basename(&1)))

    for file <- files(), owner(file) == id, file != keep do
      File.rm(Path.join(dir(), file))
    end

    :ok
  end

  @doc """
  Removes every file in the cache that is not some listed ride's current
  thumbnail. Returns how many went. The sync runs this once a pass, so a
  ride deleted on Komoot does not leave its picture behind.
  """
  def sweep_all(rides) do
    keep = rides |> Enum.map(&path/1) |> Enum.reject(&is_nil/1) |> MapSet.new(&Path.basename/1)

    files()
    |> Enum.reject(&MapSet.member?(keep, &1))
    |> Enum.count(&(File.rm(Path.join(dir(), &1)) == :ok))
  end

  defp files do
    case File.ls(dir()) do
      {:ok, files} -> Enum.filter(files, &String.ends_with?(&1, ".jpg"))
      _ -> []
    end
  end

  # `12.jpg` and `12-0a1b2c3d4e5f.jpg` both belong to ride 12.
  defp owner(file) do
    case Integer.parse(file) do
      {id, rest} when rest == ".jpg" or binary_part(rest, 0, 1) == "-" -> id
      _ -> nil
    end
  end
end
