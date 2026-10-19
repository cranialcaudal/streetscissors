defmodule Web.Fitness.Block do
  @moduledoc """
  A training block: so many weeks from a Monday, each week in a phase, and
  the lifts that progress through it. A block is a file in the vault's
  `blocks/` folder (`blocks/get-sharp.md`), and the file is the only place
  its dates and lifts are written:

      title: Get Sharp
      start: 2026-10-26
      weeks: 8
      phases: 1 Baseline; 2-3 Accumulate; 4 Deload; 5-7 Intensify; 8 Test
      lifts: hexbar-rdl 5-8 +5 hinge; box-jumps 3-3 +0 plyo_locomotion

  A lift is `<wiki slug> <low>-<high> +<pounds> <pattern>`: the rep range,
  what a step up adds, and the movement pattern its load counts toward. A
  file that cannot be read as a block is no block; nothing here raises.
  """

  alias Web.Fitness.Vault

  @phases ~w(Baseline Accumulate Deload Intensify Test)

  @doc "Every readable block in the vault, earliest first."
  def load do
    Path.join([Vault.base_path(), "blocks", "*.md"])
    |> Path.wildcard()
    |> Enum.flat_map(fn path ->
      case parse(Path.basename(path, ".md"), Vault.parse_frontmatter(path)) do
        {:ok, block} -> [block]
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
      if Date.compare(date, block.start) != :lt and Date.compare(date, block.finish) != :gt do
        week = div(Date.diff(date, block.start), 7) + 1
        Map.merge(block, %{week: week, phase: Map.get(block.phases, week)})
      end
    end)
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
         weeks: weeks,
         finish: Date.add(start, weeks * 7 - 1),
         phases: phases,
         lifts: lifts(meta["lifts"] || "")
       }}
    else
      _ -> :error
    end
  end

  # "1 Baseline; 2-3 Accumulate" -> %{1 => "Baseline", 2 => "Accumulate", ...}.
  # Every week must have exactly one phase, and only the five known names:
  # the progression rule is written per phase.
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

    if Enum.sort(weeks_named) == Enum.to_list(1..weeks),
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
