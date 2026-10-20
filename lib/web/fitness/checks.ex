defmodule Web.Fitness.Checks do
  @moduledoc """
  The questions a check-in asks, as the author writes them in
  `content/fitness/checkins.md`: one `##` section per check.

      ## Achilles
      states: quiet, talking, angry
      hold: talking
      stop: angry
      guards: box-jumps, single-leg-calf-raises
      talking: Skip the box jumps and calf raises today.
      angry: No jumping and no calf work.

      ## Bodyweight
      kind: number
      unit: lb

  A **state** check is answered from its `states` (the first is the good
  one); an answer under `hold` or `stop` holds or stops the exercises in
  `guards`, and a line named after a state is the advice shown with it. A
  **number** check is a measurement with a unit and guards nothing.
  Nothing here knows any injury: the file is the whole of it.
  """

  alias Web.Fitness.Vault

  def path, do: Path.join(Vault.base_path(), "checkins.md")

  @doc "The checks, in the file's order. A missing file is no checks."
  def all do
    case File.read(path()) do
      {:ok, text} -> parse(text)
      {:error, _} -> []
    end
  end

  @doc false
  def parse(text) do
    text
    |> String.split(~r/^##\s+/m)
    |> tl_or_empty()
    |> Enum.flat_map(fn section ->
      [label | lines] = String.split(section, "\n")
      label = String.trim(label)

      fields =
        for line <- lines,
            [_, k, v] <- [Regex.run(~r/^([a-z_]+):\s*(.*)$/, String.trim(line))],
            into: %{},
            do: {k, String.trim(v)}

      if label == "", do: [], else: [build(label, fields)]
    end)
  end

  defp tl_or_empty([_ | rest]), do: rest
  defp tl_or_empty([]), do: []

  defp build(label, f) do
    states = list(f["states"])
    kind = if f["kind"] == "number" or states == [], do: :number, else: :state

    %{
      id: id(label),
      label: label,
      kind: kind,
      unit: f["unit"],
      states: states,
      hold: list(f["hold"]),
      stop: list(f["stop"]),
      guards: list(f["guards"]),
      advice: Map.new(states, &{&1, f[&1]}) |> Map.reject(fn {_, v} -> is_nil(v) end)
    }
  end

  @doc "A check's id from its label: `Knee (stairs test)` is `knee-stairs-test`."
  def id(label),
    do: label |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "-") |> String.trim("-")

  @doc "The checks that guard an exercise."
  def guarding(checks, slug), do: Enum.filter(checks, &(slug in &1.guards))

  @doc "How an answer stands: `:green`, `:hold` or `:stop`."
  def level(%{kind: :state} = check, answer) do
    cond do
      answer in check.stop -> :stop
      answer in check.hold -> :hold
      true -> :green
    end
  end

  def level(_check, _answer), do: :green

  defp list(nil), do: []

  defp list(text),
    do:
      text
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
end
