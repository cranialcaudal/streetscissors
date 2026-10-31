defmodule Web.Fitness.Plates do
  @moduledoc """
  What goes on the bar: the plates a side for a weight, and the warm-up ramp
  to a top set. The gym's bars and plates are the author's, in the private
  `content/fitness/gym.json`:

      {"plates": [45, 35, 25, 10, 5, 2.5],
       "bars": {"barbell": 45, "hexbar": 55, "smith": 20},
       "lifts": {"hex-flat-side-deadlift": "hexbar", "smith-bench-press": "smith"}}

  `lifts` names which bar each exercise is loaded on; an exercise not named
  there is not a bar lift and gets no plate line. Without the file, nothing
  is a bar lift.
  """

  @doc "The gym's settings, or the empty defaults."
  def settings do
    path = Path.join(Web.Fitness.Vault.base_path(), "gym.json")

    with {:ok, body} <- File.read(path),
         {:ok, %{} = gym} <- Jason.decode(body) do
      %{
        plates:
          gym
          |> Map.get("plates", [45, 35, 25, 10, 5, 2.5])
          |> Enum.map(&(&1 * 1.0))
          |> Enum.sort(:desc),
        bars: Map.new(Map.get(gym, "bars", %{}), fn {k, v} -> {k, v * 1.0} end),
        lifts: Map.get(gym, "lifts", %{})
      }
    else
      _ -> %{plates: [], bars: %{}, lifts: %{}}
    end
  end

  @doc "The bar an exercise is loaded on, `{name, lbs}`, or nil."
  def bar(slug, gym \\ settings()) do
    with name when is_binary(name) <- gym.lifts[slug],
         lbs when is_number(lbs) <- gym.bars[name] do
      {name, lbs}
    else
      _ -> nil
    end
  end

  @doc """
  The plates a side for `total` on a bar of `bar` lbs, heaviest first, as
  `{plates, left_over}`: what could not be made with the plates there are
  (0.0 when the weight loads exactly). Nil when the weight is under the bar.
  """
  def per_side(total, bar, plates) when is_number(total) and is_number(bar) do
    side = (total - bar) / 2

    if side < 0 do
      nil
    else
      {used, left} =
        Enum.reduce(plates, {[], side}, fn plate, {used, left} ->
          n = trunc(Float.floor((left + 0.001) / plate))
          {used ++ List.duplicate(plate, n), left - n * plate}
        end)

      {used, Float.round(left * 2, 1)}
    end
  end

  @doc """
  The warm-up to a top set of `top` lbs, as `[{reps, lbs}]`: 5 at about half,
  3 at about 70%, 1 at about 85%, each rounded down to what loads with the
  smallest pair of plates, and none lighter than the bar.
  """
  def ramp(top, bar, plates) when is_number(top) and is_number(bar) do
    step = 2 * Enum.min(plates, fn -> 2.5 end)

    for {reps, pct} <- [{5, 0.5}, {3, 0.7}, {1, 0.85}] do
      raw = top * pct
      lbs = max(bar, bar + Float.floor((raw - bar) / step) * step)
      {reps, Float.round(lbs * 1.0, 1)}
    end
    |> Enum.uniq_by(&elem(&1, 1))
  end

  @doc "Plates a side as words: `45 + 25 + 5`, or `the bar alone`."
  def describe([]), do: "the bar alone"
  def describe(plates), do: Enum.map_join(plates, " + ", &Web.Fitness.Entry.number/1)
end
