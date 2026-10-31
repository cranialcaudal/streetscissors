defmodule WebWeb.FitnessKomootSessionTest do
  # Today's Komoot tours fill the session (2026-10-28): the day's ride is
  # what a ride brief shows and is done by, the day's run what the run line
  # shows and is done by, so neither is typed in by hand.
  use WebWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    src = Path.expand("test/support/fixtures/fitness")
    vault = Path.join(System.tmp_dir!(), "komoot-vault-#{System.unique_integer([:positive])}")
    File.cp_r!(src, vault)

    File.mkdir_p!(Path.join([vault, "exercise-wiki", "cardio"]))

    File.write!(Path.join([vault, "exercise-wiki", "cardio", "outfield-jog.md"]), """
    ---
    title: "Outfield Jog"
    muscle_group: "cardio"
    short_description: "Light jogging."
    ---
    Body.
    """)

    File.write!(Path.join([vault, "modules", "ride.md"]), """
    ### Ride In
    - [ ] Easy, conversational
    """)

    File.write!(Path.join([vault, "modules", "run.md"]), """
    ### Easy Run
    - [ ] [[outfield-jog|Easy Run]]; by time
    """)

    today = Web.Clock.today_slug()

    File.write!(Path.join([vault, "weekly", "#{today}.md"]), """
    ---
    title: Today — Ride and Run
    tab: #{String.capitalize(today)}
    theme: bike
    modules: ride, run
    ---
    """)

    prev = Application.get_env(:web, :fitness_path)
    Application.put_env(:web, :fitness_path, vault)

    on_exit(fn ->
      Application.put_env(:web, :fitness_path, prev)
      File.rm_rf(vault)
    end)

    :ok
  end

  defp ride!(sport, minutes, km) do
    {:ok, ride} =
      Web.Rides.create_ride(%{
        komoot_id: "#{System.unique_integer([:positive])}",
        name: sport,
        sport: sport,
        started_at: DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.truncate(:second),
        distance_m: km * 1000.0,
        duration_s: minutes * 60 + 120,
        time_in_motion_s: minutes * 60,
        visibility: "private"
      })

    ride
  end

  test "today's Komoot ride and run fill the session, nothing typed", %{conn: conn} do
    {:ok, view, _} =
      conn |> init_test_session(%{"admin_user" => true}) |> live(~p"/fitness?view=list")

    assert has_element?(view, ".session-brief", "Ride In")
    assert has_element?(view, "#card-outfield-jog button", "Log minutes")

    ride!("racebike", 62, 27.0)
    ride!("jogging", 25, 4.1)

    {:ok, view, _} =
      build_conn() |> init_test_session(%{"admin_user" => true}) |> live(~p"/fitness?view=list")

    assert has_element?(view, "details.session-done", "Ride In")
    assert has_element?(view, ".session-komoot", "27.0 km · 62 min moving")
    assert has_element?(view, ".session-komoot", "4.1 km · 25 min moving")
    refute has_element?(view, "#card-outfield-jog button", "Log minutes")

    html = render_click(view, "finish_session", %{})
    assert html =~ "Run (Komoot)"
    refute html =~ "Not finished"
  end
end
