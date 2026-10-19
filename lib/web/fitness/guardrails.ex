defmodule Web.Fitness.Guardrails do
  @moduledoc """
  The block's stopping rules, applied before a target is given
  (`docs/get-sharp-handoff.md` §3.2):

    * **stop**: pain 5 or more, or pain risen three check-ins running.
      A `plyo_locomotion` lift gets no target, only its substitute; any
      other lift is held as below.
    * **hold**: pain 3 or 4, or the lift's movement pattern over 1.5 on
      the acute:chronic ratio. No step up in weight.
    * **green**: neither.

  Pain is the latest check-in made in the last two days; an older one says
  nothing about today. These are plain functions of the check-ins and the
  entries, so the page, the report and the tests read the same verdict.
  """

  alias Web.Fitness.Training

  @fresh_days 2

  @doc """
  The day's verdict for a lift: `{:green | :hold | :stop, [reason]}`.
  `checkins` are newest first; `entries` are `Training.entries/2`'s.
  """
  def state(rule, checkins, entries, %Date{} = date) do
    pain = fresh_pain(checkins, date)
    rising? = rising?(checkins)
    ratio = rule && Training.acwr(entries, rule.pattern, date)

    reasons =
      [
        pain && pain >= 5 && {:stop, "pain #{pain} of 10"},
        rising? && {:stop, "pain rising three check-ins running"},
        pain && pain in 3..4 && {:hold, "pain #{pain} of 10"},
        is_number(ratio) && ratio > 1.5 &&
          {:hold, "#{pattern(rule)} load at #{ratio}× its average"}
      ]
      |> Enum.filter(& &1)

    cond do
      Enum.any?(reasons, &match?({:stop, _}, &1)) -> {:stop, Enum.map(reasons, &elem(&1, 1))}
      reasons != [] -> {:hold, Enum.map(reasons, &elem(&1, 1))}
      true -> {:green, []}
    end
  end

  @doc """
  A target with the verdict applied: a step up becomes the same weight
  under hold (and under stop, for a lift that is not plyometric); a
  plyometric lift under stop gets no target.
  """
  def apply_to(nil, _rule, _state), do: nil
  def apply_to(target, _rule, {:green, _}), do: target

  def apply_to(_target, %{pattern: "plyo_locomotion"}, {:stop, _}), do: nil

  def apply_to(%{reason: :up} = target, rule, {_hold_or_stop, _}),
    do: %{target | weight: target.weight - rule.increment, reason: :hold}

  def apply_to(target, _rule, _state), do: target

  @doc "What a stopped lift becomes, from the block's `substitutes`, or nil."
  def substitute(%{substitutes: subs}, %{slug: slug, pattern: "plyo_locomotion"}),
    do: Map.get(subs, slug)

  def substitute(_block, _rule), do: nil

  @doc "The verdict in words: `Hold: pain 3 of 10`."
  def line({:green, _}), do: nil

  def line({state, reasons}),
    do: "#{state |> to_string() |> String.capitalize()}: #{Enum.join(reasons, "; ")}"

  defp fresh_pain([%{date: date, pain: pain} | _], today) when is_integer(pain) do
    if Date.diff(today, date) in 0..@fresh_days, do: pain
  end

  defp fresh_pain(_checkins, _today), do: nil

  defp rising?([%{pain: a}, %{pain: b}, %{pain: c} | _])
       when is_integer(a) and is_integer(b) and is_integer(c),
       do: a > b and b > c

  defp rising?(_checkins), do: false

  defp pattern(%{pattern: p}), do: WebWeb.FitnessCharts.pattern_name(p) |> String.downcase()
end
