defmodule Web.Rides.KomootSyncTest do
  use Web.DataCase

  alias Web.Rides
  alias Web.Rides.KomootSync

  @login_body %{"username" => "u123", "password" => "tok"}

  @recorded_tour %{
    "id" => 111,
    "type" => "tour_recorded",
    "name" => "Evening loop",
    "sport" => "racebike",
    "date" => "2026-06-10T18:00:00.000Z"
  }

  @planned_tour %{
    "id" => 222,
    "type" => "tour_planned",
    "name" => "Fred Whitton",
    "sport" => "racebike",
    "date" => "2026-06-01T08:00:00.000Z"
  }

  @coordinates %{
    "items" => [
      %{"lat" => 54.54, "lng" => -3.15, "alt" => 100.0, "t" => 0},
      %{"lat" => 54.55, "lng" => -3.15, "alt" => 130.0, "t" => 60_000},
      %{"lat" => 54.56, "lng" => -3.15, "alt" => 120.0, "t" => 120_000}
    ]
  }

  defp stub_komoot(opts \\ []) do
    tours_pages =
      Keyword.get(opts, :tours, %{
        "tour_recorded" => [@recorded_tour],
        "tour_planned" => [@planned_tour]
      })

    broken_tour_ids = Keyword.get(opts, :broken_tours, [])

    Req.Test.stub(Web.Komoot.Client, fn conn ->
      cond do
        String.starts_with?(conn.request_path, "/v006/account/email/") ->
          Req.Test.json(conn, @login_body)

        String.contains?(conn.request_path, "/tours/") and conn.request_path =~ ~r{/v007/users/} ->
          type = URI.decode_query(conn.query_string)["type"]
          Req.Test.json(conn, %{"_embedded" => %{"tours" => tours_pages[type] || []}})

        match = Regex.run(~r{/v007/tours/(\d+)}, conn.request_path) ->
          tour_id = String.to_integer(Enum.at(match, 1))

          if tour_id in broken_tour_ids do
            Plug.Conn.send_resp(conn, 500, "boom")
          else
            Req.Test.json(conn, %{"_embedded" => %{"coordinates" => @coordinates}})
          end
      end
    end)
  end

  test "full sync imports recorded and planned tours with metadata" do
    stub_komoot()

    assert {:ok, %{imported: 2, skipped: 0, failed: 0}} = KomootSync.sync()

    assert [recorded] = Rides.list_recorded_rides()
    assert recorded.name == "Evening loop"
    assert recorded.sport == "racebike"
    assert recorded.source == "komoot"
    assert recorded.komoot_id == "111"
    assert recorded.started_at == ~U[2026-06-10 18:00:00Z]
    assert recorded.point_count == 3
    assert recorded.duration_s == 120
    assert recorded.distance_m > 2000

    assert [planned] = Rides.list_planned_rides()
    assert planned.komoot_id == "222"
    assert planned.duration_s == nil
    assert planned.distance_m > 2000
  end

  test "tour listing follows pagination links" do
    second_recorded = %{@recorded_tour | "id" => 333, "name" => "Second page loop"}

    Req.Test.stub(Web.Komoot.Client, fn conn ->
      query = URI.decode_query(conn.query_string)

      cond do
        String.starts_with?(conn.request_path, "/v006/account/email/") ->
          Req.Test.json(conn, @login_body)

        conn.request_path =~ ~r{/v007/users/} and query["type"] == "tour_recorded" ->
          case query["page"] do
            nil ->
              Req.Test.json(conn, %{
                "_embedded" => %{"tours" => [@recorded_tour]},
                "_links" => %{
                  "next" => %{
                    "href" =>
                      "https://api.komoot.de/v007/users/u123/tours/?type=tour_recorded&page=1"
                  }
                }
              })

            "1" ->
              Req.Test.json(conn, %{"_embedded" => %{"tours" => [second_recorded]}})
          end

        conn.request_path =~ ~r{/v007/users/} ->
          Req.Test.json(conn, %{"_embedded" => %{"tours" => []}})

        true ->
          Req.Test.json(conn, %{"_embedded" => %{"coordinates" => @coordinates}})
      end
    end)

    assert {:ok, %{imported: 2}} = KomootSync.sync()

    assert [%{komoot_id: "333"}, %{komoot_id: "111"}] =
             Enum.sort_by(Rides.list_recorded_rides(), & &1.komoot_id, :desc)
  end

  test "rerunning the sync is idempotent" do
    stub_komoot()

    assert {:ok, %{imported: 2}} = KomootSync.sync()
    assert {:ok, %{imported: 0, skipped: 2, failed: 0}} = KomootSync.sync()
    assert length(Rides.list_recorded_rides()) + length(Rides.list_planned_rides()) == 2
  end

  test "login failure surfaces as an error and imports nothing" do
    Req.Test.stub(Web.Komoot.Client, fn conn ->
      Plug.Conn.send_resp(conn, 401, "nope")
    end)

    assert {:error, :auth_failed} = KomootSync.sync()
    assert Rides.list_recorded_rides() == []
  end

  @tag :capture_log
  test "one broken tour does not abort the rest of the sync" do
    stub_komoot(broken_tours: [111])

    assert {:ok, %{imported: 1, failed: 1}} = KomootSync.sync()
    assert Rides.list_recorded_rides() == []
    assert [%{komoot_id: "222"}] = Rides.list_planned_rides()
  end

  test "sync is disabled without credentials" do
    original = Application.get_env(:web, :komoot)
    Application.put_env(:web, :komoot, email: nil, password: nil)
    on_exit(fn -> Application.put_env(:web, :komoot, original) end)

    refute KomootSync.enabled?()
    assert :disabled = KomootSync.sync()
  end

  @tag :capture_log
  test "run_scheduled never raises, even on transport errors" do
    Req.Test.stub(Web.Komoot.Client, fn conn ->
      Req.Test.transport_error(conn, :econnrefused)
    end)

    assert :ok = KomootSync.run_scheduled()
  end
end
