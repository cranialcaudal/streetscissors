defmodule Web.AudioFixtures do
  @moduledoc """
  Test helpers for the `Web.Audio` context (captain's logs).
  """

  @doc """
  Creates a captain's log. Defaults to published, dated today, with keywords —
  override any of it via `attrs`.
  """
  def log_fixture(attrs \\ %{}) do
    attrs = Map.new(attrs, fn {key, value} -> {to_string(key), value} end)
    title = Map.get(attrs, "title", "Log #{System.unique_integer([:positive])}")

    {:ok, log} =
      attrs
      |> Map.put_new("title", title)
      |> Map.put_new("file_path", "/uploads/logs/#{Web.Keywords.slugify(title)}.mp3")
      |> Map.put_new("recorded_on", Date.utc_today())
      |> Map.put_new("keywords", "ferry, nyc")
      |> Map.put_new("duration", 252)
      |> Map.put_new("published", true)
      |> Web.Audio.create_log()

    log
  end

  @doc """
  The smallest thing that will pass as an uploaded audio file on disk — the
  upload path only ever copies bytes, it never decodes them.
  """
  def audio_upload_fixture do
    path =
      Path.join(System.tmp_dir!(), "log-upload-#{System.unique_integer([:positive])}.mp3")

    File.write!(path, "ID3 fake audio bytes")
    path
  end
end
