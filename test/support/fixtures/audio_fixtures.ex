defmodule Web.AudioFixtures do
  @moduledoc """
  Test helpers for the `Web.Audio` context (captain's logs).
  """

  @doc """
  Creates a captain's log. Defaults to a published, transcoded video entry
  dated today, with keywords — override any of it via `attrs`.

  `status: "ready"` is the default because that is what the public pages will
  show; a test about an entry mid-transcode passes `status: "pending"`
  explicitly.
  """
  def log_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)

    {:ok, log} =
      attrs
      |> Map.put_new("recorded_on", Date.utc_today())
      |> Map.put_new("kind", "video")
      |> Map.put_new("status", "ready")
      |> Map.put_new("keywords", "ferry, nyc")
      |> Map.put_new("duration", 252)
      |> Map.put_new("published", true)
      |> put_new_media()
      |> Web.Audio.create_log()

    log
  end

  # A ready entry needs somewhere for its media to be; a pending one has none
  # yet, and pointing it at a directory would be a lie.
  defp put_new_media(%{"status" => "ready"} = attrs) do
    dir = "log-#{System.unique_integer([:positive])}"

    attrs
    |> Map.put_new("media_dir", dir)
    |> Map.put_new("poster_path", "/uploads/logs/#{dir}/poster.jpg")
  end

  defp put_new_media(attrs), do: attrs

  @doc """
  The smallest thing that will pass as an uploaded recording on disk.

  Nothing in the suite decodes it: `Web.Uploads` only ever moves bytes, and
  ffmpeg is stubbed (see `config/test.exs`).
  """
  def media_upload_fixture(extension \\ ".webm") do
    path =
      Path.join(
        System.tmp_dir!(),
        "log-upload-#{System.unique_integer([:positive])}#{extension}"
      )

    File.write!(path, "fake recording bytes")
    path
  end
end
