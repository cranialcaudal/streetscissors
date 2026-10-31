defmodule Web.Fitness.Session do
  @moduledoc """
  The admin's training day as structure, for the day page's session view:
  the day's markdown (`Web.Fitness.Vault.day_markdown/1`, already cut to the
  running week) read into modules, and each module into the things done in
  it, in order:

    * an **exercise**: one checklist line naming an exercise, with its plan
      from `Web.Fitness.Coach` (the first line naming a slug is its plan; a
      later line naming it again is a note);
    * a **superset**: the exercises under a `#### Superset A…` heading, done
      in turn with one rest after the last;
    * a **circuit**: a kettlebell warm-up run on its own timer
      (`Web.Fitness.Vault.circuit/1`);
    * a **note**: a checklist line naming no exercise ("Week 1 of 8: …", a
      guardrail).

  The things that are done one after another are the session's **stations**:
  an exercise, a superset or a circuit. Focus mode shows one station at a
  time; the list shows them all, the finished ones folded.

  Nothing here renders HTML except `inline/1`, which turns one line's text
  (its `[[slug|Name]]` links, its bold) into safe HTML.
  """

  alias Web.Fitness.{Entry, Vault}

  @line ~r/^\s*[-*]\s+\[[ xX]\]\s*(.*)$/u
  @link ~r/\[\[([a-z0-9][a-z0-9-]*)(?:\|([^\]]+))?\]\]/u

  @doc """
  The day's modules and stations. `coach` is `Web.Fitness.Coach.day/3`'s map,
  `logged` today's entries (`Web.Fitness.exercise_logs_on/1`), `activities`
  the day's Komoot tours as `activity/2` gives them: a ride is what a brief
  (a ride, the cya loop) shows and is done by, a run what the run line
  (`outfield-jog`) shows and is done by, so neither is typed in by hand.
  """
  def build(day_slug, coach, logged, activities \\ []) do
    case Vault.day_markdown(day_slug) do
      {:ok, _meta, md} -> from_markdown(md, coach, logged, activities)
      :error -> %{modules: [], stations: []}
    end
  end

  @bikes ~w(racebike touringbicycle mtb mtb_easy mtb_advanced downhillbike)
  @run_slug "outfield-jog"

  @doc "A Komoot tour as the session shows it."
  def activity(ride, power \\ nil) do
    %{
      id: ride.id,
      kind:
        if(ride.sport in @bikes,
          do: :ride,
          else: if(ride.sport == "jogging", do: :run, else: :other)
        ),
      km: ride.distance_m && Float.round(ride.distance_m / 1000, 1),
      minutes: round((ride.time_in_motion_s || ride.duration_s || 0) / 60),
      watts: power && power["avg_w"] && round(power["avg_w"]),
      peak_watts: power && power["peak_w"] && round(power["peak_w"])
    }
  end

  @doc false
  def from_markdown(md, coach, logged, activities \\ []) do
    {modules, _state} =
      md
      |> String.split("\n")
      |> Enum.reduce(
        {[], %{seen: MapSet.new(), group: nil, circuit?: false}},
        &read_line(&1, &2, coach)
      )

    modules =
      modules
      |> Enum.reverse()
      |> Enum.map(fn m -> %{m | items: m.items |> Enum.reverse() |> Enum.map(&close_group/1)} end)
      |> Enum.reject(&(&1.items == []))
      |> Enum.map(&brief/1)

    stations =
      for {m, mi} <- Enum.with_index(modules),
          item <- m.items,
          item.type in [:exercise, :superset, :circuit, :brief] do
        Map.merge(item, %{module: m.title, module_index: mi})
      end
      |> Enum.with_index()
      |> Enum.map(fn {s, i} -> Map.merge(s, %{index: i, done?: done?(s, logged)}) end)
      |> Enum.map(&with_komoot(&1, activities))

    # A brief (a ride, the cya loop) is recorded by Komoot, not here: it is
    # done when the day's ride has come in, or once anything after it is.
    stations =
      Enum.map(stations, fn
        %{type: :brief} = s ->
          %{s | done?: s.komoot != [] or Enum.any?(stations, &(&1.index > s.index and &1.done?))}

        s ->
          s
      end)

    %{modules: modules, stations: stations}
  end

  # The day's rides on a brief, the day's runs on the run line; a run from
  # Komoot is the run done.
  defp with_komoot(%{type: :brief} = s, activities),
    do: Map.put(s, :komoot, Enum.filter(activities, &(&1.kind == :ride)))

  defp with_komoot(%{type: :exercise, slug: @run_slug} = s, activities) do
    runs = Enum.filter(activities, &(&1.kind == :run))
    %{Map.put(s, :komoot, runs) | done?: s.done? or runs != []}
  end

  defp with_komoot(s, _activities), do: Map.put(s, :komoot, [])

  # A module with nothing to log (a ride, the cya loop) is still part of the
  # day, in its place: its notes become one station, a brief, so focus mode
  # shows it rather than skipping it.
  defp brief(%{items: items} = m) do
    if Enum.any?(items, &(&1.type in [:exercise, :superset, :circuit])) do
      m
    else
      notes = for %{type: :note, text: t} <- items, do: t
      %{m | items: [%{type: :brief, title: m.title, notes: notes}]}
    end
  end

  defp read_line(line, {modules, state}, coach) do
    cond do
      marker = Vault.circuit_marker(line) ->
        {slug, circuit} = marker

        {add(modules, %{type: :circuit, slug: slug, circuit: circuit, plan: coach[slug]}),
         %{state | circuit?: true, group: nil}}

      Vault.circuit_close?(line) ->
        {modules, %{state | circuit?: false}}

      state.circuit? ->
        {modules, state}

      String.starts_with?(line, "### ") ->
        title = line |> String.trim_leading("#") |> String.trim()
        {[%{title: title, items: []} | modules], %{state | group: nil}}

      String.starts_with?(line, "#### ") ->
        title = line |> String.trim_leading("#") |> String.trim()

        if title =~ ~r/^superset\b/i do
          {add(modules, %{type: :superset, title: title, items: []}), %{state | group: title}}
        else
          {add(modules, %{type: :heading, text: title}), %{state | group: nil}}
        end

      m = Regex.run(@line, line) ->
        [_, body] = m

        item =
          case Regex.run(@link, body) do
            [_, slug | _] ->
              if MapSet.member?(state.seen, slug) or is_nil(coach[slug]),
                do: %{type: :note, text: body},
                else: %{type: :exercise, slug: slug, text: body, plan: coach[slug]}

            nil ->
              %{type: :note, text: body}
          end

        seen = if item.type == :exercise, do: MapSet.put(state.seen, item.slug), else: state.seen
        state = %{state | seen: seen}

        if state.group && item.type == :exercise,
          do: {add_to_group(modules, item), state},
          else: {add(modules, item), state}

      true ->
        {modules, state}
    end
  end

  # A line before any "###" heading opens a module of its own.
  defp add([], item), do: [%{title: nil, items: [item]}]
  defp add([m | rest], item), do: [%{m | items: [item | m.items]} | rest]

  defp add_to_group([%{items: [%{type: :superset} = g | items]} = m | rest], item),
    do: [%{m | items: [%{g | items: [item | g.items]} | items]} | rest]

  defp add_to_group(modules, item), do: add(modules, item)

  defp close_group(%{type: :superset, items: items} = g), do: %{g | items: Enum.reverse(items)}
  defp close_group(item), do: item

  # ── What a station needs ──────────────────────────────────────────────────

  @doc "The slugs a station logs: one, or a superset's two or more."
  def slugs(%{type: :superset, items: items}), do: Enum.map(items, & &1.slug)
  def slugs(%{type: :brief}), do: []
  def slugs(%{slug: slug}), do: [slug]

  @doc "True when every exercise in the station is logged as far as it asks."
  def done?(%{type: :superset, items: items}, logged),
    do: items != [] and Enum.all?(items, &done?(&1, logged))

  def done?(%{type: :circuit, slug: slug}, logged), do: todays(logged, slug) != nil

  def done?(%{type: :exercise, slug: slug, plan: plan}, logged) do
    case todays(logged, slug) do
      nil -> false
      log -> not chips?(plan) or length(Entry.set_list(log.metrics)) >= planned_sets(plan)
    end
  end

  def done?(_item, _logged), do: false

  @doc "Today's entry for a slug, the newest when there are two."
  def todays(logged, slug), do: logged |> Enum.filter(&(&1.exercise.slug == slug)) |> List.last()

  @doc "Today's sets for a slug."
  def sets(logged, slug) do
    case todays(logged, slug) do
      nil -> []
      log -> Entry.set_list(log.metrics)
    end
  end

  @doc "The first station not yet done, else the last."
  def current(%{stations: []}), do: 0

  def current(%{stations: stations}) do
    case Enum.find(stations, &(not &1.done?)) do
      nil -> length(stations) - 1
      s -> s.index
    end
  end

  # ── The sets a lift asks for (shared with the page's chips) ───────────────

  @doc "A lift gets set buttons: sets of reps, loaded or not, and not held today."
  def chips?(nil), do: false

  def chips?(plan) do
    plan.prescription.kind in [:weight, :reps] and is_integer(plan.defaults.reps) and
      elem(plan.verdict, 0) != :stop
  end

  @doc """
  How many sets the day asks for: its own line, else the block's target.
  Not the form's defaults, which take today's entry as "last time" the
  moment a first set is logged.
  """
  def planned_sets(plan),
    do: plan.prescription.sets || (plan.target && plan.target.sets) || 3

  @doc """
  The next set: the last one logged today again, else the target (the plan's
  numbers when there is none). Once today is logged, Coach's target is
  already the next session's, which is why the logged sets lead.
  """
  def next_set(plan, done) do
    case List.last(done) do
      nil -> %{"w" => plan.defaults.weight, "r" => plan.defaults.reps, "rpe" => nil}
      last -> %{"w" => last["w"], "r" => last["r"], "rpe" => nil}
    end
  end

  @doc "A set as its button says it: `135×3`, `8 reps`, `1 rep`."
  def set_label(%{"w" => w, "r" => r}) when is_number(w) and w > 0,
    do: "#{Entry.number(w * 1.0)}×#{r}"

  def set_label(%{"r" => 1}), do: "1 rep"
  def set_label(%{"r" => r}), do: "#{r} reps"

  @doc """
  Seconds of rest after a set: what the line says ("90 sec between sets"),
  else 2.5 minutes on a block lift worked heavy (a range topping out at 10 or
  under) and 1.5 on the rest (the block's Design).
  """
  def rest_seconds(plan) do
    cond do
      is_integer(plan.prescription[:rest]) -> plan.prescription.rest
      plan.rule && plan.rule.high <= 10 -> 150
      true -> 90
    end
  end

  # ── One line's text as HTML ───────────────────────────────────────────────

  @doc """
  A line's text as safe HTML: `[[slug|Name]]` becomes a link to the wiki page
  that also opens the figure sheet, `**bold**` stays bold. Everything else is
  escaped.
  """
  def inline(text) do
    text
    |> Phoenix.HTML.html_escape()
    |> Phoenix.HTML.safe_to_string()
    |> then(
      &Regex.replace(@link, &1, fn _, slug, name ->
        name = if name == "", do: slug, else: name

        ~s(<a href="/fitness/wiki/#{slug}" class="gym-link session-figure-link" data-figure="#{slug}">#{name}</a>)
      end)
    )
    |> then(&Regex.replace(~r/\*\*(.+?)\*\*/u, &1, "<strong>\\1</strong>"))
    |> Phoenix.HTML.raw()
  end

  @doc "A line's text with its first link taken off the front: what follows the name."
  def detail(text) do
    text
    |> String.replace(~r/^\s*(?:\*\*)?\[\[[^\]]+\]\](?:\*\*)?\s*[;:—–-]?\s*/u, "")
  end

  @doc "The name a line gives its exercise, else the slug."
  def name(%{text: text, slug: slug}) do
    case Regex.run(@link, text) do
      [_, _, name] when name != "" -> name
      _ -> slug
    end
  end
end
