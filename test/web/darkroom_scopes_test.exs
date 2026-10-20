defmodule Web.Darkroom.ScopesTest do
  use ExUnit.Case, async: true

  alias Web.Darkroom.Scopes

  # 256 x 96 pixels: the left half black, the right half a warm grey.
  defp picture do
    row = :binary.copy(<<0, 0, 0>>, 128) <> :binary.copy(<<200, 150, 100>>, 128)
    :binary.copy(row, 96)
  end

  test "the histogram is 64 bins a channel, the tallest at 1.0" do
    %{histogram: h} = Scopes.from_bytes(picture())

    for channel <- [:r, :g, :b, :l], do: assert(length(h[channel]) == 64)
    assert Enum.max(Enum.flat_map(Map.values(h), & &1)) == 1.0
    # Half the picture is black: every channel's first bin holds it.
    assert hd(h.r) == 1.0
    # The warm half: red lands in its bin for 200, blue in its bin for 100.
    assert Enum.at(h.r, div(200 * 64, 256)) == 1.0
    assert Enum.at(h.b, div(100 * 64, 256)) == 1.0
    assert Enum.at(h.b, div(200 * 64, 256)) == 0.0
  end

  test "the parade follows the picture across: dark on the left, warm on the right" do
    %{parade: p} = Scopes.from_bytes(picture())

    assert length(p.r) == 64
    {_low, left_mid, _high} = hd(p.r)
    {_low, right_red, _high} = List.last(p.r)
    {_low, right_blue, _high} = List.last(p.b)

    assert left_mid == 0.0
    assert_in_delta right_red, 200 / 255, 1.0e-9
    assert right_red > right_blue
  end
end
