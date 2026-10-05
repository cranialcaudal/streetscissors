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

  describe "exposed?/1" do
    test "a view that never comes near a private place is clean" do
      refute Privacy.exposed?([north_of_the_house(600), north_of_the_house(2_000)])
      refute Privacy.exposed?([])
    end

    test "one point inside the wire is enough" do
      assert Privacy.exposed?([north_of_the_house(2_000), north_of_the_house(40), {46.0, 8.0}])
      assert Privacy.exposed?([@house])
    end

    # Komoot's zones put the nearest point a stranger sees hundreds of metres
    # out. The wire is well inside that: it trips on a zone that is missing,
    # not on the edge of one that is there.
    test "the wire is at 100 metres" do
      assert Privacy.tripwire_m() == 100
      assert Privacy.exposed?([north_of_the_house(95)])
      refute Privacy.exposed?([north_of_the_house(105)])
    end

    test "any of several places trips it" do
      Application.put_env(:web, :ride_privacy_zones, "45.0,7.0; 46.0,8.0")

      assert Privacy.exposed?([{46.0002, 8.0}])
      refute Privacy.exposed?([{45.5, 7.5}])
    end

    test "with no places on file nothing is exposed: Komoot is trusted as it stands" do
      for unset <- [nil, ""] do
        Application.put_env(:web, :ride_privacy_zones, unset)
        refute Privacy.exposed?([@house])
      end
    end

    # A setting that is there and unreadable means somebody meant to protect
    # something. Waving every tour through unchecked would be the wrong guess.
    test "a setting that cannot be read exposes everything" do
      for broken <- ["home", "45.0", "45.0,seven", "95.0,7.0", "45.0,7.0,400,1", 42] do
        Application.put_env(:web, :ride_privacy_zones, broken)
        assert Privacy.zones() == :invalid, "#{inspect(broken)} was read as a place"
        assert Privacy.exposed?([{0.0, 0.0}])
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
