defmodule Web.Media do
  @moduledoc """
  The names of the files inside a captain's log's media directory.

  One module so the writer (`Web.Media.Transcoder`) and the readers
  (`Web.Audio.Log.media_url/1`, the player hook) cannot drift: rename a file
  here and both ends follow. The directory itself is `Web.Uploads`'s business.
  """

  @doc """
  The progressive MP4 a video entry is played from.

  One file, not an HLS ladder: every browser plays it natively, so starting
  playback is a plain `play()` inside the click — no player library to fetch
  first, which is what Safari needs — and seeking is a Range request.
  """
  def video_rendition, do: "video.mp4"

  @doc "The progressive rendition an audio entry is played from."
  def audio_rendition, do: "audio.m4a"

  # Entries encoded before 2026-09-22 were an HLS ladder; its top rung is
  # what `reencode/1` reads when there is no MP4 yet.
  @legacy_top_rung "v0/index.m3u8"

  @doc "The still a video entry shows before it is played — or, for audio, its waveform."
  def poster, do: "poster.jpg"

  @doc """
  Puts a log on the transcode queue.

  One indirection, for one reason: a test that uploads a file should not
  start ffmpeg. The queue is a supervised, globally named process, so it
  cannot see the test's sandboxed database connection — the job would fail
  and take the queue down with it. `config/test.exs` points this at a null
  queue instead, and the transcoder is driven directly by its own test.
  """
  def enqueue(log_id), do: queue().enqueue(log_id)

  @doc """
  Re-encodes a finished entry from its own rendition, for when the encode
  itself has changed and the source is long gone (sources are deleted after
  a successful transcode).

  The input is the entry's current rendition — its MP4, or the top rung of a
  legacy HLS ladder, which ffmpeg reads as input. The trims are cleared
  because they are already baked into that rendition; `poster_at_ms` is kept,
  since it is measured on the finished timeline. The old directory is
  destroyed by `Web.Audio.mark_ready/2` only once the row points at the new
  one, and a failed run leaves it in place with `source_path` still pointing
  into it, so the admin's retry works as for any failed entry.

  The entry is `processing`, and so off the public list, while it runs.
  """
  def reencode(%Web.Audio.Log{status: "ready", media_dir: dir} = log) when is_binary(dir) do
    with {:ok, input} <- current_rendition(log),
         {:ok, log} <-
           Web.Audio.update_log(log, %{
             source_path: input,
             trim_start_ms: nil,
             trim_duration_ms: nil,
             status: "pending",
             transcode_error: nil
           }) do
      enqueue(log.id)
      {:ok, log}
    end
  end

  def reencode(_log), do: {:error, "only a finished entry can be re-encoded"}

  defp current_rendition(%{kind: kind, media_dir: dir}) do
    root = Web.Uploads.entry_dir!(dir)

    candidates =
      if kind == "video",
        do: [video_rendition(), @legacy_top_rung],
        else: [audio_rendition()]

    case Enum.find(candidates, &File.regular?(Path.join(root, &1))) do
      nil -> {:error, "no rendition to re-encode from in #{dir}"}
      name -> {:ok, Path.join(root, name)}
    end
  end

  defp queue, do: Application.get_env(:web, :transcode_queue, Web.Media.Transcoder)
end
