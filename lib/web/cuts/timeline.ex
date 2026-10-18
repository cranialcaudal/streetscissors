defmodule Web.Cuts.Timeline do
  @moduledoc """
  The edit, as data: a map kept as JSON on the cut.

      %{"clips" => [...], "titles" => [...], "sounds" => [...]}

  **Clips play one after another**, on one main track (Final Cut's magnetic
  timeline rather than Premiere's free one): taking a clip out closes the gap,
  and moving one moves the rest along. A clip is either

    * a take: `"kind" => "take"`, `"media"` (a bin id), `"in"` and `"out"` in
      milliseconds of the take, `"gain"` in dB; or
    * a print from the archive: `"kind" => "still"`, `"frame"` (`"065/6"`),
      `"duration"`, and `"move"`, how the camera moves over it (`none`, `in`,
      `out`, `pan-left`, `pan-right`).

  **Titles and sounds sit at a time of their own** (`"at"`, milliseconds from
  the start of the cut) over the clips. A title has `"text"`, `"duration"` and
  `"style"`: `title` across the middle in Goudy, `lower` along the foot in the
  instrument voice. A sound is a file from the bin (music, or a voice laid
  over the prints) with `"in"`, `"out"`, `"gain"`, `"fade_in"`, `"fade_out"`
  and `"duck"`, which lowers it while the clips speak.

  Everything the browser sends goes through `normalize/2`, which drops what
  refers to nothing and holds every number to its range, so a timeline on
  disk is always one `Web.Cuts.Render` can render.
  """

  @min_take 100
  @moves ~w(in out pan-left pan-right none)
  @styles ~w(title lower)
  @id ~r/\A[a-z]-[a-z0-9]{1,16}\z/

  def empty, do: %{"clips" => [], "titles" => [], "sounds" => []}

  def moves, do: @moves
  def styles, do: @styles

  # ── Normalizing ───────────────────────────────────────────────────────

  @doc """
  The timeline held to what the bin has and to every range. `media` is the
  bin, by id. A take or sound whose file is missing or not yet ready is
  dropped, as is a title with no words.
  """
  def normalize(timeline, media) when is_map(timeline) do
    %{
      "clips" => list(timeline["clips"]) |> Enum.flat_map(&clip(&1, media)),
      "titles" => list(timeline["titles"]) |> Enum.flat_map(&title/1),
      "sounds" => list(timeline["sounds"]) |> Enum.flat_map(&sound(&1, media))
    }
  end

  def normalize(_timeline, _media), do: empty()

  defp list(items) when is_list(items), do: Enum.filter(items, &is_map/1)
  defp list(_), do: []

  defp clip(%{"kind" => "take"} = clip, media) do
    case usable(media, clip["media"], &(&1.kind == "video")) do
      nil ->
        []

      take ->
        first = clamp(int(clip["in"], 0), 0, take.duration_ms - @min_take)
        last = clamp(int(clip["out"], take.duration_ms), first + @min_take, take.duration_ms)

        [
          %{
            "id" => id(clip["id"], "c"),
            "kind" => "take",
            "media" => take.id,
            "in" => first,
            "out" => last,
            "gain" => clamp(num(clip["gain"], 0.0), -30.0, 12.0)
          }
        ]
    end
  end

  defp clip(%{"kind" => "still", "frame" => frame} = clip, _media) when is_binary(frame) do
    if Regex.match?(~r/\A\d{1,4}\/\d{1,4}\z/, frame) do
      [
        %{
          "id" => id(clip["id"], "c"),
          "kind" => "still",
          "frame" => frame,
          "duration" => clamp(int(clip["duration"], 4000), 500, 60_000),
          "move" => if(clip["move"] in @moves, do: clip["move"], else: "in")
        }
      ]
    else
      []
    end
  end

  defp clip(_clip, _media), do: []

  defp title(%{"text" => text} = title) when is_binary(text) do
    case text |> String.trim() |> String.slice(0, 120) do
      "" ->
        []

      text ->
        [
          %{
            "id" => id(title["id"], "t"),
            "text" => text,
            "at" => max(int(title["at"], 0), 0),
            "duration" => clamp(int(title["duration"], 3000), 500, 60_000),
            "style" => if(title["style"] in @styles, do: title["style"], else: "title")
          }
        ]
    end
  end

  defp title(_title), do: []

  defp sound(sound, media) do
    case usable(media, sound["media"], &(&1.kind == "audio" or &1.has_audio)) do
      nil ->
        []

      file ->
        first = clamp(int(sound["in"], 0), 0, file.duration_ms - @min_take)
        last = clamp(int(sound["out"], file.duration_ms), first + @min_take, file.duration_ms)
        length = last - first

        [
          %{
            "id" => id(sound["id"], "s"),
            "media" => file.id,
            "at" => max(int(sound["at"], 0), 0),
            "in" => first,
            "out" => last,
            "gain" => clamp(num(sound["gain"], 0.0), -40.0, 12.0),
            "fade_in" => clamp(int(sound["fade_in"], 0), 0, min(10_000, length)),
            "fade_out" => clamp(int(sound["fade_out"], 0), 0, min(10_000, length)),
            "duck" => sound["duck"] in [true, "true"]
          }
        ]
    end
  end

  defp usable(media, id, fits?) do
    with id when is_integer(id) <- int(id, nil),
         %{status: "ready", duration_ms: duration} = file when is_integer(duration) <- media[id],
         true <- duration > @min_take and fits?.(file) do
      file
    else
      _ -> nil
    end
  end

  defp id(id, prefix) when is_binary(id) do
    if Regex.match?(@id, id), do: id, else: new_id(prefix)
  end

  defp id(_id, prefix), do: new_id(prefix)

  @doc "A fresh id for an item: its track's letter and six random characters."
  def new_id(prefix) do
    prefix <> "-" <> (:crypto.strong_rand_bytes(4) |> Base.encode32(case: :lower, padding: false))
  end

  defp clamp(value, lo, hi) when lo > hi, do: clamp(value, hi, hi)
  defp clamp(value, lo, hi), do: value |> max(lo) |> min(hi)

  defp int(value, _default) when is_integer(value), do: value
  defp int(value, _default) when is_float(value), do: round(value)

  defp int(value, default) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> round(float)
      :error -> default
    end
  end

  defp int(_value, default), do: default

  defp num(value, _default) when is_number(value), do: value * 1.0

  defp num(value, default) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> default
    end
  end

  defp num(_value, default), do: default

  # ── Where everything falls ────────────────────────────────────────────

  @doc "How long a clip runs, in milliseconds."
  def length_of(%{"kind" => "take", "in" => first, "out" => last}), do: last - first
  def length_of(%{"kind" => "still", "duration" => duration}), do: duration
  def length_of(%{"in" => first, "out" => last}), do: last - first
  def length_of(%{"duration" => duration}), do: duration

  @doc """
  The clips with where each starts (`"start"`) and how long it runs
  (`"length"`), and the cut's whole length, which is the clips'. A title or a
  sound past the end is cut off there.
  """
  def layout(timeline) do
    {clips, total} =
      Enum.map_reduce(timeline["clips"] || [], 0, fn clip, start ->
        length = length_of(clip)
        {Map.merge(clip, %{"start" => start, "length" => length}), start + length}
      end)

    %{
      clips: clips,
      titles: Enum.map(timeline["titles"] || [], &Map.put(&1, "length", &1["duration"])),
      sounds: Enum.map(timeline["sounds"] || [], &Map.put(&1, "length", length_of(&1))),
      length: total
    }
  end

  # ── Edits ─────────────────────────────────────────────────────────────

  @doc "A take put on the end of the main track, whole."
  def add_take(timeline, %{id: id, duration_ms: duration}) do
    clip = %{
      "id" => new_id("c"),
      "kind" => "take",
      "media" => id,
      "in" => 0,
      "out" => duration,
      "gain" => 0.0
    }

    Map.update!(timeline, "clips", &(&1 ++ [clip]))
  end

  @doc "A print from the archive put on the end of the main track."
  def add_still(timeline, frame) do
    clip = %{
      "id" => new_id("c"),
      "kind" => "still",
      "frame" => frame,
      "duration" => 4000,
      "move" => "in"
    }

    Map.update!(timeline, "clips", &(&1 ++ [clip]))
  end

  @doc "A title at `at` milliseconds."
  def add_title(timeline, at) do
    title = %{
      "id" => new_id("t"),
      "text" => "Title",
      "at" => at,
      "duration" => 3000,
      "style" => "title"
    }

    Map.update!(timeline, "titles", &(&1 ++ [title]))
  end

  @doc "A sound from the bin at `at` milliseconds, whole."
  def add_sound(timeline, %{id: id, duration_ms: duration}, at) do
    sound = %{
      "id" => new_id("s"),
      "media" => id,
      "at" => at,
      "in" => 0,
      "out" => duration,
      "gain" => -12.0,
      "fade_in" => 0,
      "fade_out" => 1000,
      "duck" => true
    }

    Map.update!(timeline, "sounds", &(&1 ++ [sound]))
  end

  @doc "The item with this id, on whichever track it is, or nil."
  def find(timeline, id) do
    Enum.find_value(~w(clips titles sounds), fn track ->
      Enum.find(timeline[track], &(&1["id"] == id))
    end)
  end

  @doc "Takes an item out; the clips after a clip close up."
  def remove(timeline, id) do
    Map.new(timeline, fn {track, items} -> {track, Enum.reject(items, &(&1["id"] == id))} end)
  end

  @doc "Changes an item's fields (normalize afterwards)."
  def update(timeline, id, attrs) do
    Map.new(timeline, fn {track, items} ->
      {track, Enum.map(items, &if(&1["id"] == id, do: Map.merge(&1, attrs), else: &1))}
    end)
  end

  @doc "Moves a clip to `index` on the main track; the others close up around it."
  def move(timeline, id, index) do
    clips = timeline["clips"]

    case Enum.find(clips, &(&1["id"] == id)) do
      nil ->
        timeline

      clip ->
        rest = Enum.reject(clips, &(&1["id"] == id))
        %{timeline | "clips" => List.insert_at(rest, clamp(index, 0, length(rest)), clip)}
    end
  end

  @doc """
  Cuts the clip under `at` (milliseconds into the cut) in two there. Nothing
  happens within a tenth of a second of either end.
  """
  def split(timeline, at) do
    %{clips: clips} = layout(timeline)

    case Enum.find(clips, &(at > &1["start"] and at < &1["start"] + &1["length"])) do
      nil ->
        timeline

      clip ->
        offset = at - clip["start"]

        if offset < @min_take or clip["length"] - offset < @min_take do
          timeline
        else
          {first, second} = halves(clip, offset)
          clean = &Map.drop(&1, ["start", "length"])

          clips =
            Enum.flat_map(timeline["clips"], fn c ->
              if c["id"] == clip["id"], do: [clean.(first), clean.(second)], else: [c]
            end)

          %{timeline | "clips" => clips}
        end
    end
  end

  defp halves(%{"kind" => "take"} = clip, offset) do
    cut = clip["in"] + offset
    {%{clip | "out" => cut}, %{clip | "id" => new_id("c"), "in" => cut}}
  end

  defp halves(%{"kind" => "still"} = clip, offset) do
    {%{clip | "duration" => offset},
     %{clip | "id" => new_id("c"), "duration" => clip["duration"] - offset}}
  end
end
