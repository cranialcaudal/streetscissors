defmodule Web.Rides.PrivacyTest do
  # Not async: the zones are application config.
  use ExUnit.Case

  alias Web.Rides.{Privacy, Route}

  # Invented ground. The "house" is at 45.0, 7.0; a degree of latitude is
  # ~111 km, so 0.0002° is ~22 m.
  @house {45.0, 7.0}
  @radius 400

  setup do
    Application.put_env(:web, :ride_privacy_zones, "45.0,7.0,#{@radius}")
    on_exit(fn -> Application.delete_env(:web, :ride_privacy_zones) end)
  end

  # Straight out from the house along `bearing` degrees, `count` points ~22 m apart.
  defp spoke(bearing, count \\ 100) do
    radians = bearing * :math.pi() / 180

    for i <- 0..count do
      {45.0 + i * 0.0002 * :math.cos(radians),
       7.0 + i * 0.0002 * :math.sin(radians) / :math.cos(45.0 * :math.pi() / 180), 300.0, i}
    end
  end

  defp published(points, key),
    do: points |> Privacy.redact(key) |> Enum.flat_map(&elem(&1, 0))

  test "a ride that starts at the house is published from outside the radius on" do
    [{run, cut_start?, cut_end?}] = Privacy.redact(spoke(0), "ride")

    assert cut_start? and not cut_end?
    assert Enum.all?(run, &(Privacy.distance_m(&1, @house) > @radius))
    assert List.last(run) == List.last(spoke(0))
  end

  test "the house keeps the full radius of cover in every direction" do
    for bearing <- 0..350//10, ride <- ~w(a b c) do
      points = published(spoke(bearing), ride)

      assert points != []
      assert Enum.all?(points, &(Privacy.distance_m(&1, @house) > @radius))
    end
  end

  test "the ends of many rides do not sit on a circle around the house" do
    # Where each of 72 rides, leaving in every direction, is first seen.
    firsts =
      for bearing <- 0..355//5 do
        bearing |> spoke() |> published("ride-#{bearing}") |> hd() |> Privacy.distance_m(@house)
      end

    # On a circle centred on the house these would all be equal.
    assert Enum.max(firsts) - Enum.min(firsts) > 80

    # And their middle — what fitting a circle to them finds — is not the house.
    cuts = for bearing <- 0..355//5, do: bearing |> spoke() |> published("r#{bearing}") |> hd()
    centre = {mean(cuts, 0), mean(cuts, 1)}
    assert Privacy.distance_m(centre, @house) > 25
  end

  defp mean(points, index), do: Enum.sum(Enum.map(points, &elem(&1, index))) / length(points)

  test "an out-and-back is cut at both ends" do
    out = spoke(90)
    [{run, true, true}] = Privacy.redact(out ++ Enum.reverse(out), "ride")

    assert Enum.all?(run, &(Privacy.distance_m(&1, @house) > @radius))
  end

  test "passing back through the zone mid-ride splits the route in two" do
    west = Enum.reverse(spoke(270))
    east = spoke(90)

    assert [{first, false, true}, {second, true, false}] = Privacy.redact(west ++ east, "ride")
    assert hd(first) == hd(west)
    assert List.last(second) == List.last(east)
  end

  test "a straight line is never drawn across the zone" do
    # A recording paused on one side of the zone and resumed on the other:
    # both points are outside it, the line between them is not.
    far_west = spoke(270) |> Enum.take(-20) |> Enum.reverse()
    far_east = Enum.take(spoke(90), -20)

    assert [{_, false, true}, {_, true, false}] = Privacy.redact(far_west ++ far_east, "ride")
  end

  test "a ride is cut in the same place every time, and differently from another ride" do
    assert published(spoke(0), "a") == published(spoke(0), "a")

    cuts = for ride <- ~w(a b c d e f), do: hd(published(spoke(0), ride))
    assert length(Enum.uniq(cuts)) > 1
  end

  test "a ride nowhere near a zone is published whole" do
    far = for {lat, lng, alt, t} <- spoke(0), do: {lat + 1, lng, alt, t}

    assert Privacy.redact(far, "ride") == [{far, false, false}]
  end

  test "a ride that never leaves the zone publishes nothing" do
    assert Privacy.redact(Enum.take(spoke(0), 10), "ride") == []
    assert Route.empty?(Route.build(Enum.take(spoke(0), 10), "ride"))
  end

  test "several zones are all applied" do
    Application.put_env(:web, :ride_privacy_zones, "45.0,7.0,400; 45.02,7.0,300")

    # The spoke north ends at 45.02 — inside the second zone.
    assert [{run, true, true}] = Privacy.redact(spoke(0), "ride")
    assert Enum.all?(run, &(Privacy.distance_m(&1, @house) > 400))
    assert Enum.all?(run, &(Privacy.distance_m(&1, {45.02, 7.0}) > 300))
  end

  test "no zones, nothing cut" do
    Application.delete_env(:web, :ride_privacy_zones)
    assert Privacy.redact(spoke(0), "ride") == [{spoke(0), false, false}]
  end

  @tag :capture_log
  test "a setting that can't be read hides everything rather than nothing" do
    for bad <- ["45.0,7.0", "here,there,400", "45.0,7.0,-5", "45.0,7.0,400;oops"] do
      Application.put_env(:web, :ride_privacy_zones, bad)

      assert Privacy.zones() == :invalid
      assert Privacy.redact(spoke(0), "ride") == []
    end
  end

  test "the key changes with the zones" do
    before = Privacy.key()
    Application.put_env(:web, :ride_privacy_zones, "45.0,7.0,500")
    refute Privacy.key() == before
  end

  describe "Route" do
    test "distances count the published route only, from zero" do
      route = Route.build(spoke(0), "ride")
      [[{_, _, _, first} | _] = segment] = route.segments

      assert first == 0.0
      assert_in_delta route.length_m, Privacy.distance_m(hd(segment), List.last(segment)), 1.0
      refute route.start?
      assert route.finish?
    end

    test "map data carries only published points, as [lng, lat, distance, alt]" do
      %{segments: [points], start: false, finish: true} =
        Route.map_data(Route.build(spoke(0), "ride"))

      assert [7.0, lat, 0, 300] = hd(points)
      assert Privacy.distance_m({lat, 7.0}, @house) > @radius
    end

    test "a long track is thinned, keeping its last point" do
      track = for i <- 0..9_999, do: {46.0 + i * 0.00001, 7.0, 300.0, i}
      %{segments: [segment]} = Route.build(track, "ride")

      assert length(segment) <= 1_201
      assert {lat, _, _, _} = List.last(segment)
      assert_in_delta lat, 46.09999, 1.0e-9
    end

    test "the profile and the card outline are SVG paths; no altitudes, no profile" do
      route = Route.build(spoke(45), "ride")

      assert %{line: "M" <> _, area: area, low_m: 300.0, high_m: 300.0} = Route.profile(route)
      assert String.ends_with?(area, "Z")
      assert "M" <> _ = Route.card_path(route)

      flat = for {lat, lng, _alt, t} <- spoke(45), do: {lat, lng, nil, t}
      assert Route.profile(Route.build(flat, "ride")) == nil
    end
  end
end
