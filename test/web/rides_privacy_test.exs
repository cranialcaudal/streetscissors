defmodule Web.Rides.PrivacyTest do
  # Not async: the private places are application config.
  use ExUnit.Case

  alias Web.Rides.Privacy

  # Invented ground. The "house" is at 45.0, 7.0; a degree of latitude is
  # ~111 km, so 0.001° north is ~111 m.
  @house {45.0, 7.0}

  setup do
    Application.put_env(:web, :ride_privacy_zones, "45.0,7.0")
    on_exit(fn -> Application.delete_env(:web, :ride_privacy_zones) end)
  end

  defp north_of_the_house(metres), do: {45.0 + metres / 111_195, 7.0}

  describe "verdict/1" do
    test "a view that never comes near a private place is clear" do
      assert Privacy.verdict([north_of_the_house(600), north_of_the_house(2_000)]) == :clear
      assert Privacy.verdict([]) == :clear
    end

    # A zone that is doing its job trims a tour's two ends. A view that
    # begins or ends at the door means it is not.
    test "a view that begins or ends inside the wire is exposed" do
      away = [north_of_the_house(2_000), {46.0, 8.0}]

      assert Privacy.verdict([north_of_the_house(40) | away]) == :exposed
      assert Privacy.verdict(away ++ [north_of_the_house(40)]) == :exposed
      assert Privacy.verdict([@house]) == :exposed
    end

    # Out, home for lunch, out again. Komoot trims both ends and hands a
    # stranger the middle whole. Held back, and not the zone's failure.
    test "a view whose ends are away and which comes back in between is passing" do
      assert Privacy.verdict([
               north_of_the_house(800),
               north_of_the_house(40),
               @house,
               north_of_the_house(900)
             ]) == :passing
    end

    test "an end inside the wire outranks a pass in the middle" do
      assert Privacy.verdict([
               north_of_the_house(800),
               @house,
               north_of_the_house(900),
               north_of_the_house(30)
             ]) == :exposed
    end

    # Komoot's zones put the nearest point a stranger sees hundreds of metres
    # out. The wire is well inside that: it trips on a zone that is missing,
    # not on the edge of one that is there.
    test "the wire is at 100 metres" do
      assert Privacy.tripwire_m() == 100
      assert Privacy.verdict([north_of_the_house(95)]) == :exposed
      assert Privacy.verdict([north_of_the_house(105)]) == :clear

      far = north_of_the_house(1_000)
      assert Privacy.verdict([far, north_of_the_house(95), far]) == :passing
      assert Privacy.verdict([far, north_of_the_house(105), far]) == :clear
    end

    test "any of several places trips it" do
      Application.put_env(:web, :ride_privacy_zones, "45.0,7.0; 46.0,8.0")

      assert Privacy.verdict([{46.0002, 8.0}]) == :exposed
      assert Privacy.verdict([{45.5, 7.5}, {46.0002, 8.0}, {45.5, 7.5}]) == :passing
      assert Privacy.verdict([{45.5, 7.5}]) == :clear
    end

    test "with no places on file nothing is checked: Komoot is trusted as it stands" do
      for unset <- [nil, ""] do
        Application.put_env(:web, :ride_privacy_zones, unset)
        assert Privacy.verdict([@house]) == :clear
      end
    end

    # A setting that is there and unreadable means somebody meant to protect
    # something. Waving every tour through unchecked would be the wrong guess.
    test "a setting that cannot be read exposes everything" do
      for broken <- ["home", "45.0", "45.0,seven", "95.0,7.0", "45.0,7.0,400,1", 42] do
        Application.put_env(:web, :ride_privacy_zones, broken)
        assert Privacy.zones() == :invalid, "#{inspect(broken)} was read as a place"
        assert Privacy.verdict([{0.0, 0.0}]) == :exposed
        assert Privacy.verdict([]) == :exposed
      end
    end
  end

  describe "zones/0" do
    test "reads lat,lng pairs separated by semicolons" do
      Application.put_env(:web, :ride_privacy_zones, " 45.0, 7.0 ;46,8;")
      assert Privacy.zones() == {:ok, [{45.0, 7.0}, {46.0, 8.0}]}
    end

    # The site used to cut its own maps by a radius given as a third number.
    # An `.env` written for that still works; the radius is not used.
    test "still accepts the radius an earlier setting carried" do
      Application.put_env(:web, :ride_privacy_zones, "45.0,7.0,400")
      assert Privacy.zones() == {:ok, [{45.0, 7.0}]}
    end
  end

  test "distance_m/2 is the distance over the ground" do
    assert_in_delta Privacy.distance_m(@house, north_of_the_house(500)), 500, 1
    assert Privacy.distance_m(@house, @house) == 0.0
    # A degree of longitude is shorter at 45° north than a degree of latitude.
    assert_in_delta Privacy.distance_m({45.0, 7.0}, {45.0, 8.0}), 78_600, 300
  end
end
