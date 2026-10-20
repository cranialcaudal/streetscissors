defmodule Web.Fitness.Block do
  @moduledoc """
  A training block: so many weeks from a Monday, each week in a phase, and
  the lifts that progress through it. A block is a file in the vault's
  `blocks/` folder (`blocks/get-sharp.md`), and the file is the only place
  its dates and lifts are written:

      title: Get Sharp
      start: 2026-10-26
      weeks: 8
      phases: 0 Setup; 1-2 Baseline; 3-6 Push; 7 Peak; 8 Deload
      top_set_rpe: 9
      hypothesis: 8 weeks, +0.25 lb/wk, hypertrophy → visible definition
      predict: bodyweight +0.25 lb/week; e1rm +10%; volume +20%; compliance 85%
      poses: front, side, back
      lifts: hex-flat-side-deadlift 3-3 +5 hinge; box-jumps 5-5 +0 plyo_locomotion
      substitutes: box-jumps step-ups; single-leg-calf-raises holds

  `start` is week 1's Monday. A week 0 in `phases` is the week before it,
  a setup week that belongs to the block but counts toward none of its
  numbers. The phases are `Setup`, `Baseline`, `Push`, `Peak` and `Deload`,
  each with its own rule (`Web.Fitness.Progression`). `top_set_rpe` is the
  hardest a top-of-range set may be and still earn the step (9: one rep in
  reserve; 8 when not given). `predict` is the hypothesis in measures the
  block report can check (`bodyweight`, `e1rm`, `volume`, `compliance`).

  A lift is `<wiki slug> <low>-<high> +<pounds> <pattern>`: the rep range,
  what a step up adds, and the movement pattern its load counts toward.
  `substitutes` (optional) names what a lift becomes when the guardrails
  stop it: a wiki slug, or a word. A file that cannot be read as a block is
  no block; nothing here raises.
  """

  alias Web.Fitness.Vault

  @phases ~w(Setup Baseline Push Peak Deload)

  @doc "Every readable block in the vault, earliest first."
  def load do
    Path.join([Vault.base_path(), "blocks", "*.md"])
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      case parse(Path.basename(path, ".md"), Vault.parse_frontmatter(path)) do
        {:ok, block} -> [Map.put(block, :body, body(path))]
        :error -> []
      end
    end)
    |> Enum.sort_by(& &1.start, Date)
  end

  @doc """
  The block running on `date`, with the week it is in and that week's phase,
  or nil when no block covers the day.
  """
  def current(%Date{} = date) do
    Enum.find_value(load(), fn block ->
      if Date.compare(date, block.opens) != :lt and Date.compare(date, block.finish) != :gt do
        at(block, week_of(date, block))
      end
    end)
  end

  @doc "The block week a date falls in: 1 from `start`, 0 the week before."
  def week_of(%Date{} = date, %{start: start}),
    do: Integer.floor_div(Date.diff(date, start), 7) + 1

  defp at(block, week), do: Map.merge(block, %{week: week, phase: Map.get(block.phases, week)})

  @doc """
  The block to report on for `date`: the one running, else the latest to
  have started, else the next to start, with the week clamped into its
  length (week 1 before it begins). Nil when the vault has no block.
  """
  def latest(%Date{} = date) do
    blocks = load()

    block =
      current(date) ||
        blocks |> Enum.filter(&(Date.compare(&1.start, date) != :gt)) |> List.last() ||
        List.first(blocks)

    case block do
      nil ->
        nil

      %{week: _} = running ->
        running

      block ->
        first = if Map.has_key?(block.phases, 0), do: 0, else: 1
        at(block, date |> week_of(block) |> max(first) |> min(block.weeks))
    end
  end

  @doc "A lift's rule in a block, or nil when the block does not track it."
  def lift(%{lifts: lifts}, slug), do: Map.get(lifts, slug)
  def lift(_block, _slug), do: nil

  @doc false
  def parse(slug, meta) do
    with title when is_binary(title) and title != "" <- meta["title"],
         {:ok, start} <- Date.from_iso8601(meta["start"] || ""),
         1 <- Date.day_of_week(start),
         {weeks, ""} when weeks > 0 <- Integer.parse(meta["weeks"] || ""),
         {:ok, phases} <- phases(meta["phases"] || "", weeks) do
      {:ok,
       %{
         slug: slug,
         title: title,
         start: start,
         opens: if(Map.has_key?(phases, 0), do: Date.add(start, -7), else: start),
         weeks: weeks,
         finish: Date.add(start, weeks * 7 - 1),
         phases: phases,
         top_set_rpe: rpe(meta["top_set_rpe"]),
         hypothesis: blank(meta["hypothesis"]),
         predict: predictions(meta["predict"] || ""),
         poses:
           meta["poses"]
           |> to_string()
           |> String.split(",", trim: true)
           |> Enum.map(&String.trim/1),
         lifts: lifts(meta["lifts"] || ""),
         substitutes: substitutes(meta["substitutes"] || "")
       }}
    else
      _ -> :error
    end
  end

  # The file's prose under its frontmatter: the experiment's framing.
  defp body(path) do
    case File.read(path) do
      {:ok, text} -> text |> String.replace(~r/\A---\n.*?\n---\n?/s, "") |> String.trim()
      _ -> ""
    end
  end

  # "bodyweight +0.25 lb/week; e1rm +10%" -> [%{measure, value, unit}].
  defp predictions(text) do
    for part <- String.split(text, ";", trim: true),
        [_, measure, value, unit] <-
          [Regex.run(~r/\A\s*([a-z0-9_]+)\s+([+-]?\d+(?:\.\d+)?)\s*(.*?)\s*\z/u, part)],
        {value, _} <- [Float.parse(value)],
        do: %{measure: measure, value: value, unit: unit, text: String.trim(part)}
  end

  defp rpe(text) do
    case text && Float.parse(text) do
      {v, _} when v >= 5 and v <= 10 -> v
      _ -> 8.0
    end
  end

  defp blank(nil), do: nil
  defp blank(text), do: if(String.trim(text) == "", do: nil, else: text)

  # "0 Setup; 1-2 Baseline" -> %{0 => "Setup", 1 => "Baseline", 2 => "Baseline"}.
  # Every week 1..weeks must have exactly one phase (week 0 may), and only
  # the five known names: the progression rule is written per phase.
  defp phases(text, weeks) do
    pairs =
      for part <- String.split(text, ";", trim: true),
          [range, name] <- [String.split(String.trim(part), " ", parts: 2)],
          name = String.trim(name),
          name in @phases,
          {from, to} <- [week_range(range)],
          week <- from..to//1,
          do: {week, name}

    weeks_named = Enum.map(pairs, &elem(&1, 0))

    if Enum.sort(weeks_named -- [0]) == Enum.to_list(1..weeks) and
         Enum.count(weeks_named, &(&1 == 0)) <= 1,
       do: {:ok, Map.new(pairs)},
       else: :error
  end

  # "2-3" -> {2, 3}, "4" -> {4, 4}; anything else an empty range.
  defp week_range(range) do
    case Enum.map(String.split(range, "-"), &integer/1) do
      [n] when is_integer(n) -> {n, n}
      [a, b] when is_integer(a) and is_integer(b) -> {a, b}
      _ -> {1, 0}
    end
  end

  defp integer(text) do
    case Integer.parse(text) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp substitutes(text) do
    for part <- String.split(text, ";", trim: true),
        [slug, instead] <- [String.split(String.trim(part), " ", parts: 2)],
        into: %{},
        do: {slug, String.trim(instead)}
  end

  # A lift that does not read is left out rather than spoiling the block.
  defp lifts(text) do
    for part <- String.split(text, ";", trim: true),
        [slug, range, "+" <> step, pattern] <- [String.split(String.trim(part))],
        Regex.match?(~r/\A[a-z0-9][a-z0-9-]*\z/, slug),
        [low, high] <- [String.split(range, "-")],
        {low, ""} <- [Integer.parse(low)],
        {high, ""} <- [Integer.parse(high)],
        {step, ""} <- [Float.parse(step)],
        low > 0 and high >= low,
        into: %{},
        do: {slug, %{slug: slug, low: low, high: high, increment: step, pattern: pattern}}
  end
end
