defmodule Web.Cuts.Render do
  @moduledoc """
  The ffmpeg command that renders a cut (`Web.Cuts.Timeline`) into one MP4.
  Pure: it is given the laid-out timeline and where every file is, and gives
  back arguments, so the whole filter graph can be read in a test.

  The picture is 1280x720 at 30 frames a second, the shape every log already
  is, and the result goes through the captain's logs' own transcode after
  (`Web.Cuts.publish/2`), so it is made at a high quality (CRF 18) to lose
  little the second time.

  The graph, in order:

    1. **Each clip becomes a picture and a sound of exactly its length.** A
       take is read from its in point for its length (input seeking), fitted
       into the frame with black bars where its shape differs, and its sound
       resampled; a take with no sound gets silence. A print is fitted the
       same way, scaled up, and moved by `zoompan` (scaling up first is what
       keeps a slow zoom from shuddering a pixel at a time), with silence.
    2. **`concat` joins them**, picture and sound together, into the main track.
    3. **Each title is laid over it** between its times, fading in and out
       over 0.4 s. A title is a transparent PNG set by `Web.Cuts.Titles`.
    4. **The sounds are mixed under the main track's sound.** Each is cut,
       delayed to its place, faded and set to its gain. Sounds marked `duck`
       are mixed together and pressed down by the main track's own sound
       (`sidechaincompress`), so music drops while someone speaks; the rest
       are mixed in as they are. `amix` runs with `normalize=0`, or every
       input would be halved.
  """

  @width 1280
  @height 720
  @fps 30
  @fade 0.4

  @doc """
  The arguments for `Web.Media.FFmpeg.command/1`.

  `files` says where everything is: `:media` maps a bin id to
  `%{path: _, has_audio: _}`, `:stills` a frame (`"065/6"`) to its print, and
  `:titles` a title's id to its PNG.
  """
  def args(%{clips: clips, titles: titles, sounds: sounds, length: total}, files, output)
      when clips != [] do
    {inputs, clip_specs, n} = clip_inputs(clips, files, 0)
    {title_inputs, title_specs, n} = title_inputs(titles, files, total, n)
    {sound_inputs, sound_specs, _n} = sound_inputs(sounds, files, n)

    graph =
      Enum.flat_map(Enum.with_index(clip_specs), &clip_filters/1) ++
        [concat(length(clip_specs))] ++
        title_filters(title_specs) ++
        sound_filters(sound_specs, total)

    inputs ++
      title_inputs ++
      sound_inputs ++
      ["-filter_complex", Enum.join(graph, ";")] ++
      ["-map", "[vout]", "-map", "[aout]"] ++
      [
        "-c:v",
        "libx264",
        "-preset",
        "medium",
        "-crf",
        "18",
        "-pix_fmt",
        "yuv420p",
        "-r",
        "#{@fps}"
      ] ++
      ["-c:a", "aac", "-b:a", "192k", "-ar", "48000", "-ac", "2"] ++
      ["-t", seconds(total), "-movflags", "+faststart"] ++
      ["-progress", "pipe:1", "-nostats"] ++
      [output]
  end

  # ── Inputs ────────────────────────────────────────────────────────────

  defp clip_inputs(clips, files, n) do
    Enum.reduce(clips, {[], [], n}, fn clip, {args, specs, i} ->
      case clip do
        %{"kind" => "take", "media" => id} ->
          file = Map.fetch!(files.media, id)
          input = ["-ss", seconds(clip["in"]), "-t", seconds(clip["length"]), "-i", file.path]
          {args ++ input, specs ++ [{:take, i, clip, file.has_audio}], i + 1}

        %{"kind" => "still", "frame" => frame} ->
          input = ["-i", Map.fetch!(files.stills, frame)]
          {args ++ input, specs ++ [{:still, i, clip}], i + 1}
      end
    end)
  end

  # A title's picture is looped for the whole cut and shown only in its time.
  defp title_inputs(titles, files, total, n) do
    Enum.reduce(titles, {[], [], n}, fn title, {args, specs, i} ->
      png = Map.fetch!(files.titles, title["id"])
      input = ["-loop", "1", "-framerate", "#{@fps}", "-t", seconds(total), "-i", png]
      {args ++ input, specs ++ [{i, title}], i + 1}
    end)
  end

  defp sound_inputs(sounds, files, n) do
    Enum.reduce(sounds, {[], [], n}, fn sound, {args, specs, i} ->
      file = Map.fetch!(files.media, sound["media"])
      input = ["-ss", seconds(sound["in"]), "-t", seconds(sound["length"]), "-i", file.path]
      {args ++ input, specs ++ [{i, sound}], i + 1}
    end)
  end

  # ── The main track ────────────────────────────────────────────────────

  defp clip_filters({{:take, input, clip, has_audio}, k}) do
    length = seconds(clip["length"])

    picture =
      "[#{input}:v]setpts=PTS-STARTPTS,fps=#{@fps},#{fit()},setsar=1,format=yuv420p," <>
        "trim=duration=#{length}[v#{k}]"

    sound =
      if has_audio do
        "[#{input}:a]#{audio_format()},asetpts=PTS-STARTPTS,volume=#{gain(clip["gain"])}," <>
          "apad,atrim=duration=#{length}[a#{k}]"
      else
        silence(length, k)
      end

    [picture, sound]
  end

  defp clip_filters({{:still, input, clip}, k}) do
    frames = max(round(clip["length"] / 1000 * @fps), 1)
    {z, x, y} = move(clip["move"], frames)

    picture =
      "[#{input}:v]#{fit()},setsar=1,scale=#{@width * 2}:#{@height * 2}," <>
        "zoompan=z='#{z}':x='#{x}':y='#{y}':d=#{frames}:s=#{@width}x#{@height}:fps=#{@fps}," <>
        "setsar=1,format=yuv420p[v#{k}]"

    [picture, silence(seconds(clip["length"]), k)]
  end

  # How the camera moves over a print, as zoompan's zoom and corner. `on` is
  # the frame being made; the zoom goes 12% over the print's time.
  @doc false
  def move("in", n), do: {"1+0.12*on/#{n}", centre(:x), centre(:y)}
  def move("out", n), do: {"1.12-0.12*on/#{n}", centre(:x), centre(:y)}
  def move("pan-left", n), do: {"1.12", "(iw-iw/zoom)*(1-on/#{n})", centre(:y)}
  def move("pan-right", n), do: {"1.12", "(iw-iw/zoom)*on/#{n}", centre(:y)}
  def move(_none, _n), do: {"1", "0", "0"}

  defp centre(:x), do: "iw/2-(iw/zoom/2)"
  defp centre(:y), do: "ih/2-(ih/zoom/2)"

  defp fit do
    "scale=#{@width}:#{@height}:force_original_aspect_ratio=decrease," <>
      "pad=#{@width}:#{@height}:(ow-iw)/2:(oh-ih)/2:color=black"
  end

  defp audio_format, do: "aresample=48000,aformat=sample_fmts=fltp:channel_layouts=stereo"

  defp silence(length, k),
    do: "anullsrc=r=48000:cl=stereo,aformat=sample_fmts=fltp,atrim=duration=#{length}[a#{k}]"

  defp concat(n) do
    pairs = Enum.map_join(0..(n - 1), "", &"[v#{&1}][a#{&1}]")
    pairs <> "concat=n=#{n}:v=1:a=1[vc][ac]"
  end

  # ── Titles ────────────────────────────────────────────────────────────

  defp title_filters([]), do: ["[vc]null[vout]"]

  defp title_filters(specs) do
    count = length(specs)

    specs
    |> Enum.with_index()
    |> Enum.flat_map(fn {{input, title}, j} ->
      at = title["at"] / 1000
      until = (title["at"] + title["length"]) / 1000
      fade = min(@fade, (until - at) / 2)
      from = if j == 0, do: "vc", else: "vt#{j - 1}"
      to = if j == count - 1, do: "vout", else: "vt#{j}"

      [
        "[#{input}:v]format=rgba,fade=t=in:st=#{f(at)}:d=#{f(fade)}:alpha=1," <>
          "fade=t=out:st=#{f(until - fade)}:d=#{f(fade)}:alpha=1[t#{j}]",
        "[#{from}][t#{j}]overlay=0:0:enable='between(t,#{f(at)},#{f(until)})'[#{to}]"
      ]
    end)
  end

  # ── Sound ─────────────────────────────────────────────────────────────

  defp sound_filters([], _total), do: ["[ac]anull[aout]"]

  defp sound_filters(specs, total) do
    shaped =
      specs
      |> Enum.with_index()
      |> Enum.map(fn {{input, sound}, j} ->
        length = sound["length"] / 1000
        fade_in = sound["fade_in"] / 1000
        fade_out = sound["fade_out"] / 1000

        filter =
          "[#{input}:a]#{audio_format()},asetpts=PTS-STARTPTS,volume=#{gain(sound["gain"])}," <>
            "afade=t=in:st=0:d=#{f(fade_in)},afade=t=out:st=#{f(max(length - fade_out, 0))}:d=#{f(fade_out)}," <>
            "adelay=#{sound["at"]}:all=1[s#{j}]"

        {filter, "s#{j}", sound["duck"]}
      end)

    {ducked, plain} = Enum.split_with(shaped, fn {_, _, duck} -> duck end)
    filters = Enum.map(shaped, &elem(&1, 0))
    length = seconds(total)

    if ducked == [] do
      filters ++ [mix(["ac" | labels(plain)], "aout", "first")]
    else
      filters ++
        [
          "[ac]asplit=2[voice][key]",
          mix(labels(ducked), "bus", "longest"),
          "[bus][key]sidechaincompress=threshold=0.02:ratio=8:attack=20:release=500[ducked]",
          mix(["voice", "ducked" | labels(plain)], "mixed", "first"),
          "[mixed]atrim=duration=#{length}[aout]"
        ]
    end
  end

  defp labels(shaped), do: Enum.map(shaped, &elem(&1, 1))

  defp mix([only], to, _duration), do: "[#{only}]anull[#{to}]"

  defp mix(labels, to, duration) do
    Enum.map_join(labels, "", &"[#{&1}]") <>
      "amix=inputs=#{length(labels)}:normalize=0:duration=#{duration}[#{to}]"
  end

  # ── Numbers ───────────────────────────────────────────────────────────

  defp gain(db), do: "#{f(db * 1.0)}dB"
  defp seconds(ms), do: f(ms / 1000)
  defp f(number), do: :erlang.float_to_binary(number * 1.0, decimals: 3)
end
