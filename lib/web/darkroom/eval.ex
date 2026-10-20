defmodule Web.Darkroom.Eval do
  @moduledoc """
  How well the colour prior and the taste model guess the author's own edits
  (docs/colour/contracts.md, "The held-out score"): leave one out over every
  saved edit (`Taste.examples/1` at weight 1.0, never a Taste-page choice),
  fit on the rest (`Taste.fit_examples/3`), and compare the guess with what
  was saved.

  * **Colour**: the distance between the guessed and the saved target, in
    `{rg, bg}` (log10 ratios), reported in hundredths of density, overall
    and per film group. (contracts.md asks for ΔE₀₀; until the pipeline has
    calibrated Lab, this is the honest unit the prior works in.)
  * **Sliders**: each slider's mean absolute error, in its own units.

  `run/1` writes `<archive>/.darkroom/eval/<timestamp>.json` and returns the
  scores with the change from the last file. A change to `Prior` or `Taste`
  should not make the mean colour error worse. `mix darkroom.eval` runs it.
  """

  alias Web.Darkroom.{Archive, Film, Taste}
  alias Web.Negatives

  def dir, do: Path.join([Negatives.base_path(), ".darkroom", "eval"])

  @doc "Scores the archive as it stands, keeps them, and compares with the last run."
  def run(opts \\ []) do
    prints = Keyword.get_lazy(opts, :prints, &Archive.prints/0)
    groups = Archive.groups(prints)
    scores = score(Taste.examples(prints), groups, Keyword.get(opts, :defaults, %{}))
    previous = latest()

    stamp = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601(:basic)
    File.mkdir_p!(dir())
    File.write!(Path.join(dir(), "#{stamp}.json"), Jason.encode!(scores, pretty: true))

    {:ok, %{scores: scores, previous: previous}}
  end

  @doc false
  def score(examples, groups, defaults \\ %{}) do
    indexed = Enum.with_index(examples)
    held = for {ex, i} <- indexed, ex.weight == 1.0, do: {ex, i}

    results =
      for {ex, i} <- held do
        rest = for {other, j} <- indexed, j != i, do: other
        model = Taste.fit_examples(rest, groups, defaults)
        %{group: ex.group, colour: colour_error(ex, model, groups), sliders: slider_errors(ex, model, defaults)}
      end

    colour = Enum.reject(results, &is_nil(&1.colour))

    %{
      "edits" => length(held),
      "colour" => %{
        "mean" => mean(Enum.map(colour, & &1.colour)),
        "by_group" =>
          colour
          |> Enum.group_by(& &1.group)
          |> Map.new(fn {group, list} -> {group, mean(Enum.map(list, & &1.colour))} end)
      },
      "sliders" =>
        results
        |> Enum.flat_map(& &1.sliders)
        |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
        |> Map.new(fn {id, errors} -> {id, mean(errors)} end)
    }
  end

  # The saved edit's target, as Taste.fit_colour reads one, against where the
  # model would have put the print.
  defp colour_error(ex, model, groups) do
    with true <- ex.stats.chroma >= 0.004,
         %{cast: m} <- groups[ex.group] do
      temp = number(ex.controls["wb.temp"], 6500.0)
      tint = number(ex.controls["wb.tint"], 0.0)
      {dr, db} = Film.cast_of(6500.0, temp, tint)
      {rg, bg} = ex.stats.cast
      %{alpha: alpha, offset: {or_, ob}} = Taste.taste_for(model, ex.group)
      {gr, gb} = {alpha * elem(m, 0) + or_, alpha * elem(m, 1) + ob}
      :math.sqrt(:math.pow(rg + dr - gr, 2) + :math.pow(bg + db - gb, 2)) * 100
    else
      _ -> nil
    end
  end

  defp slider_errors(ex, model, defaults) do
    model
    |> Taste.predict(ex.stats, ex.group, ex.condition)
    |> Enum.map(fn {id, guess} ->
      {id, abs(guess - number(ex.controls[id], number(defaults[id], 0.0)))}
    end)
  end

  @doc "The last run's scores, or nil."
  def latest do
    with {:ok, names} <- File.ls(dir()),
         [_ | _] = files <- names |> Enum.filter(&String.ends_with?(&1, ".json")) |> Enum.sort(),
         {:ok, body} <- File.read(Path.join(dir(), List.last(files))),
         {:ok, scores} <- Jason.decode(body) do
      scores
    else
      _ -> nil
    end
  end

  defp mean([]), do: nil
  defp mean(list), do: Float.round(Enum.sum(list) / length(list), 4)

  defp number(v, _default) when is_number(v), do: v * 1.0
  defp number(_v, default), do: default
end
