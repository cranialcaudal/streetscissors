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
    * **Seeking an HLS playlist has to be an output seek.** `-ss` *before* an
      `.m3u8` input yields zero frames and the encoder then fails to open at
      all; `-ss` after it works. That is what lets a poster be re-picked from
      a finished rendition once the source is gone.
  """

  require Logger

  # The ladder, largest first. A rung is only cut if it would actually make
  # the picture smaller — see `rungs/1`.
  @rungs [
    %{
      name: "720",
      height: 720,
      width: 1280,
      bitrate: "2200k",
      maxrate: "2400k",
      bufsize: "4400k"
    },
    %{name: "480", height: 480, width: 854, bitrate: "800k", maxrate: "900k", bufsize: "1600k"}
  ]

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
  The rungs worth encoding for a source of the given height.

  A 480p source encoded against both rungs produces two byte-identical
  renditions, because neither box makes it smaller — so anything at or below
  the bottom rung gets one rendition at its native size, and the ladder only
  appears when there is a real difference to switch between.
  """
  def rungs(height) when is_integer(height) do
    case Enum.filter(@rungs, &(&1.height < height)) do
      # Nothing downscales it: one rendition at its own size.
      [] -> [List.last(@rungs)]
      # Only the bottom rung downscales it, so the top one renders native and
      # there is still a real pair to switch between.
      [smallest] -> [hd(@rungs), smallest]
      kept -> kept
    end
  end

  def rungs(_height), do: @rungs

  @doc """
  The HLS ladder: one invocation, source decoded once, `n` renditions out.

  Keyframes are forced onto a fixed 60-frame grid (`-g`/`-keyint_min` with
  scene detection off) because a player can only switch rungs at a segment
  boundary, and boundaries only line up across renditions if the keyframes do.
  """
  def ladder_args(source, dir, opts) do
    rungs = Keyword.fetch!(opts, :rungs)
    audio? = Keyword.get(opts, :audio?, true)
    n = length(rungs)

    trim_args(opts) ++
      ["-i", source] ++
      ["-filter_complex", filter_complex(rungs)] ++
      Enum.flat_map(0..(n - 1), &["-map", "[v#{&1}]"]) ++
      if(audio?, do: List.duplicate(["-map", "0:a:0"], n) |> List.flatten(), else: []) ++
      ["-c:v", "libx264", "-preset", "veryfast", "-profile:v", "high", "-pix_fmt", "yuv420p"] ++
      Enum.flat_map(Enum.with_index(rungs), fn {rung, i} ->
        [
          "-b:v:#{i}",
          rung.bitrate,
          "-maxrate:v:#{i}",
          rung.maxrate,
          "-bufsize:v:#{i}",
          rung.bufsize
        ]
      end) ++
      ["-g", "60", "-keyint_min", "60", "-sc_threshold", "0"] ++
      if(audio?, do: ["-c:a", "aac", "-b:a", "128k", "-ac", "2", "-ar", "48000"], else: []) ++
      [
        "-f",
        "hls",
        "-hls_time",
        "6",
        "-hls_playlist_type",
        "vod",
        "-hls_segment_type",
        "fmp4",
        "-var_stream_map",
        var_stream_map(n, audio?),
        "-master_pl_name",
        Web.Media.master_playlist(),
        "-hls_segment_filename",
        Path.join(dir, "v%v/seg%03d.m4s")
      ] ++
      progress_args() ++
      [Path.join(dir, "v%v/index.m3u8")]
  end

  defp filter_complex([single]) do
    "[0:v]#{scale(single)}[v0]"
  end

  defp filter_complex(rungs) do
    n = length(rungs)
    labels = Enum.map(0..(n - 1), &"[s#{&1}]") |> Enum.join()

    chains =
      rungs
      |> Enum.with_index()
      |> Enum.map(fn {rung, i} -> "[s#{i}]#{scale(rung)}[v#{i}]" end)
      |> Enum.join(";")

    "[0:v]split=#{n}#{labels};#{chains}"
  end

  # The box is the smaller of the rung and the source, so a rendition never
  # upscales — `force_original_aspect_ratio=decrease` then fits inside it
  # keeping the aspect, and `force_divisible_by=2` keeps both sides even,
  # which yuv420p requires.
  defp scale(rung) do
    "scale=w='min(#{rung.width},iw)':h='min(#{rung.height},ih)'" <>
      ":force_original_aspect_ratio=decrease:force_divisible_by=2"
  end

  defp var_stream_map(n, audio?) do
    0..(n - 1)
    |> Enum.map(fn i -> if audio?, do: "v:#{i},a:#{i}", else: "v:#{i}" end)
    |> Enum.join(" ")
  end

  @doc """
  A progressive audio rendition: what an audio-only entry is played from.

  No HLS here on purpose. Ten minutes of speech is about 7 MB, which one
  Range request serves better than a hundred segments would — and it needs no
  player library in the browser at all.
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

  `at` is a timestamp within the *finished* media, so `input` may be either
  the source file or a rendition's playlist — see the note about output
  seeking in this module's docs.
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
