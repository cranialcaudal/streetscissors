defmodule Web.Rides.GPX do
  @moduledoc """
  Parses GPX track files (e.g. Komoot or Apple Health exports) into ride
  point rows. Namespace-agnostic so GPX 1.0 and 1.1 both work.
  """

  import SweetXml

  @doc """
  Returns `{:ok, points, has_time?}` where points are maps ready for
  `insert_all`, ordered as they appear in the file. When the file has no
  `<time>` elements, sequential 1-second timestamps are synthesized (the
  unique index needs them) and `has_time?` is false so callers skip
  time-based stats.
  """
  def parse(xml) when is_binary(xml) do
    trkpts =
      xpath(xml, ~x"//*[local-name()='trkpt']"l,
        lat: ~x"./@lat"s,
        lon: ~x"./@lon"s,
        ele: ~x"./*[local-name()='ele']/text()"s,
        time: ~x"./*[local-name()='time']/text()"s
      )

    points =
      trkpts
      |> Enum.map(&to_point/1)
      |> Enum.reject(&is_nil/1)

    case points do
      [] ->
        {:error, :no_track_points}

      points ->
        has_time? = Enum.all?(points, & &1.recorded_at)
        {:ok, ensure_timestamps(points, has_time?), has_time?}
    end
  rescue
    # :xmerl exits/raises on malformed XML
    _ -> {:error, :invalid_gpx}
  catch
    :exit, _ -> {:error, :invalid_gpx}
  end

  defp to_point(%{lat: lat, lon: lon, ele: ele, time: time}) do
    with {lat, ""} <- Float.parse(lat),
         {lon, ""} <- Float.parse(lon) do
      %{
        lat: lat,
        lon: lon,
        altitude_m: parse_ele(ele),
        recorded_at: parse_time(time),
        speed_mps: nil,
        accuracy_m: nil
      }
    else
      _ -> nil
    end
  end

  defp parse_ele(""), do: nil

  defp parse_ele(ele) do
    case Float.parse(ele) do
      {value, _} -> value
      :error -> nil
    end
  end

  defp parse_time(""), do: nil

  defp parse_time(time) do
    case DateTime.from_iso8601(time) do
      {:ok, dt, _offset} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end

  defp ensure_timestamps(points, true), do: points

  defp ensure_timestamps(points, false) do
    base = DateTime.utc_now() |> DateTime.truncate(:second)

    points
    |> Enum.with_index()
    |> Enum.map(fn {point, i} -> %{point | recorded_at: DateTime.add(base, i)} end)
  end
end
