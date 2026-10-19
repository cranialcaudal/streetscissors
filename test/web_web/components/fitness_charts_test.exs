defmodule WebWeb.FitnessChartsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  alias WebWeb.FitnessCharts

  test "ticks are round numbers" do
    assert FitnessCharts.nice_ticks(0) == [0, 1]
    assert FitnessCharts.nice_ticks(245) == [0, 100, 200, 300]
    assert FitnessCharts.nice_ticks(1.6) == [0, 0.5, 1, 1.5, 2]
  end

  test "a line chart draws a gap where a week has no value" do
    html =
      render_component(&FitnessCharts.line_chart/1,
        id: "c",
        title: "e1RM",
        xs: [{1, "W1"}, {2, "W2"}, {3, "W3"}, {4, "W4"}],
        series: [%{name: "Hexbar RDL", values: %{1 => 200, 2 => 210, 4 => 220}}],
        unit: "lb"
      )

    assert html =~ ~s(aria-label="e1RM")
    assert length(Regex.scan(~r/<circle /, html)) == 3
    # W1–W2 is a line; W4 stands alone, so one polyline.
    assert length(Regex.scan(~r/<polyline /, html)) == 1
    refute html =~ "fc-legend", "one series needs no legend"
  end

  test "a chart with nothing to draw says so" do
    html =
      render_component(&FitnessCharts.line_chart/1,
        id: "c",
        title: "ACWR",
        xs: [{1, "W1"}],
        series: [],
        empty: "Needs four weeks."
      )

    assert html =~ "Needs four weeks."
    refute html =~ "<svg"
  end
end
