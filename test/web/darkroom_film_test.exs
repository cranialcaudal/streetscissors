defmodule Web.Darkroom.FilmTest do
  use ExUnit.Case, async: true

  alias Web.Darkroom.{Film, Prior}

  defp stock(id), do: Enum.find(Film.stocks(), &(&1["id"] == id))
  defp close?({a, b}, {c, d}, tol \\ 0.002), do: abs(a - c) < tol and abs(b - d) < tol

  describe "naming the film" do
    test "the longest name found in the words wins" do
      assert Film.match("Kodak Portra 400, shot at box speed")["id"] == "kodak-portra-400"
      assert Film.match("portra 800")["id"] == "kodak-portra-800"
      assert Film.match("Ektachrome E100 (expired 2019)")["id"] == "kodak-ektachrome-e100"
      assert Film.match("HP5+ pushed")["id"] == "ilford-hp5-plus"
      assert Film.match("something homemade") == nil
      assert Film.match(nil) == nil
    end
  end

  describe "reciprocity, from the sheets" do
    test "Velvia 50 goes green on long exposures, and the sheet's magenta answers it" do
      velvia = stock("fujifilm-velvia-50")

      assert %{status: :none} = Film.reciprocity(velvia, 1)
      assert %{status: :published, filter: "12.5M", cast: cast} = Film.reciprocity(velvia, 32)
      assert close?(cast, {0.125, 0.125})
      assert %{stops: stops} = Film.reciprocity(velvia, 8)
      assert_in_delta stops, 0.5, 0.001

      # Between rows, along the log of the time.
      %{cast: {rg, _}} = Film.reciprocity(velvia, :math.sqrt(4 * 8))
      assert_in_delta rg, 0.0625, 0.001

      assert %{status: :beyond} = Film.reciprocity(velvia, 64)
    end

    test "Ektachrome needs nothing to ten seconds and red at two minutes" do
      e100 = stock("kodak-ektachrome-e100")
      assert %{status: :none} = Film.reciprocity(e100, 8)
      assert %{status: :published, cast: cast} = Film.reciprocity(e100, 120)
      assert close?(cast, {0.10, 0.0})
    end

    test "a maker that publishes nothing is said so, and changes nothing" do
      assert %{status: :unpublished, cast: {+0.0, +0.0}} =
               Film.reciprocity(stock("kodak-portra-400"), 30)

      assert %{status: :unknown} = Film.reciprocity(stock("kodak-gold-200"), 30)
      assert %{status: :unknown} = Film.reciprocity(nil, 30)
    end

    test "Ilford's P: ten metered seconds want about one more stop" do
      %{stops: stops} = Film.reciprocity(stock("ilford-hp5-plus"), 10)
      assert_in_delta stops, 1.03, 0.01
    end
  end

  test "a filter holds back the colours it is not" do
    assert close?(Film.filter_cast("10R"), {0.10, 0.0})
    assert close?(Film.filter_cast("5M"), {0.05, 0.05})
    assert close?(Film.filter_cast("10C"), {-0.10, 0.0})
    assert close?(Film.filter_cast("10Y"), {0.0, -0.10})
    assert Film.filter_cast(nil) == {0.0, 0.0}
  end

  test "Temp and Tint for a cast, and back" do
    for cast <- [{0.05, -0.03}, {-0.08, 0.02}, {0.125, 0.125}] do
      %{"wb.temp" => temp, "wb.tint" => tint} = Film.sliders(cast, 6500.0)
      assert close?(Film.cast_of(6500.0, temp, tint), cast, 0.0005)
    end
  end

  describe "the prior" do
    @stats %{cast: {0.06, 0.0}, neutral: 0.8, chroma: 0.05}

    test "a print is brought toward its film's average, weighed by how grey it is" do
      film = %{n: 20, cast: {0.02, 0.0}, var: {0.0004, 0.0004}}
      result = Prior.compute(@stats, "C-41", nil, nil, film, %{alpha: 1.0, offset: {0.0, 0.0}})

      {est, _} = result.estimate
      assert est > 0.02 and est < 0.06
      assert result.target == {0.02, 0.0}
      assert elem(result.correction, 0) < 0
      # Less red is a cooler Temp.
      assert result.sliders["wb.temp"] < 6500

      little_grey =
        Prior.compute(%{@stats | neutral: 0.02}, "C-41", nil, nil, film, %{
          alpha: 1.0,
          offset: {0.0, 0.0}
        })

      assert abs(elem(little_grey.estimate, 0) - 0.02) < abs(est - 0.02)
    end

    test "with too few prints the print stands for itself, and a long exposure adds the sheet's filter" do
      velvia = stock("fujifilm-velvia-50")

      result =
        Prior.compute(@stats, "fujifilm-velvia-50", velvia, 32, nil, %{
          alpha: 1.0,
          offset: {0.0, 0.0}
        })

      assert close?(result.correction, {0.125, 0.125})
      assert Enum.any?(result.lines, &(&1 =~ "12.5M"))
    end

    test "the suggestion is absolute, anchored where the print was developed" do
      film = %{n: 20, cast: {0.02, 0.0}, var: {0.0004, 0.0004}}
      taste = %{alpha: 1.0, offset: {0.0, 0.0}}
      plain = Prior.compute(@stats, "C-41", nil, nil, film, taste)
      anchored = Prior.compute(@stats, "C-41", nil, nil, film, taste, temp: 6500.0, tint: 10.0)

      # Same anchor, same answer: pressing it twice cannot move the print twice.
      assert plain.sliders["wb.temp"] == anchored.sliders["wb.temp"]
      assert_in_delta anchored.sliders["wb.tint"], plain.sliders["wb.tint"] + 10.0, 1.0e-9

      warmer_anchor = Prior.compute(@stats, "C-41", nil, nil, film, taste, temp: 5000.0)
      assert warmer_anchor.sliders["wb.temp"] < plain.sliders["wb.temp"]
    end

    test "black and white is offered no colour" do
      result = Prior.compute(@stats, "BW", nil, nil, nil, %{alpha: 1.0, offset: {0.0, 0.0}})
      assert result.sliders == %{}
    end
  end

  # The slider response is measured, so it is measured again where LightCraft is.
  if System.find_executable("lightcraft-cli") && System.find_executable("magick") do
    test "LightCraft's Temp and Tint move a grey by the cast asked for" do
      dir = Path.join(System.tmp_dir!(), "film_cal_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)
      grey = Path.join(dir, "grey.png")
      {_, 0} = System.cmd("magick", ["-size", "32x32", "xc:rgb(118,118,118)", grey])

      for cast <- [{0.05, -0.03}, {-0.04, 0.04}] do
        values = Film.sliders(cast, 6500.0)
        out = Path.join(dir, "out.png")
        script = Path.join(dir, "s.jsonl")

        File.write!(script, [
          Jason.encode!(%{"command" => "develop.set", "params" => %{"values" => values}}),
          "\n",
          Jason.encode!(%{
            "command" => "app.export",
            "params" => %{"path" => out, "longEdge" => 0, "conflict" => "overwrite"}
          }),
          "\n"
        ])

        {_, 0} = System.cmd("lightcraft-cli", ["run", "--import", grey, "--script", script])
        {:ok, %{cast: {rg, bg}}} = Web.Darkroom.Stats.read(out)
        assert_in_delta rg, elem(cast, 0), 0.012
        assert_in_delta bg, elem(cast, 1), 0.012
      end
    end
  end
end
