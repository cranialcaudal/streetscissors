defmodule Web.Media.FFmpeg do
  @moduledoc """
  Builds and runs the ffmpeg commands behind the captain's logs.

  This is the shell-out seam, and the only module that knows ffmpeg's argument
  vocabulary. The binaries resolve through application config
  (`:ffmpeg_bin`, `:ffprobe_bin`) so the test suite can point them at a stub
  and never encode a real frame.

  Every command here was checked against ffmpeg 7.1 before it was written
  down; two of them are less obvious than they look:

    * **Trim is `-ss` + `-t`, not `-ss` + `-to`.** With input seeking, `-to`
      is read against the input timeline in some versions and the seek point
      in others. A duration has no such ambiguity.
    * **A video is pinned to 30 fps.** The recording booth's WebM carries
      1 ms timestamps and no frame rate, so left to itself ffmpeg took it for
      1000 fps and duplicated frames to fill that — six thousand frames per
      six seconds, which libx264 then labelled H.264 level 6.0 and which many
      decoders (Safari among them) refused. `fps=30` in the filter graph is
      the fix; `-level:v 4.0` states the result.
  """

  require Logger

  # The one video rendition: fitted inside 1280x720, never upscaled.
  @video_box %{width: 1280, height: 720}

  @doc "Path to the ffmpeg binary. Overridable as `config :web, :ffmpeg_bin`."
  def ffmpeg_bin, do: Application.get_env(:web, :ffmpeg_bin, "ffmpeg")

  @doc "Path to the ffprobe binary. Overridable as `config :web, :ffprobe_bin`."
  def ffprobe_bin, do: Application.get_env(:web, :ffprobe_bin, "ffprobe")

  @doc """
  Inspects a file: duration in seconds, pixel dimensions, and which kinds of
  stream it actually carries.

  `has_audio?` is not a formality — a screen recording or a muted clip has no
  audio stream at all, and mapping one that isn't there fails the whole
  encode.
  """
  def probe(path) do
    args = [
      "-v",
      "error",
      "-print_format",
      "json",
      "-show_format",
      "-show_streams",
      path
    ]

    case System.cmd(ffprobe_bin(), args, stderr_to_stdout: true) do
      {output, 0} -> parse_probe(output)
      {output, status} -> {:error, "ffprobe exited #{status}: #{String.trim(output)}"}
    end
  rescue
    e in ErlangError -> {:error, "ffprobe could not be run: #{Exception.message(e)}"}
  end

  defp parse_probe(output) do
    with {:ok, %{"streams" => streams} = json} <- Jason.decode(output) do
      video = Enum.find(streams, &(&1["codec_type"] == "video"))
      audio = Enum.find(streams, &(&1["codec_type"] == "audio"))

      {:ok,
       %{
         duration: parse_duration(json),
         width: video && video["width"],
         height: video && video["height"],
         has_video?: not is_nil(video),
         has_audio?: not is_nil(audio)
       }}
    else
      _ -> {:error, "ffprobe returned something that is not stream JSON"}
    end
  end

  defp parse_duration(%{"format" => %{"duration" => duration}}) when is_binary(duration) do
    case Float.parse(duration) do
      {seconds, _} -> seconds
      :error -> nil
    end
  end

  defp parse_duration(_json), do: nil

  @doc """
  The video rendition: one progressive MP4 that every browser plays natively,
  with no player library and no segment requests.

  `fps=30` drops the duplicate frames a 1 ms-timebase recording would
  otherwise be padded out with (see the module docs), which is also what
  makes the `-g 60` keyframe grid mean two seconds. `+faststart` moves the
  index to the front, so playback begins before the file has downloaded, and
  seeking is a Range request away. A 60 fps phone clip comes out at 30 —
  for a spoken log that costs nothing.
  """
  def video_args(source, dir, opts) do
    audio? = Keyword.get(opts, :audio?, true)

    trim_args(opts) ++
      ["-i", source] ++
      ["-map", "0:v:0"] ++
      if(audio?, do: ["-map", "0:a:0"], else: []) ++
      ["-vf", "fps=30," <> scale(@video_box)] ++
      ["-c:v", "libx264", "-preset", "veryfast", "-profile:v", "high", "-level:v", "4.0"] ++
      ["-pix_fmt", "yuv420p", "-crf", "23", "-maxrate", "2500k", "-bufsize", "5000k"] ++
      ["-g", "60", "-keyint_min", "60"] ++
      if(audio?, do: ["-c:a", "aac", "-b:a", "128k", "-ac", "2", "-ar", "48000"], else: []) ++
      ["-movflags", "+faststart"] ++
      progress_args() ++
      [Path.join(dir, Web.Media.video_rendition())]
  end

  # The box is the smaller of the target and the source, so the rendition
  # never upscales — `force_original_aspect_ratio=decrease` then fits inside it
  # keeping the aspect, and `force_divisible_by=2` keeps both sides even,
  # which yuv420p requires.
  defp scale(box) do
    "scale=w='min(#{box.width},iw)':h='min(#{box.height},ih)'" <>
      ":force_original_aspect_ratio=decrease:force_divisible_by=2"
  end

  @doc """
  A progressive audio rendition: what an audio-only entry is played from.

  Ten minutes of speech is about 7 MB, served by Range requests and played
  by the browser's own `<audio>` — the same shape as the video rendition.
  """
  def audio_args(source, dir, opts) do
    trim_args(opts) ++
      ["-i", source] ++
      [
        "-vn",
        "-c:a",
        "aac",
        "-b:a",
        "96k",
        "-ac",
        "1",
        "-ar",
        "44100",
        "-movflags",
        "+faststart"
      ] ++
      progress_args() ++
      [Path.join(dir, Web.Media.audio_rendition())]
  end

  @doc """
  A single still, scaled to 960 wide.

  `at` is a timestamp within the *finished* media, so `input` is the
  rendition itself. The seek is an output seek (`-ss` after `-i`): exact on
  any input, including a legacy HLS playlist, where an input seek yields no
  frames at all.
  """
  def poster_args(input, output, at) do
    ["-i", input, "-ss", format_seconds(at), "-frames:v", "1"] ++
      ["-vf", "scale=w='min(960,iw)':h=-2", "-q:v", "4", output]
  end

  @doc "A waveform plate, which is what an audio entry has instead of a still."
  def waveform_args(input, output) do
    [
      "-i",
      input,
      "-filter_complex",
      "showwavespic=s=960x240:colors=#ff9e3d",
      "-frames:v",
      "1",
      output
    ]
  end

  # `-ss` before `-i` seeks the input, which on a regular file is both exact
  # enough and fast. `-t` rather than `-to`: see the module docs.
  defp trim_args(opts) do
    start = Keyword.get(opts, :trim_start)
    duration = Keyword.get(opts, :trim_duration)

    if(start && start > 0, do: ["-ss", format_seconds(start)], else: []) ++
      if duration && duration > 0, do: ["-t", format_seconds(duration)], else: []
  end

  defp progress_args, do: ["-progress", "pipe:1", "-nostats"]

  defp format_seconds(seconds) when is_integer(seconds), do: to_string(seconds)

  defp format_seconds(seconds) when is_float(seconds),
    do: :erlang.float_to_binary(seconds, decimals: 3)

  @doc """
  The executable and arguments to actually spawn, with the common flags and a
  politeness prefix in front.

  Encoding runs at `nice 10` and idle I/O priority so that a transcode never
  competes with serving the site — the whole point of doing this on the same
  laptop that answers requests. Both tools are standard on Linux but are
  looked up rather than assumed, so a container without them still encodes.
  """
  def command(args) do
    base = [ffmpeg_bin(), "-hide_banner", "-nostdin", "-y"] ++ args

    case {System.find_executable("nice"), System.find_executable("ionice")} do
      {nil, _} -> {ffmpeg_bin(), tl(base)}
      {nice, nil} -> {nice, ["-n", "10"] ++ base}
      {nice, ionice} -> {nice, ["-n", "10", ionice, "-c", "3"] ++ base}
    end
  end

  @doc """
  Runs one command to completion, without progress. Used for the short steps
  — posters and waveforms — where there is nothing worth reporting.
  """
  def run(args) do
    {executable, argv} = command(args)

    case System.cmd(executable, argv, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> {:error, "ffmpeg exited #{status}: #{tail(output)}"}
    end
  rescue
    e in ErlangError -> {:error, "ffmpeg could not be run: #{Exception.message(e)}"}
  end

  @doc "The last few lines of ffmpeg's output — the part that says what went wrong."
  def tail(output, lines \\ 6) do
    output
    |> String.split("\n", trim: true)
    |> Enum.take(-lines)
    |> Enum.join("\n")
  end
end
