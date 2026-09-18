defmodule Web.Media do
  @moduledoc """
  The names of the files inside a captain's log's media directory.

  One module so the writer (`Web.Media.Transcoder`) and the readers
  (`Web.Audio.Log.media_url/1`, the player hook) cannot drift: rename a file
  here and both ends follow. The directory itself is `Web.Uploads`'s business.
  """

  @doc "The HLS master playlist a video entry is played from."
  def master_playlist, do: "master.m3u8"

  @doc "One rung of the ladder, `0` being the largest."
  def variant_playlist(index), do: "v#{index}/index.m3u8"

  @doc """
  The progressive rendition an audio entry is played from.

  Audio skips HLS on purpose: ten minutes of speech is about 7 MB, which a
  Range request serves better than a hundred segments would, and it needs no
  player library at all.
  """
  def audio_rendition, do: "audio.m4a"

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

  defp queue, do: Application.get_env(:web, :transcode_queue, Web.Media.Transcoder)
end
