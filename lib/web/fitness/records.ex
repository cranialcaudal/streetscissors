defmodule Web.Fitness.Records do
  @moduledoc """
  An exercise's best, for the day page's "new best" and the session summary.
  An entry is scored by what it can be compared on:

    * a loaded lift: its best set's estimated one-rep max (Epley,
      `Web.Fitness.Progression.e1rm/2`), `{:e1rm, lbs}`;
    * a lift at bodyweight: its most reps in one set, `{:reps, n}`;
    * a swim counted in laps: `{:laps, n}`, from a result like "24 laps".

  A score only beats a score of the same kind, so a pull-up done with a belt
  for the first time is not a "best" against the bodyweight sets before it.
  """

  alias Web.Fitness.{Entry, Progression}

  @doc "An entry's score, or nil when there is nothing to compare."
  def score(%{metrics: metrics}) when is_map(metrics) do
    sets = Entry.set_list(metrics)

    e1rms = for %{"w" => w, "r" => r} <- sets, e = Progression.e1rm(w, r), do: e
    reps = for %{"r" => r} = set <- sets, is_integer(r), not loaded?(set), do: r

    cond do
      e1rms != [] -> {:e1rm, Enum.max(e1rms)}
      reps != [] -> {:reps, Enum.max(reps)}
      laps = laps(metrics["result"]) -> {:laps, laps}
      true -> nil
    end
  end

  def score(_entry), do: nil

  defp loaded?(%{"w" => w}) when is_number(w) and w > 0, do: true
  defp loaded?(_set), do: false

  defp laps("" <> result) do
    case Regex.run(~r/(\d+)\s*laps?\b/i, result) do
      [_, n] -> String.to_integer(n)
      _ -> nil
    end
  end

  defp laps(_), do: nil

  @doc """
  The best score among `entries` of the same kind as `score`, or nil.
  """
  def best(entries, {kind, _}) do
    entries
    |> Enum.map(&score/1)
    |> Enum.filter(&match?({^kind, _}, &1))
    |> Enum.max_by(&elem(&1, 1), fn -> nil end)
  end

  @doc """
  `{:best, score, previous}` when `entry` beats every earlier entry of the
  same kind (`earlier`: the exercise's entries from before its day), else
  nil. A first entry is a start, not a best: there is nothing it beat.
  """
  def new_best(entry, earlier) do
    with {_, value} = score <- score(entry),
         {_, before} = previous <- best(earlier, score),
         true <- value > before do
      {:best, score, previous}
    else
      _ -> nil
    end
  end

  @doc "A score as the page says it: `≈162 lb e1RM`, `4 reps`, `26 laps`."
  def describe({:e1rm, lbs}), do: "≈#{Entry.number(Float.round(lbs * 1.0, 0))} lb est. 1RM"
  def describe({:reps, n}), do: "#{n} #{if n == 1, do: "rep", else: "reps"}"
  def describe({:laps, n}), do: "#{n} laps"
end
