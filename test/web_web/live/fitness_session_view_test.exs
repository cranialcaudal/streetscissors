defmodule WebWeb.FitnessSessionViewTest do
  # The admin's session view (2026-10-26): a day as one station at a time
  # (focus) or a list, from the plan's structure, with the rest handed to the
  # browser, a best said out loud, and a summary at the end.
  use WebWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  # A copy of the fixture vault with a superset day of two exercises.
  setup do
    src = Path.expand("test/support/fixtures/fitness")
    vault = Path.join(System.tmp_dir!(), "session-vault-#{System.unique_integer([:positive])}")
    File.cp_r!(src, vault)

    File.write!(Path.join([vault, "exercise-wiki", "upper", "dumbbell-rows.md"]), """
    ---
    title: "Dumbbell Rows"
    muscle_group: "upper"
    short_description: "A row."
    ---
    Body.
    """)

    File.write!(Path.join([vault, "modules", "pair.md"]), """
    ### Pair Day (30 Min)

    - [ ] Weeks 1–520: every week's line
    - [ ] Week 1: only the first week's line

    #### Superset A: Push and Pull
    - [ ] [[push-ups|Push-ups]]; 3 x 12
    - [ ] [[dumbbell-rows|Dumbbell Rows]]; 3 x 10, 30 lb, 60 sec between sets

    #### After
    - [ ] [[plank|Plank]]; 2 x 30 sec
    """)

    File.write!(Path.join([vault, "exercise-wiki", "upper", "plank.md"]), """
    ---
    title: "Plank"
    muscle_group: "upper"
    short_description: "A hold."
    ---
    Body.
    """)

    File.write!(Path.join([vault, "modules", "ride.md"]), """
    ### Ride In
    - [ ] Easy, conversational
    """)

    File.write!(Path.join([vault, "sessions", "wednesday.md"]), """
    ---
    title: Wednesday — Pairs
    tab: Wednesday
    theme: arms
    modules: ride, pair
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

  defp admin(conn, path) do
    {:ok, view, html} = conn |> log_in_admin() |> live(path)
    {view, html}
  end

  test "the admin chooses focus or list; a visitor only ever gets the plan", %{conn: conn} do
    {view, html} = admin(conn, ~p"/fitness/day/tuesday?view=list")
    assert html =~ ~s(id="session-list")
    assert has_element?(view, ~s(.view-toggle-btn[aria-pressed="true"]), "List")
    refute has_element?(view, ~s(.view-toggle-btn[phx-value-view="page"]))

    view |> element(~s(.view-toggle-btn[phx-value-view="focus"])) |> render_click()
    # On a Tuesday, Tuesday's page is /fitness itself.
    day = if Web.Clock.today_slug() == "tuesday", do: "/fitness", else: "/fitness/day/tuesday"
    assert_patch(view, day <> "?view=focus")
    assert has_element?(view, "#session-focus")

    {:ok, _view, html} = live(conn, ~p"/fitness/day/tuesday?view=focus")
    refute html =~ "session-focus"
    refute html =~ "view-toggle"
    refute html =~ "rest-bar"
  end

  test "any day opens in focus, whatever the date, and the address no longer takes page", %{
    conn: conn
  } do
    other = hd(~w(tuesday wednesday) -- [Web.Clock.today_slug()])

    for path <- [~p"/fitness", ~p"/fitness/day/#{other}", ~p"/fitness/day/#{other}?view=page"] do
      {view, _html} = admin(conn, path)
      assert has_element?(view, ~s(.view-toggle-btn[aria-pressed="true"]), "Focus")
      assert has_element?(view, "#view-toggle[data-asked='false']")
    end
  end

  test "a card says last time once, and today's sets are not last time", %{conn: conn} do
    {:ok, exercise} = Web.Fitness.loggable_exercise("push-ups")

    for {days, reps} <- [{-3, "10"}, {0, "14"}] do
      {:ok, _} =
        Web.Fitness.create_exercise_log(%{
          exercise_id: exercise.id,
          date: Date.add(Web.Clock.local_today(), days),
          metrics: %{"sets" => "3", "reps" => reps}
        })
    end

    {view, _html} = admin(conn, ~p"/fitness/day/tuesday?view=list")
    card = view |> element("#card-push-ups") |> render()

    assert card =~ "3 x 10"
    refute card =~ ~r/session-card-(last|hint)[^<]*3 x 14/
    assert length(String.split(card, "session-card-last")) == 2
    refute card =~ ~r/session-card-hint[^<]*>\s*Last/
  end

  test "a lift logs from its chips: no Log button, and Finish appears once", %{conn: conn} do
    {view, _html} = admin(conn, ~p"/fitness/day/tuesday?view=list")

    assert has_element?(view, "#next-push-ups")
    refute has_element?(view, "button.session-card-log[phx-value-slug='push-ups']")

    finishes = view |> render() |> String.split(~s(phx-click="finish_session")) |> length()
    assert finishes == 2
  end

  test "a session of several modules jumps straight to one; a plain one has no jumps", %{
    conn: conn
  } do
    {plain, _} = admin(conn, ~p"/fitness/day/tuesday?view=focus")
    refute has_element?(plain, ".session-jumps")

    {view, _} = admin(conn, ~p"/fitness/day/wednesday?view=focus")
    assert has_element?(view, ~s(.session-jump[aria-current="true"]), "Ride In")

    view |> element(".session-jump", "Pair Day") |> render_click()
    assert has_element?(view, ~s(.session-jump[aria-current="true"]), "Pair Day")
    assert has_element?(view, ".session-superset-title", "Superset A: Push and Pull")
  end

  test "focus shows one station, moves on, and finishes with a summary", %{conn: conn} do
    {view, _} = admin(conn, ~p"/fitness/day/wednesday?view=focus&at=1")

    assert has_element?(view, ".session-superset-title", "Superset A: Push and Pull")
    # The fixture block runs 520 weeks from January 2026; only this week's
    # line shows.
    assert has_element?(view, ".session-notes li", "of 520: every week's line")
    refute has_element?(view, ".session-notes li", "only the first week")

    render_click(view, "set_done", %{"slug" => "push-ups"})
    render_click(view, "set_done", %{"slug" => "dumbbell-rows"})
    assert has_element?(view, "#sets-dumbbell-rows .log-set.is-done", "30×10")

    view |> element(".session-nav-btn--next", "Next: Plank") |> render_click()
    view |> element(".session-nav-btn--next", "Finish session") |> render_click()
    assert has_element?(view, "#session-summary", "2 sets")
    assert has_element?(view, "#session-summary", "300 lb moved")
  end

  test "in a superset the rest waits for the last of the pair", %{conn: conn} do
    {view, _} = admin(conn, ~p"/fitness/day/wednesday?view=focus")

    render_click(view, "set_done", %{"slug" => "push-ups"})
    refute_push_event(view, "rest:start", %{})

    render_click(view, "set_done", %{"slug" => "dumbbell-rows"})
    assert_push_event(view, "rest:start", %{seconds: 60, label: "Dumbbell Rows"})
  end

  test "a better set than ever before says so", %{conn: conn} do
    {:ok, ex} = Web.Fitness.loggable_exercise("dumbbell-rows")

    {:ok, _} =
      Web.Fitness.create_exercise_log(%{
        exercise_id: ex.id,
        date: Date.add(Web.Clock.local_today(), -7),
        metrics: Web.Fitness.Entry.sets_metrics([%{"w" => 25.0, "r" => 10}])
      })

    {view, _} = admin(conn, ~p"/fitness/day/wednesday?view=list")
    assert has_element?(view, ".session-card-last", "Last,")

    # The set starts from last time's 25 lb; five more is a best.
    render_click(view, "set_done", %{"slug" => "dumbbell-rows"})
    refute has_element?(view, "#flash-info", "New best")

    render_click(view, "set_adjust", %{
      "slug" => "dumbbell-rows",
      "i" => "0",
      "field" => "w",
      "by" => "5"
    })

    assert has_element?(view, "#flash-info", "New best on Dumbbell Rows")
  end

  # A ride is logged by Komoot, so it is a brief: shown in its place, done
  # once anything after it is, and folded in the list like the rest.
  test "a ride is a brief, in its place, done when the next thing is", %{conn: conn} do
    {view, _} = admin(conn, ~p"/fitness/day/wednesday?view=focus&at=0")
    assert has_element?(view, ".session-brief", "Easy, conversational")

    for _ <- 1..3,
        slug <- ~w(push-ups dumbbell-rows),
        do: render_click(view, "set_done", %{"slug" => slug})

    {view, _} = admin(conn, ~p"/fitness/day/wednesday?view=list")
    assert has_element?(view, "details.session-done", "Ride In")
  end

  test "the Next set line sets the weight the tap logs", %{conn: conn} do
    {view, _} = admin(conn, ~p"/fitness/day/wednesday?view=focus&at=1")
    assert has_element?(view, "#next-dumbbell-rows", "30 lb")

    render_click(view, "draft_adjust", %{"slug" => "dumbbell-rows", "field" => "w", "by" => "5"})
    assert has_element?(view, "#next-dumbbell-rows", "35 lb")
    assert has_element?(view, "#sets-dumbbell-rows .log-set", "35×10")

    render_click(view, "set_done", %{"slug" => "dumbbell-rows"})
    assert has_element?(view, "#sets-dumbbell-rows .log-set.is-done", "35×10")
    # the next set repeats it
    assert has_element?(view, "#next-dumbbell-rows", "35 lb")
  end

  test "focus moves on when the station is done: a lift once its RPE is in", %{conn: conn} do
    {view, _} = admin(conn, ~p"/fitness/day/wednesday?view=focus&at=1")

    for _ <- 1..3,
        slug <- ~w(push-ups dumbbell-rows),
        do: render_click(view, "set_done", %{"slug" => slug})

    # the sets are in, but the RPE row is still there to tap
    assert has_element?(view, "#rpe-push-ups")
    assert has_element?(view, ".session-superset-title")

    render_click(view, "set_rpe", %{"slug" => "push-ups", "rpe" => "8"})
    assert has_element?(view, ".session-superset-title")
    render_click(view, "set_rpe", %{"slug" => "dumbbell-rows", "rpe" => "8"})

    refute has_element?(view, ".session-superset-title")
    assert has_element?(view, "#card-plank")
  end

  test "a tap on an exercise's name opens its figure sheet", %{conn: conn} do
    {view, _} = admin(conn, ~p"/fitness/day/wednesday?view=list")

    view |> element(~s(.session-card-name[phx-value-slug="dumbbell-rows"])) |> render_click()
    assert has_element?(view, "#figure-sheet", "A row.")

    render_click(view, "close_figure")
    refute has_element?(view, "#figure-sheet")
  end
end
