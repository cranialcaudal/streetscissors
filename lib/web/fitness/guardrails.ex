defmodule Web.Fitness.Guardrails do
  @moduledoc """
  The block's stopping rules, applied to one exercise before a target is
  given. Every rule is the author's, from the vault:

    * **a check-in** (`Web.Fitness.Checks`, `content/fitness/checkins.md`):
      an answer listed under a check's `hold` holds the exercises it
      `guards` (no step up in weight), one under `stop` stops them (no
      target; the block's substitute, if it names one), each with the advice
      the file gives for that answer. A guarded check whose answer has
      worsened three check-ins running holds as well;
    * **the load**: a tracked lift whose movement pattern is over 1.5 on the
      acute:chronic ratio is held.

  Only the latest check-in made in the last two days counts: an older one
  says nothing about today. These are plain functions of the check-ins and
  the entries, so the day page, the log form, the report and the tests all
  read one verdict.
  """

  alias Web.Fitness.{Checks, Training}

  @fresh_days 2

  @doc """
  The day's verdict for an exercise: `{:green | :hold | :stop, [reason]}`.
  `rule` is the block's lift or nil (an exercise the block does not track
  can still be guarded); `checkins` newest first; `entries` from
  `Training.entries/2`; `checks` from `Checks.all/0`.
  """
  def state(slug, rule, checkins, entries, %Date{} = date, checks) do
    fresh = fresh(checkins, date)

    from_checks =
      for check <- Checks.guarding(checks, slug),
          answer = fresh && fresh.answers[check.id],
          answer do
        case Checks.level(check, answer) do
          :green -> nil
          level -> {level, reason(check, answer)}
        end
      end

    worsening =
      for check <- Checks.guarding(checks, slug),
          worsening?(check, checkins),
          do: {:hold, "#{check.label} worse three check-ins running"}

    ratio = rule && Training.acwr(entries, rule.pattern, date)

    load =
      if is_number(ratio) and ratio > 1.5,
        do: [
          {:hold,
           "#{WebWeb.FitnessCharts.pattern_name(rule.pattern) |> String.downcase()} load at #{ratio}× its average"}
        ],
        else: []

    verdict(Enum.reject(from_checks, &is_nil/1) ++ worsening ++ load)
  end

  @doc """
  The day's standing, whatever the exercise: every check answered off its
  good state today, as `[{label, answer, level}]`.
  """
  def today(checkins, %Date{} = date, checks) do
    case fresh(checkins, date) do
      nil ->
        []

      checkin ->
        for %{kind: :state} = check <- checks,
            answer = checkin.answers[check.id],
            answer,
            level = Checks.level(check, answer),
            level != :green or answer != List.first(check.states),
            do: {check.label, answer, level}
    end
  end

  @doc """
  A target with the verdict applied: a step up becomes the same weight
  under hold, and a stopped exercise gets no target.
  """
  def apply_to(nil, _rule, _state), do: nil
  def apply_to(target, _rule, {:green, _}), do: target
  def apply_to(_target, _rule, {:stop, _}), do: nil

  def apply_to(%{reason: :up, weight: w} = target, rule, {:hold, _}) when is_number(w),
    do: %{target | weight: w - rule.increment, reason: :hold}

  def apply_to(target, _rule, _state), do: target

  @doc "What a stopped exercise becomes, from the block's `substitutes`, or nil."
  def substitute(%{substitutes: subs}, slug), do: Map.get(subs, slug)
  def substitute(_block, _slug), do: nil

  @doc "The verdict in words: `Hold: Achilles talking — skip the box jumps today`."
  def line({:green, _}), do: nil

  def line({state, reasons}),
    do: "#{state |> to_string() |> String.capitalize()}: #{Enum.join(reasons, "; ")}"

  defp verdict(reasons) do
    cond do
      Enum.any?(reasons, &match?({:stop, _}, &1)) ->
        {:stop, reasons |> Enum.map(&elem(&1, 1)) |> Enum.uniq()}

      reasons != [] ->
        {:hold, reasons |> Enum.map(&elem(&1, 1)) |> Enum.uniq()}

      true ->
        {:green, []}
    end
  end

  defp reason(check, answer) do
    case check.advice[answer] do
      nil -> "#{check.label} #{answer}"
      advice -> "#{check.label} #{answer} — #{advice}"
    end
  end

  defp fresh([%{date: date} = checkin | _], today) do
    if Date.diff(today, date) in 0..@fresh_days, do: checkin
  end

  defp fresh(_checkins, _today), do: nil

  # Three answers running, each further down the check's states than the last.
  defp worsening?(%{kind: :state, states: states} = check, [a, b, c | _]) do
    [ia, ib, ic] =
      Enum.map([a, b, c], &Enum.find_index(states, fn s -> s == &1.answers[check.id] end))

    is_integer(ia) and is_integer(ib) and is_integer(ic) and ia > ib and ib > ic
  end

  defp worsening?(_check, _checkins), do: false
end
