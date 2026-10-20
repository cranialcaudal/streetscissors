defmodule Web.Darkroom.EvalTest do
  use ExUnit.Case, async: true

  alias Web.Darkroom.Eval

  defp stats(cast) do
    %{cast: cast, neutral: 0.6, chroma: 0.05, l: 0.5, a: 0.0, b: 0.0, l05: 0.1, l50: 0.5, l95: 0.9}
  end

  defp edit(cast, controls, weight \\ 1.0) do
    %{group: "C-41", condition: "sound", stats: stats(cast), controls: controls, weight: weight}
  end

  test "each saved edit is left out in turn, and choices are never scored" do
    examples = [
      edit({0.02, 0.0}, %{"wb.temp" => 6000.0, "light.exposure" => 0.3}),
      edit({0.02, 0.0}, %{"wb.temp" => 6000.0, "light.exposure" => 0.3}),
      edit({0.02, 0.0}, %{"wb.temp" => 6000.0, "light.exposure" => 0.3}),
      edit({0.02, 0.0}, %{"wb.temp" => 6000.0, "light.exposure" => 0.3}),
      edit({0.05, 0.0}, %{"wb.temp" => 5000.0}, 0.5)
    ]

    groups = %{"C-41" => %{n: 4, cast: {0.02, 0.0}, var: {0.0004, 0.0004}}}
    scores = Eval.score(examples, groups)

    assert scores["edits"] == 4
    assert is_float(scores["colour"]["mean"])
    assert Map.has_key?(scores["colour"]["by_group"], "C-41")
    # The same edit four times: the rest predict it closely.
    assert scores["colour"]["mean"] < 2.0
    assert scores["sliders"]["light.exposure"] < 0.1
  end

  test "an archive with no saved edits scores nothing" do
    scores = Eval.score([edit({0.0, 0.0}, %{}, 0.5)], %{})
    assert scores["edits"] == 0
    assert scores["colour"]["mean"] == nil
  end
end
