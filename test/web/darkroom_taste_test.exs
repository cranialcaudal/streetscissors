defmodule Web.Darkroom.TasteTest do
  use ExUnit.Case, async: false

  import Web.NegativesFixtures

  alias Web.Darkroom
  alias Web.Darkroom.{Film, Taste}

  setup do
    root = archive!()
    dir = Path.join(root, "roll")
    File.mkdir_p!(Path.join(dir, "frames"))
    %{root: root, dir: dir}
  end

  defp stats(l, cast \\ {0.05, 0.0}) do
    %{
      cast: cast,
      neutral: 0.6,
      l: l,
      a: 0.01,
      b: 0.02,
      chroma: 0.05,
      l05: l - 0.3,
      l50: l,
      l95: l + 0.3
    }
  end

  # A print on disk with an edit, as Archive.prints/0 would give it.
  defp edited(dir, frame, l, controls, group \\ "C-41", cast \\ {0.05, 0.0}) do
    File.write!(
      Path.join([dir, "frames", "#{String.pad_leading("#{frame}", 2, "0")}.png"]),
      "print"
    )

    :ok = Darkroom.save(dir, frame, %{controls: controls, crop: nil, spots: []})
    %{roll: "001", frame: frame, dir: dir, group: group, stock: nil, stats: stats(l, cast)}
  end

  test "the solver finds a line it is given" do
    rows = for x <- 1..10, do: {[1.0, x * 1.0], 2.0 + 3.0 * x, 1.0}
    assert {:ok, [a, b]} = Taste.solve_ridge(rows, [1.0e-9, 1.0e-9], nil)
    assert_in_delta a, 2.0, 1.0e-6
    assert_in_delta b, 3.0, 1.0e-6
  end

  test "untaught, a film's prints are brought to its own average" do
    model = Taste.fit([], %{"C-41" => %{n: 10, cast: {0.03, -0.01}, var: {0.0, 0.0}}})
    assert model.n == 0
    assert %{alpha: 1.0, offset: {+0.0, +0.0}} = Taste.taste_for(model, "C-41")
  end

  test "a film's colour leans toward where his edits put it, more with every edit", %{dir: dir} do
    groups = %{"C-41" => %{n: 10, cast: {0.05, 0.0}, var: {0.0004, 0.0004}}}
    # Each edit warms a print sitting at its film's average by the same Temp.
    grade = Film.sliders({0.04, 0.0}, 6500.0)

    prints = for f <- 1..2, do: edited(dir, f, 0.5, grade)
    few = Taste.taste_for(Taste.fit(prints, groups), "C-41")

    prints = prints ++ for(f <- 3..12, do: edited(dir, f, 0.5, grade))
    many = Taste.taste_for(Taste.fit(prints, groups), "C-41")

    target = fn %{alpha: a, offset: {o, _}} -> a * 0.05 + o end
    assert target.(few) > 0.05 and target.(few) < 0.09
    assert target.(many) > target.(few)
    assert_in_delta target.(many), 0.09, 0.015
  end

  test "a slider is learned from what the print looks like, once moved in three edits", %{
    dir: dir
  } do
    # Darker prints he brightens, lighter ones he darkens; vibrance once only.
    prints =
      for {l, f} <- Enum.with_index([0.3, 0.35, 0.4, 0.6, 0.65, 0.7], 1) do
        edited(dir, f, l, %{"light.exposure" => (0.5 - l) * 4})
      end ++ [edited(dir, 9, 0.5, %{"color.vibrance" => 30.0})]

    model = Taste.fit(prints, %{})
    assert Map.has_key?(model.sliders.fits, "light.exposure")
    refute Map.has_key?(model.sliders.fits, "color.vibrance")

    dark = Taste.predict(model, stats(0.3), "C-41", "sound")["light.exposure"]
    light = Taste.predict(model, stats(0.7), "C-41", "sound")["light.exposure"]
    assert dark > 0.2 and light < -0.2
  end

  test "a choice is kept, and counts half an edit", %{dir: dir} do
    print = edited(dir, 1, 0.5, %{"light.exposure" => 0.3})
    Taste.choose("001", 1, %{"light.exposure" => 0.6}, %{"light.exposure" => 0.0})

    assert [%{"roll" => "001", "frame" => 1, "chosen" => %{"light.exposure" => 0.6}}] =
             Taste.choices()

    assert [%{weight: 1.0}, %{weight: 0.5, controls: %{"light.exposure" => 0.6}}] =
             Taste.examples([print])
  end

  test "the bath's diagnosis is a condition", %{dir: dir} do
    assert Taste.condition(dir) == "sound"
    File.write!(Path.join(dir, "frames.json"), ~s({"diagnosis": {"veil": true}}))
    assert Taste.condition(dir) == "veil"
  end
end
