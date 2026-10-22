defmodule Web.Fitness.Prescription do
  @moduledoc """
  What the plan asks of an exercise, read off the day's own lines:

      - [ ] [[dumbbell-rdl|Dumbbell RDL]]; 3 x 10, 30 lb dumbbells. Groove the hinge…
      - [ ] [[side-planks|Side Planks]]; 3 x 30–40 sec/side.
      - [ ] **[[push-ups|Push-ups]]** — 3 × 12

  Each becomes `%{slug, name, text, sets, reps, seconds, metres, weight,
  kind}`: the first `N x` is the sets, what follows it the reps (a range is
  `{low, high}`), a time in seconds or minutes a hold, a distance in metres
  a carry, a weight in pounds the starting load. The `kind` is what the log
  form asks for (`WebWeb.FitnessLive.Index`):

    * `:weight` — weight, sets, reps, RPE (a loaded lift);
    * `:reps` — sets and reps, an optional added weight (bodyweight work);
    * `:hold` — sets and seconds;
    * `:carry` — weight, sets and metres;
    * `:jump` — sets, reps and height;
    * `:circuit` — a whole circuit (`Web.Fitness.Vault.circuit/1`): its
      rounds as the sets, logged once by the day page's circuit timer.

  A day is the plan; the logs are what was done. `planned_sets/1` is the
  day's sets, which compliance counts against. Universal: it reads any
  line in the vault's checklist form, whatever the exercise.
  """

  alias Web.Fitness.Vault

  @line ~r/^\s*-\s*\[[ xX]\]\s*(?:\*\*)?\[\[([a-z0-9][a-z0-9-]*)(?:\|([^\]]+))?\]\](?:\*\*)?\s*[;:—–-]?\s*(.*)$/u

  @doc """
  The day's prescriptions, one per exercise in the order they first appear;
  an exercise on two lines (a circuit and the main block) keeps the line that
  says the most, the one with a set count.
  """
  def for_day(day), do: day |> lines() |> unique()

  @doc "Every exercise line of a day, repeats included: what compliance counts."
  def lines(day) do
    case Vault.day_markdown(day) do
      {:ok, _meta, md} -> parse(md)
      :error -> []
    end
  end

  @doc false
  def unique(lines) do
    order = lines |> Enum.map(& &1.slug) |> Enum.uniq()
    best = Enum.group_by(lines, & &1.slug)

    for slug <- order do
      candidates = best[slug]
      Enum.find(candidates, hd(candidates), &is_integer(&1.sets))
    end
  end

  @doc "The prescription for one exercise on a day, or nil."
  def find(day, slug), do: Enum.find(for_day(day), &(&1.slug == slug))

  @doc "A prescription for an exercise the day's plan does not list: its kind from its name alone."
  def bare(slug, name),
    do: slug |> read(name, "", {nil, nil}) |> Map.put(:section, %{title: nil, minutes: nil})

  defp section(line) do
    title = line |> String.trim_leading("#") |> String.trim()

    minutes =
      case Regex.run(~r/\((\d+)\s*min\)/i, title) do
        [_, n] -> String.to_integer(n)
        _ -> nil
      end

    %{title: title, minutes: minutes}
  end

  @doc "The sets a day prescribes across its exercises (1 for a line with no count)."
  def planned_sets(prescriptions), do: prescriptions |> Enum.map(&(&1.sets || 1)) |> Enum.sum()

  @doc false
  def parse(markdown) do
    markdown
    |> String.split("\n")
    |> Enum.flat_map_reduce(
      {{nil, nil}, %{title: nil, minutes: nil}, false},
      fn line, {heading, section, in_circuit?} ->
        cond do
          # A circuit (`Vault.circuit/1`) is one line of its rounds, logged
          # whole; the moves inside it are not lines of their own.
          marker = Vault.circuit_marker(line) ->
            {slug, c} = marker
            {[circuit_line(slug, c, section)], {heading, section, true}}

          Vault.circuit_close?(line) ->
            {[], {heading, section, false}}

          in_circuit? ->
            {[], {heading, section, true}}

          # A "### Lower … (75 Min)" heading is the section the lines under it
          # belong to, and its minutes are the session's length.
          String.starts_with?(line, "### ") ->
            {[], {sets_reps(line), section(line), false}}

          # A smaller heading's "4 x 6-10" is the default for the lines under it.
          String.starts_with?(line, "#") ->
            {[], {sets_reps(line), section, false}}

          m = Regex.run(@line, line) ->
            [_, slug, name | rest] = m

            {[Map.put(read(slug, name, List.first(rest) || "", heading), :section, section)],
             {heading, section, false}}

          true ->
            {[], {heading, section, false}}
        end
      end
    )
    |> elem(0)
  end

  defp circuit_line(slug, c, section) do
    %{
      slug: slug,
      name: c.name,
      text: "#{c.rounds} rounds",
      sets: c.rounds,
      reps: nil,
      seconds: nil,
      metres: nil,
      weight: c.weight,
      kind: :circuit,
      section: section
    }
  end

  defp read(slug, name, text, {head_sets, head_reps}) do
    text = text |> String.replace("**", "") |> String.trim()

    {sets, reps} =
      case sets_reps(text) do
        {nil, nil} -> {head_sets, leading_reps(text) || head_reps}
        {nil, reps} -> {head_sets, reps}
        found -> found
      end

    seconds = seconds(text)
    metres = metres(text)

    %{
      slug: slug,
      name: if(name in [nil, ""], do: slug, else: name),
      text: text,
      sets: sets,
      reps: reps,
      seconds: seconds,
      metres: metres,
      weight: weight(text),
      kind: kind(slug, text, seconds, metres)
    }
  end

  # "3 x 10", "3 × 12", "3 x 10–12/leg", "3 x AMRAP", "ramp 5/3/1, then 3 x 3".
  defp sets_reps(text) do
    case Regex.run(~r/(\d+)\s*[x×]\s*(AMRAP|\d+)(?:\s*[–-]\s*(\d+))?/iu, text) do
      [_, s, "AMRAP" <> _ | _] ->
        {String.to_integer(s), :amrap}

      [_, s, low, high] ->
        {String.to_integer(s), {String.to_integer(low), String.to_integer(high)}}

      [_, s, n] ->
        {String.to_integer(s), {String.to_integer(n), String.to_integer(n)}}

      _ ->
        sets_only(text)
    end
    |> case do
      {s, :amrap} when is_integer(s) -> {s, :amrap}
      other -> other
    end
  end

  # A line with only its reps: "8–12", "6/direction", "10–15".
  defp leading_reps(text) do
    case Regex.run(~r/\A(\d+)(?:\s*[–-]\s*(\d+))?(?!\d)(?!\s*(?:sec|s\b|min|m\b|lb))/u, text) do
      [_, low, high] -> {String.to_integer(low), String.to_integer(high)}
      [_, n] -> {String.to_integer(n), String.to_integer(n)}
      _ -> nil
    end
  end

  defp sets_only(text) do
    case Regex.run(~r/\b(AMRAP)\b/i, text) do
      [_, _] -> {nil, :amrap}
      _ -> {nil, nil}
    end
  end

  # "30–40 sec", "20-30 sec", "2 min/side": the low end, in seconds.
  defp seconds(text) do
    cond do
      m = Regex.run(~r/(\d+)(?:\s*[–-]\s*\d+)?\s*(?:sec|s\b)/u, text) ->
        String.to_integer(Enum.at(m, 1))

      m = Regex.run(~r/(\d+)(?:\s*[–-]\s*\d+)?\s*min\b/u, text) ->
        String.to_integer(Enum.at(m, 1)) * 60

      true ->
        nil
    end
  end

  defp metres(text) do
    case Regex.run(~r/(\d+)\s*m\b/u, text) do
      [_, n] -> String.to_integer(n)
      _ -> nil
    end
  end

  defp weight(text) do
    # Not "add 5 lb" or "+5 lb", which is the step, not the load.
    case Regex.run(~r/(?<!add )(?<!\+)(?<!\d)(\d+(?:\.\d+)?)\s*(?:lbs?|pounds?)\b/iu, text) do
      [_, n] ->
        {w, _} = Float.parse(n)
        w

      _ ->
        nil
    end
  end

  defp kind(slug, text, seconds, metres) do
    cond do
      String.contains?(slug, "jump") and not String.contains?(slug, "rope") ->
        :jump

      is_integer(metres) ->
        :carry

      is_integer(seconds) ->
        :hold

      text =~ ~r/bodyweight|AMRAP/i ->
        :reps

      slug =~
        ~r/push-up|pull-up|chin-up|plank|hang|bridge|dead-bug|hollow|knee-raise|leg-raise|burpee/ and
          not (text =~ ~r/\d+\s*lb/) ->
        :reps

      true ->
        :weight
    end
  end
end
