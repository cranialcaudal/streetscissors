defmodule Mix.Tasks.Darkroom.Eval do
  @shortdoc "Scores the colour prior and taste model against the saved edits"

  @moduledoc """
  Leave-one-out over every saved print edit (`Web.Darkroom.Eval`): how far
  the prior and the taste model's guess lands from what was saved, in colour
  and per slider, with the change from the last run.

      mix darkroom.eval

  Reads the archive at `NEGATIVES_PATH` and writes only
  `<archive>/.darkroom/eval/<timestamp>.json`. It **never boots the site**
  (this machine is the server): config is loaded, nothing is started.
  """
  use Mix.Task

  @impl true
  def run(_args) do
    Mix.Task.run("app.config")
    {:ok, _} = Application.ensure_all_started(:jason)

    {:ok, %{scores: scores, previous: previous}} = Web.Darkroom.Eval.run()

    Mix.shell().info("#{scores["edits"]} saved edits, each left out in turn.")
    line("Colour (hundredths of density)", scores["colour"]["mean"], previous && previous["colour"]["mean"])

    for {group, value} <- Enum.sort(scores["colour"]["by_group"]) do
      line("  #{group}", value, previous && get_in(previous, ["colour", "by_group", group]))
    end

    for {id, value} <- Enum.sort(scores["sliders"]) do
      line(id, value, previous && get_in(previous, ["sliders", id]))
    end
  end

  defp line(label, nil, _before), do: Mix.shell().info("#{label}: no examples")

  defp line(label, value, before) when is_number(before) do
    change = Float.round(value - before, 4)
    word = cond do
      change < 0 -> "better by #{-change}"
      change > 0 -> "WORSE by #{change}"
      true -> "unchanged"
    end

    Mix.shell().info("#{label}: #{value} (#{word})")
  end

  defp line(label, value, _before), do: Mix.shell().info("#{label}: #{value}")
end
