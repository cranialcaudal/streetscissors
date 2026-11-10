defmodule WebWeb.FitnessLive.Index do
  @moduledoc """
  The training plan, one day to a page (`/fitness` is today by the Pacific
  clock; `/fitness/day/thursday` is Thursday, whatever day it is).

  The admin can also open any other session at `/fitness/session/<slug>`.
  Exercises are read from the vault (the day's file in
  `content/fitness/weeks/<program>/` and the modules it lists) by
  `Web.Fitness.Vault`, and shown as a checklist whose ticks the browser
  remembers (the `GymRoutine` hook, `assets/js/gym_routine.js`).

  **For the admin, the page is also the training log.** Each exercise gets a
  Log button. During a training block the line under it says what today's
  target is and why (`Web.Fitness.Coach`), and the log form starts from the
  plan's own numbers. A lift (sets of reps, loaded or not) also gets its sets
  as chips with the target written on them: a tap logs a set and starts the
  rest timer, a tap on a logged set opens its stepper, and after the planned
  sets one tap gives the RPE. Ticking a lift's box logs its planned sets.
  Visitors see only the plan.

  **A session runs as stations for the admin** (`WebWeb.FitnessLive.SessionView`,
  from `Web.Fitness.Session`): `?view=focus` shows one station at a time
  (an exercise, a superset, a circuit) with Back and Next and a swipe,
  `?view=list` all of them with the finished ones folded, `?view=page` the
  plan as visitors see it. A logged set hands its rest to the rest bar (kept
  in the browser), a set that beats every earlier one says so
  (`Web.Fitness.Records`), and Finish sums the session up.

  Pages link to each other with `navigate`, never `patch` (the comment above
  `mount/3` explains why).

  ## How this file is laid out

  1. **Opening a page** (`mount/3`, `mount_day/4`, `mount_session/3`,
     `handle_params/3`): a day or a session, and its plan.
  2. **Logging** (`handle_event/3`): opening, filling, saving, editing and
     removing a log entry, and the set chips. Admin only: the first clause
     turns away every event a visitor sends but the two in `@visitor_events`.
     An entry is filed under today unless the form names an earlier day.
  3. **Saving an entry** (`save/5`, and `save_sets/4` for the chips).
  4. **Targets** (`assign_coach/1` to `format_n/1`): what the plan's own
     lines and the training block ask of each exercise today.
  5. **What a logged entry says** (`log_line/1` to `blank_to_nil/1`).
  6. **The log form's fields** (`log_fields/1` to `num/1`): which fields,
     for which kind of exercise.
  7. **The page itself** (`render/1`).
  """

  use WebWeb, :live_view

  alias Web.Fitness

  alias Web.Fitness.{
    Block,
    Checks,
    Coach,
    Entry,
    Plates,
    Prescription,
    Progression,
    Records,
    Session,
    Vault
  }

  alias WebWeb.FitnessLive.SessionView

  # The fuelling plan is the admin's alone (`/admin/fitness/fueling`): it is
  # never drawn here, and never offered among the extra modules.
  @fuelling "nutrition-module"
  # The circuit timer is drawn inside the plan's raw HTML, where HEEx does not
  # expand a colocated hook's short name, so it is named in full.
  @circuit_hook "#{inspect(__MODULE__)}.Circuit"

  # ── Opening a page ────────────────────────────────────────────────────────

  # One day to a page. `/fitness` is always today, by the Pacific clock, so it
  # moves on by itself; `/fitness/day/thursday` is Thursday whatever the day, so
  # the day being looked at is in the address and a reload keeps it.
  # `/fitness/session/<slug>` is any other session, for the admin alone, and is
  # treated as today's. Days link with `navigate`, not `patch`: the checklist is
  # raw HTML whose ticks GymRoutine restores on mount, and a patch would carry
  # one day's ticked boxes over onto the next.
  @impl true
  def mount(%{"modules" => _}, _session, socket) do
    {:ok, push_navigate(socket, to: ~p"/fitness")}
  end

  def mount(%{"slug" => slug}, session, socket) do
    is_admin = session["admin_user"] == true

    case is_admin && Vault.session(slug) do
      found when is_map(found) -> {:ok, mount_session(socket, found, is_admin)}
      _ -> {:ok, push_navigate(socket, to: ~p"/fitness")}
    end
  end

  def mount(params, session, socket) do
    is_admin = session["admin_user"] == true
    today = Web.Clock.today_slug()

    case Vault.day(params["day"] || today) do
      nil -> {:ok, push_navigate(socket, to: ~p"/fitness")}
      day -> {:ok, mount_day(socket, day, day.slug == today, is_admin)}
    end
  end

  defp mount_day(socket, day, live?, is_admin) do
    socket
    |> assign(:live_day?, live?)
    |> assign(:strip, strip())
    |> mount_page(day, is_admin)
    |> assign(:page_title, "#{String.capitalize(day.slug)} · Fitness & Sport")
  end

  defp mount_session(socket, session, is_admin) do
    socket
    |> assign(:live_day?, true)
    |> assign(:strip, [])
    |> mount_page(session, is_admin)
    |> assign(:page_title, "#{session.title} · Fitness & Sport")
  end

  defp mount_page(socket, day, is_admin) do
    socket
    |> assign(:day, with_html(day))
    |> assign(
      :extra_modules,
      Vault.list_additional() |> Enum.reject(&(&1.slug == @fuelling)) |> Enum.map(&with_html/1)
    )
    |> assign_common(is_admin)
  end

  # The running program's sessions, for a day that goes another way.
  defp other_sessions do
    all = Vault.list_sessions()

    case Block.current(Web.Clock.local_today()) do
      %{sessions: [_ | _] = slugs} -> Enum.filter(all, &(&1.slug in slugs))
      _ -> all
    end
  end

  # The days in order, each over the one word its file gives as `theme:`.
  defp strip do
    for day <- Vault.list_days() do
      %{
        slug: day.slug,
        name: String.capitalize(day.slug),
        theme: day.theme,
        title: String.replace(day.title, ~r/^\w+:\s*/, "")
      }
    end
  end

  defp day_path(slug) do
    if slug == Web.Clock.today_slug(), do: ~p"/fitness", else: ~p"/fitness/day/#{slug}"
  end

  defp assign_common(socket, is_admin) do
    socket
    |> assign(:is_admin, is_admin)
    # The block's week and every number are the admin's: a
    # visitor's page says nothing of training state (see the privacy tests).
    |> assign(:block, if(is_admin, do: Block.current(Web.Clock.local_today())))
    |> assign(:other_sessions, if(is_admin, do: other_sessions(), else: []))
    |> assign(:logging, nil)
    |> assign(:open_set, nil)
    |> assign(:log_today, Web.Clock.local_today())
    |> assign(view: "focus", view_asked?: false, focus: 0, summary: nil, figure: nil, draft: %{})
    |> assign(
      :gym,
      if(is_admin, do: Plates.settings(), else: %{plates: [], bars: %{}, lifts: %{}})
    )
    |> assign_coach()
    |> assign_logged_today()
  end

  # A day's checklist, plus any rotating options. Days that do the same thing
  # every week come back with `options: []`, so the template handles both
  # shapes the same way.
  # The key the saved ticks hang off (`vault_gym_<data-day>_<index>` in
  # GymRoutine).
  defp day_key(slug), do: slug

  defp with_html(nil), do: nil

  defp with_html(day) do
    case Vault.get_day_with_options(day.slug) do
      {:ok, %{html: html, options: options}} -> Map.merge(day, %{html: html, options: options})
      _ -> Map.merge(day, %{html: "", options: []})
    end
  end

  # The admin's day is a session: `?view=focus`, one station at a time, or
  # `?view=list`. With no view asked for it opens in focus, and the ViewMemory
  # hook moves it to the one this browser last used. A visitor gets the plan.
  @impl true
  def handle_params(params, _uri, %{assigns: %{is_admin: true}} = socket) do
    view =
      case params["view"] do
        v when v in ~w(focus list) -> v
        _ -> "focus"
      end

    focus =
      case Integer.parse(to_string(params["at"])) do
        {i, ""} when i >= 0 -> i
        _ -> Session.current(socket.assigns.session)
      end

    {:noreply,
     assign(socket, view: view, focus: focus, view_asked?: params["view"] in ~w(focus list))}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  # ── Events: whose they are ────────────────────────────────────────────────

  # The events a visitor may send. Both close the log form, which only the
  # admin can open, so for a visitor they do nothing. Every other event is the
  # admin's (the log, the set chips, the session), and this clause, which has
  # to stay first, turns a visitor's away: an event added below is closed to
  # visitors without being listed anywhere, and one a visitor is to have is
  # added here.
  @visitor_events ~w(close_log log_key)

  @impl true
  def handle_event(event, _params, %{assigns: %{is_admin: false}} = socket)
      when event not in @visitor_events,
      do: {:noreply, socket}

  # ── Logging: the form's buttons ───────────────────────────────────────────

  # Fired by the inline "Log" button that Web.Fitness.Vault stitches onto any
  # checkbox line referencing a `[[slug]]` exercise (see
  # Vault.render_markdown/1's ⟦LOG:slug⟧ marker). Any exercise the wiki has
  # can be logged (`Fitness.loggable_exercise/1`); the form opens showing the
  # last entry for it, which is the number to beat.
  def handle_event("open_log", %{"slug" => slug}, socket) do
    case Fitness.loggable_exercise(slug) do
      {:ok, exercise} ->
        {:noreply,
         assign(socket, :logging, %{
           slug: slug,
           name: exercise.name,
           last: Fitness.last_exercise_log(exercise.id, Web.Clock.local_today()),
           plan: plan_for(socket, slug, exercise.name)
         })}

      :error ->
        {:noreply, put_flash(socket, :error, "There is no exercise by that name in the wiki.")}
    end
  end

  def handle_event("close_log", _params, socket), do: {:noreply, close_log(socket)}

  # Escape closes the form. Any other key is somebody typing in it.
  def handle_event("log_key", %{"key" => "Escape"}, socket), do: {:noreply, close_log(socket)}
  def handle_event("log_key", _params, socket), do: {:noreply, socket}

  def handle_event(
        "save_log",
        %{"log" => params},
        %{assigns: %{logging: %{slug: slug} = logging}} = socket
      ) do
    save(
      socket,
      slug,
      params |> counted(logging.plan) |> Entry.metrics(),
      blank_to_nil(params["note"]),
      Entry.date(params["date"])
    )
  end

  def handle_event("save_log", _params, socket), do: {:noreply, socket}

  # One tap: the set the plan (or the target) asks for, logged as done. From
  # the "Done" button under a line, or the form's "Done as planned". A lift
  # with set chips gets the sets still to do, so a tick or a Done after two
  # logged sets makes three, not six. A held lift is not logged.
  def handle_event("log_planned", %{"slug" => slug}, socket) do
    with {:ok, exercise} <- Fitness.loggable_exercise(slug) do
      plan = plan_for(socket, slug, exercise.name)

      cond do
        elem(plan.verdict, 0) == :stop ->
          {:noreply, put_flash(socket, :info, "Not logged: #{plan.guard || "held today"}.")}

        chips?(plan) ->
          done = todays_sets(socket, slug)
          todo = max(planned_sets(plan) - length(done), 0)
          sets = done ++ List.duplicate(next_set(plan, done), todo)
          {:noreply, socket |> close_log() |> save_sets(exercise, sets, flash: true)}

        true ->
          save(socket, slug, planned_metrics(plan), nil, Web.Clock.local_today())
      end
    else
      :error ->
        {:noreply, put_flash(socket, :error, "There is no exercise by that name in the wiki.")}
    end
  end

  # ── Logging: the set chips ────────────────────────────────────────────────

  # Under each lift the admin sees its sets as chips. A tap on a chip still
  # to do logs that set (the first makes today's entry, each after it adds to
  # it) and starts the rest timer; a tap on a logged chip opens its stepper;
  # once the planned sets are in, one tap gives the last set's RPE.
  #
  # The set logged is the one the card's Next set line shows: what the
  # admin dialled in, else today's last set again, else the target.
  def handle_event("set_done", %{"slug" => slug}, socket) do
    with_plan(socket, slug, fn exercise, plan ->
      done = todays_sets(socket, slug)
      set = Map.get(socket.assigns.draft, slug) || next_set(plan, done)

      socket
      |> assign(open_set: nil, draft: Map.delete(socket.assigns.draft, slug))
      |> start_rest(slug, plan, exercise.name)
      |> save_sets(exercise, done ++ [Map.put(set, "rpe", nil)])
    end)
  end

  # The Next set line's steppers: the weight and reps the next tap logs.
  def handle_event("draft_adjust", %{"slug" => slug, "field" => field, "by" => by}, socket)
      when field in ["w", "r"] do
    with plan when not is_nil(plan) <- socket.assigns.coach[slug],
         {by, ""} <- Float.parse(to_string(by)) do
      base = Map.get(socket.assigns.draft, slug) || next_set(plan, todays_sets(socket, slug))

      {:noreply,
       assign(socket, :draft, Map.put(socket.assigns.draft, slug, adjust(base, field, by)))}
    else
      _ -> {:noreply, socket}
    end
  end

  # ── The session: its view, the station in focus, its end ──────────────────

  def handle_event("set_view", %{"view" => view}, socket) when view in ~w(focus list) do
    {:noreply, push_patch(socket, to: view_path(socket, view))}
  end

  def handle_event("focus_step", %{"by" => by}, socket) do
    last = max(length(socket.assigns.session.stations) - 1, 0)

    focus =
      case Integer.parse(to_string(by)) do
        {by, ""} -> (socket.assigns.focus + by) |> max(0) |> min(last)
        _ -> socket.assigns.focus
      end

    {:noreply, assign(socket, focus: focus, open_set: nil)}
  end

  def handle_event("focus_to", %{"i" => i}, socket) do
    case index(i) do
      nil -> {:noreply, socket}
      i -> {:noreply, push_patch(socket, to: view_path(socket, "focus", i))}
    end
  end

  def handle_event("finish_session", _params, socket),
    do: {:noreply, assign(socket, :summary, summary(socket))}

  def handle_event("close_summary", _params, socket),
    do: {:noreply, assign(socket, :summary, nil)}

  def handle_event("show_figure", %{"slug" => slug}, socket) do
    case Vault.get_exercise_by_slug(slug) do
      {:ok, exercise} ->
        {:noreply,
         assign(socket, :figure, %{
           slug: slug,
           name: exercise.name,
           description: exercise.short_description,
           clip: Web.Fitness.Clip.find(slug, exercise.anatomy)
         })}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_event("close_figure", _params, socket), do: {:noreply, assign(socket, :figure, nil)}

  def handle_event("set_open", %{"slug" => slug, "i" => i}, socket) do
    open = {slug, index(i)}

    {:noreply,
     assign(socket, :open_set, if(socket.assigns.open_set == open, do: nil, else: open))}
  end

  def handle_event("set_close", _params, socket), do: {:noreply, assign(socket, :open_set, nil)}

  def handle_event(
        "set_adjust",
        %{"slug" => slug, "i" => i, "field" => field, "by" => by},
        socket
      )
      when field in ["w", "r"] do
    with_plan(socket, slug, fn exercise, _plan ->
      case {index(i), Float.parse(by)} do
        {i, {by, ""}} when is_integer(i) ->
          sets = List.update_at(todays_sets(socket, slug), i, &adjust(&1, field, by))
          save_sets(socket, exercise, sets)

        _ ->
          socket
      end
    end)
  end

  def handle_event("set_remove", %{"slug" => slug, "i" => i}, socket) do
    with_plan(socket, slug, fn exercise, _plan ->
      case index(i) do
        nil ->
          socket

        i ->
          sets = List.delete_at(todays_sets(socket, slug), i)
          socket |> assign(:open_set, nil) |> save_sets(exercise, sets)
      end
    end)
  end

  # The circuit timer's Finish: the whole circuit as one entry, its rounds as
  # the sets, its time, and the one bell. A second run today replaces it.
  def handle_event("circuit_done", %{"slug" => slug} = params, socket) do
    with %{prescription: %{kind: :circuit} = p} <- socket.assigns.coach[slug],
         rounds when is_integer(rounds) and rounds > 0 <- whole(params["rounds"]),
         seconds when is_integer(seconds) and seconds >= 0 <- whole(params["seconds"]),
         {:ok, exercise} <- Fitness.circuit_exercise(slug, p.name) do
      metrics =
        %{"sets" => Integer.to_string(min(rounds, 20)), "time" => rest_clock(seconds)}
        |> then(
          &if(p.weight, do: Map.put(&1, "weight", "#{Entry.number(p.weight)} lbs"), else: &1)
        )

      result =
        case todays_log(socket, slug) do
          nil ->
            Fitness.create_exercise_log(%{
              exercise_id: exercise.id,
              date: Web.Clock.local_today(),
              metrics: metrics
            })

          log ->
            Fitness.update_exercise_log(log, %{metrics: metrics})
        end

      case result do
        {:ok, log} ->
          {:noreply,
           socket
           |> put_flash(:info, "Logged #{p.name}: #{Fitness.entry_line(log)}.")
           |> assign_coach()
           |> assign_logged_today()}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Couldn't save that — try again.")}
      end
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("set_rpe", %{"slug" => slug, "rpe" => rpe}, socket) do
    with_plan(socket, slug, fn exercise, _plan ->
      case {todays_sets(socket, slug), Float.parse(rpe)} do
        {[_ | _] = sets, {rpe, ""}} when rpe >= 6 and rpe <= 10 ->
          save_sets(socket, exercise, List.update_at(sets, -1, &Map.put(&1, "rpe", rpe)))

        _ ->
          socket
      end
    end)
  end

  # An entry already made opens the same form, its fields at what it says.
  def handle_event("edit_log", %{"id" => id}, socket) do
    with {id, ""} <- Integer.parse(id),
         %{exercise: exercise} = log <- Fitness.get_exercise_log(id) do
      plan = plan_for(socket, exercise.slug, exercise.name)

      {:noreply,
       assign(socket, :logging, %{
         slug: exercise.slug,
         name: exercise.name,
         last: nil,
         plan: %{plan | defaults: Map.merge(plan.defaults, defaults_from(log))},
         editing: log
       })}
    else
      _ -> {:noreply, put_flash(socket, :error, "That entry is not there any more.")}
    end
  end

  def handle_event("delete_log", %{"id" => id}, socket) do
    with {id, ""} <- Integer.parse(id), do: Fitness.delete_exercise_log(id)

    {:noreply,
     socket |> put_flash(:info, "Entry removed.") |> assign_coach() |> assign_logged_today()}
  end

  # ── Saving an entry ───────────────────────────────────────────────────────

  defp save(socket, slug, metrics, note, date) do
    with {:ok, exercise} <- Fitness.loggable_exercise(slug),
         true <- map_size(metrics) > 0 do
      attrs = %{exercise_id: exercise.id, date: date, metrics: metrics, note: note}

      result =
        case socket.assigns.logging do
          %{editing: log} -> Fitness.update_exercise_log(log, attrs)
          _ -> Fitness.create_exercise_log(attrs)
        end

      case result do
        {:ok, log} ->
          {:noreply,
           socket
           |> put_flash(:info, "#{saved_words(exercise.name, log)}: #{Fitness.entry_line(log)}.")
           |> close_log()
           |> assign_coach()
           |> assign_logged_today()
           |> best_flash(log, exercise)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Couldn't save that — try again.")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Enter at least one value to log.")}
    end
  end

  defp close_log(socket), do: assign(socket, :logging, nil)

  # A logged entry that beats everything before its day says so.
  defp best_flash(socket, nil, _exercise), do: socket

  defp best_flash(socket, log, exercise) do
    earlier =
      exercise.slug
      |> Fitness.exercise_logs_for()
      |> Enum.filter(&(Date.compare(&1.date, log.date) == :lt))

    case Records.new_best(log, earlier) do
      {:best, score, previous} ->
        put_flash(
          socket,
          :info,
          "New best on #{exercise.name}: #{Records.describe(score)} (was #{Records.describe(previous)})."
        )

      nil ->
        socket
    end
  end

  # A lap count typed as a bare number is saved as "24 laps", so the entry
  # reads as what it is.
  defp counted(%{"result" => result} = params, %{prescription: %{kind: :laps}}) do
    case Integer.parse(String.trim(result || "")) do
      {n, ""} -> Map.put(params, "result", "#{n} laps")
      _ -> params
    end
  end

  defp counted(params, _plan), do: params

  # The chips' sets, saved as today's entry for the exercise: made by the
  # first, updated by every one after, removed when the last set goes. What
  # else the entry says (a distance, a note) stays.
  defp save_sets(socket, exercise, sets, opts \\ []) do
    log = todays_log(socket, exercise.slug)
    metrics = Entry.sets_metrics(sets)

    result =
      cond do
        sets == [] and log != nil ->
          Fitness.delete_exercise_log(log.id)

        sets == [] ->
          {:ok, nil}

        log != nil ->
          kept = Map.drop(log.metrics, ~w(weight sets reps rpe result set_list))
          Fitness.update_exercise_log(log, %{metrics: Map.merge(kept, metrics)})

        true ->
          Fitness.create_exercise_log(%{
            exercise_id: exercise.id,
            date: Web.Clock.local_today(),
            metrics: metrics
          })
      end

    case result do
      {:ok, saved} ->
        socket = socket |> assign_coach() |> assign_logged_today() |> best_flash(saved, exercise)

        if opts[:flash] && saved,
          do:
            put_flash(
              socket,
              :info,
              "#{saved_words(exercise.name, saved)}: #{Fitness.entry_line(saved)}."
            ),
          else: socket

      {:error, _changeset} ->
        put_flash(socket, :error, "Couldn't save that — try again.")
    end
  end

  defp with_plan(socket, slug, fun) do
    case Fitness.loggable_exercise(slug) do
      {:ok, exercise} ->
        {:noreply, fun.(exercise, plan_for(socket, slug, exercise.name))}

      :error ->
        {:noreply, put_flash(socket, :error, "There is no exercise by that name in the wiki.")}
    end
  end

  # Today's entry for an exercise (the newest, if there are two), and its sets.
  defp todays_log(socket, slug),
    do: socket.assigns.logged_today |> Enum.filter(&(&1.exercise.slug == slug)) |> List.last()

  defp todays_sets(socket, slug) do
    case todays_log(socket, slug) do
      nil -> []
      log -> Entry.set_list(log.metrics)
    end
  end

  defp chips?(plan), do: Session.chips?(plan)

  defp planned_sets(plan), do: Session.planned_sets(plan)

  defp next_set(plan, done), do: Session.next_set(plan, done)

  defp adjust(set, "w", by),
    do: Map.put(set, "w", max(Float.round((set["w"] || 0) + by, 1), 0.0))

  defp adjust(set, "r", by), do: Map.put(set, "r", max((set["r"] || 0) + trunc(by), 1))

  # The rest after a set, handed to the page's rest bar (its hook keeps the
  # end time in the browser, so it survives a locked phone or another page).
  # Inside a superset the rest comes after the last exercise of the pair.
  defp start_rest(socket, slug, plan, name) do
    if superset_waits?(socket, slug) do
      socket
    else
      push_event(socket, "rest:start", %{seconds: Session.rest_seconds(plan), label: name})
    end
  end

  defp superset_waits?(%{assigns: %{session: %{stations: stations}}}, slug) do
    Enum.any?(stations, fn
      %{type: :superset, items: items} ->
        slugs = Enum.map(items, & &1.slug)
        slug in slugs and slug != List.last(slugs)

      _ ->
        false
    end)
  end

  defp superset_waits?(_socket, _slug), do: false

  defp view_path(socket, view, at \\ nil) do
    base =
      if socket.assigns.strip == [],
        do: ~p"/fitness/session/#{socket.assigns.day.slug}",
        else: day_path(socket.assigns.day.slug)

    query = if at, do: %{view: view, at: at}, else: %{view: view}
    base <> "?" <> URI.encode_query(query)
  end

  # The end of a session: today's entries for the day, their time, their
  # sets and what they moved, which were bests, and what the plan asked that
  # was not logged.
  defp summary(socket) do
    logged = socket.assigns.logged_today
    session = socket.assigns.session
    slugs = session.stations |> Enum.flat_map(&Session.slugs/1)
    mine = Enum.filter(logged, &(&1.exercise.slug in slugs))
    today = Web.Clock.local_today()

    rows =
      for log <- mine do
        earlier =
          log.exercise.slug
          |> Fitness.exercise_logs_for()
          |> Enum.filter(&(Date.compare(&1.date, today) == :lt))

        best =
          case Records.new_best(log, earlier) do
            {:best, score, _} -> Records.describe(score)
            nil -> nil
          end

        %{name: log.exercise.name, line: Fitness.entry_line(log), best: best}
      end

    rows =
      rows ++
        for a <- activities_on(today), a.kind in [:ride, :run] do
          watts =
            cond do
              a.watts && a[:peak_watts] -> " · ≈#{a.watts} W (≈#{a.peak_watts} W peak)"
              a.watts -> " · ≈#{a.watts} W"
              true -> ""
            end

          %{
            name: if(a.kind == :run, do: "Run (Komoot)", else: "Ride (Komoot)"),
            line: "#{a.km} km · #{a.minutes} min#{watts}",
            best: nil
          }
        end

    sets = mine |> Enum.map(&length(Entry.set_list(&1.metrics))) |> Enum.sum()

    volume =
      for log <- mine,
          %{"w" => w, "r" => r} <- Entry.set_list(log.metrics),
          is_number(w),
          is_integer(r),
          reduce: 0.0 do
        acc -> acc + w * r
      end

    times = Enum.map(mine, & &1.inserted_at)

    minutes =
      if times != [] do
        first = Enum.min(times, NaiveDateTime)
        div(max(NaiveDateTime.diff(NaiveDateTime.utc_now(), first), 0), 60)
      end

    missed = for s <- session.stations, s.type != :brief, not s.done?, do: SessionView.label(s)

    %{
      rows: rows,
      sets: sets,
      volume: Float.round(volume, 0),
      minutes: minutes,
      missed: missed
    }
  end

  defp rest_clock(seconds),
    do: "#{div(seconds, 60)}:#{String.pad_leading("#{rem(seconds, 60)}", 2, "0")}"

  defp whole(n) when is_integer(n), do: n
  defp whole(n) when is_float(n), do: round(n)
  defp whole("" <> text), do: index(text)
  defp whole(_), do: nil

  defp index(text) do
    case Integer.parse(to_string(text)) do
      {i, ""} when i >= 0 -> i
      _ -> nil
    end
  end

  defp saved_words(name, %{date: date}) do
    if date == Web.Clock.local_today(),
      do: "Logged #{name}",
      else: "Logged #{name} on #{Calendar.strftime(date, "%a %-d %b")}"
  end

  # What an entry says, as the form's starting values (`Coach.defaults/3`'s
  # keys). A figure it doesn't read stays at the plan's.
  defp defaults_from(%{metrics: metrics}) do
    parsed = Progression.parse_log_metrics(metrics)

    %{
      weight: parsed.weight,
      sets: parsed.sets,
      reps: parsed.reps,
      # The dropdown's values are the strings "8", "8.5", …
      rpe: blank_to_nil(metrics["rpe"]),
      seconds: leading_integer(metrics["time"]),
      metres: leading_integer(metrics["distance"]),
      height: leading_integer(metrics["result"])
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp leading_integer("" <> text) do
    case Integer.parse(String.trim(text)) do
      {n, _rest} -> n
      :error -> nil
    end
  end

  defp leading_integer(_), do: nil

  # ── Targets: what the plan and the block ask for ──────────────────────────

  # Every exercise on the day as the admin sees it (Web.Fitness.Coach): the
  # line under it, its target and what its form starts from. Nothing for a
  # visitor.
  defp assign_coach(%{assigns: %{is_admin: true, day: day, block: block}} = socket) do
    assign(socket, :coach, Coach.day(day.slug, Web.Clock.local_today(), block))
  end

  defp assign_coach(socket), do: assign(socket, :coach, %{})

  # An exercise the day's plan does not list (a rotating option, an extra
  # module) still gets a form fitted to it, from its name.
  defp plan_for(%{assigns: %{coach: coach, block: block}}, slug, name) do
    Map.get_lazy(coach, slug, fn ->
      today = Web.Clock.local_today()
      logs = slug |> Fitness.exercise_logs_for() |> Enum.reverse()

      Coach.plan(
        Prescription.bare(slug, name),
        logs,
        block,
        [],
        Fitness.recent_checkins(today),
        Checks.all(),
        today
      )
    end)
  end

  @doc false
  def circuit_bar(slug, c, log) do
    how =
      cond do
        c.every > 0 -> "a round every #{div(c.every, 60)} min"
        c.rest > 0 -> "#{div(c.rest, 60)} min between rounds"
        true -> "straight through"
      end

    bell = if c.weight, do: ", one #{Entry.number(c.weight)} lb bell", else: ""

    logged =
      if log do
        line =
          log
          |> Fitness.entry_line()
          |> Phoenix.HTML.html_escape()
          |> Phoenix.HTML.safe_to_string()

        ~s(<p class="circuit-logged" id="circuit-logged-#{slug}">Logged today: #{line}</p>)
      else
        ""
      end

    ~s(<div class="circuit" id="circuit-#{slug}" phx-hook="#{@circuit_hook}" phx-update="ignore" ) <>
      ~s(data-slug="#{slug}" data-rounds="#{c.rounds}" data-every="#{c.every}" data-rest="#{c.rest}" ) <>
      ~s(data-day="#{Date.to_iso8601(Web.Clock.local_today())}">) <>
      ~s(<div class="circuit-head"><span class="circuit-how">#{c.rounds} rounds, #{how}#{bell}</span>) <>
      ~s(<span class="circuit-clock" data-clock>0:00</span></div>) <>
      ~s(<p class="circuit-cue" data-cue aria-live="polite">Round 1 of #{c.rounds}</p>) <>
      ~s(<div class="circuit-actions">) <>
      ~s(<button type="button" class="circuit-btn circuit-btn--go" data-start>Start circuit</button>) <>
      ~s(<button type="button" class="circuit-btn circuit-btn--go" data-round hidden>Round done</button>) <>
      ~s(<button type="button" class="circuit-btn" data-finish hidden>Finish and log</button>) <>
      ~s(</div></div>) <> logged
  end

  # The planned set as metrics: what "Done" logs.
  defp planned_metrics(%{defaults: d, prescription: p}) do
    %{}
    |> put_number(
      "weight",
      d.weight && p.kind in [:weight, :carry, :reps] && d.weight > 0 &&
        "#{format_n(d.weight)} lbs"
    )
    |> put_number("sets", d.sets)
    |> put_number("reps", d.reps && p.kind in [:weight, :reps, :jump] && d.reps)
    |> put_number("time", d.seconds && p.kind == :hold && "#{d.seconds} sec")
    |> put_number("time", d.seconds && p.kind == :timed && "#{div(d.seconds, 60)} min")
    |> put_number("distance", d.metres && p.kind == :carry && "#{d.metres} m")
    |> put_number("distance", d[:yards] && p.kind == :swim && "#{d.yards} yd")
    |> then(fn m -> if p.kind in [:trial, :laps], do: %{}, else: m end)
  end

  defp put_number(map, _key, v) when v in [nil, false, ""], do: map
  defp put_number(map, key, v), do: Map.put(map, key, to_string(v))

  defp format_n(w) when is_float(w) and w == trunc(w), do: Integer.to_string(trunc(w))
  defp format_n(w), do: to_string(w)

  # What has been logged today, for the admin only: the proof an entry went
  # in, and the place to take a wrong one back out.
  # With today's entries, the admin's session (what is done, what is next)
  # and the week's colours are drawn again.
  defp assign_logged_today(%{assigns: %{is_admin: true}} = socket) do
    logged = Fitness.exercise_logs_on(Web.Clock.local_today())
    today = Web.Clock.local_today()

    activities = if socket.assigns.live_day?, do: activities_on(today), else: []
    session = Session.build(socket.assigns.day.slug, socket.assigns.coach, logged, activities)

    socket
    |> advance(socket.assigns[:session], session, logged)
    |> assign(:logged_today, logged)
    |> assign(:session, session)
  end

  defp assign_logged_today(socket),
    do:
      assign(socket,
        logged_today: [],
        session: %{modules: [], stations: []}
      )

  # Today's Komoot tours (rides and runs), as the session shows them.
  defp activities_on(date) do
    Web.Rides.list_rides()
    |> Enum.filter(&(Web.Clock.local_today(&1.started_at) == date))
    |> Enum.map(&Session.activity(&1, Web.Rides.Power.for_ride(&1)))
  end

  # In focus, the station just finished hands over to the next one not yet
  # done. A lift is finished once its planned sets are in and its last set
  # has its RPE, so the RPE row is not taken away before it is tapped; a
  # hold, a swim or a circuit is finished when it is logged.
  defp advance(
         %{assigns: %{view: "focus", focus: i, logged_today: earlier}} = socket,
         %{stations: before},
         after_,
         logged
       ) do
    was = Enum.at(before, i)
    now = Enum.at(after_.stations, i)

    if was && now && not finished?(was, earlier) && finished?(now, logged) do
      next =
        Enum.find(after_.stations, &(&1.index > i and not &1.done?)) ||
          Enum.find(after_.stations, &(not &1.done?))

      assign(socket, focus: (next && next.index) || i, open_set: nil)
    else
      socket
    end
  end

  defp advance(socket, _before, _after, _logged), do: socket

  defp finished?(%{done?: false}, _logged), do: false
  defp finished?(%{type: :brief, komoot: [_ | _]}, _logged), do: true
  defp finished?(%{type: :brief}, _logged), do: false

  defp finished?(%{type: :exercise, plan: plan, slug: slug}, logged) do
    if Session.chips?(plan),
      do: logged |> Session.sets(slug) |> List.last() |> then(&(&1 && is_number(&1["rpe"]))),
      else: true
  end

  defp finished?(%{type: :superset, items: items}, logged),
    do: Enum.all?(items, &finished?(Map.put(&1, :done?, Session.done?(&1, logged)), logged))

  defp finished?(_station, _logged), do: true

  # ── What a logged entry says ──────────────────────────────────────────────

  @doc "A log entry's values in a line (`Web.Fitness.entry_line/1`)."
  def log_line(log), do: Fitness.entry_line(log)

  defp today_progress(%{stations: []}), do: "nothing to log"

  defp today_progress(%{stations: stations}) do
    done = Enum.count(stations, & &1.done?)
    "#{done} of #{length(stations)} done"
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  # The log form's fields, fitted to the exercise (`Prescription` kinds):
  # dropdowns that start at the target, else the last entry, else the plan,
  # so logging the usual is a Save and a change is one pick.
  attr :plan, :map, required: true
  attr :editing, :map, default: nil

  # ── The log form's fields ─────────────────────────────────────────────────

  defp log_fields(assigns) do
    d = assigns.plan.defaults
    kind = assigns.plan.prescription.kind
    {_low, high} = reps_range(assigns.plan)

    assigns =
      assign(assigns,
        kind: kind,
        d: d,
        weights: weight_options(d.weight),
        reps: Enum.to_list(1..max(20, high + 5)),
        seconds: Enum.to_list(10..180//5),
        metres: Enum.to_list(10..200//10),
        heights: Enum.to_list(6..42//2)
      )

    ~H"""
    <div class="log-modal-row">
      <label :if={@kind in [:weight, :carry, :reps]}>
        {if @kind == :reps, do: "Added weight", else: "Weight"}
        <select name="log[weight]">
          <option value="0" selected={is_nil(@d.weight)}>
            {if @kind == :reps, do: "none", else: "—"}
          </option>
          <option :for={w <- @weights} value={num(w)} selected={@d.weight == w}>{num(w)} lb</option>
        </select>
      </label>
      <label :if={@kind not in [:trial, :laps, :timed]}>
        Sets
        <select name="log[sets]">
          <option :for={n <- 1..8} value={n} selected={(@d.sets || 3) == n}>{n}</option>
        </select>
      </label>
      <label :if={@kind in [:weight, :reps, :jump]}>
        Reps
        <select name="log[reps]">
          <option :for={n <- @reps} value={n} selected={@d.reps == n}>{n}</option>
        </select>
      </label>
      <label :if={@kind == :hold}>
        Seconds
        <select name="log[seconds]">
          <option :for={n <- @seconds} value={n} selected={(@d.seconds || 30) == n}>{n}</option>
        </select>
      </label>
      <label :if={@kind == :carry}>
        Metres
        <select name="log[metres]">
          <option :for={n <- @metres} value={n} selected={(@d.metres || 40) == n}>{n}</option>
        </select>
      </label>
      <label :if={@kind == :jump}>
        Height (in)
        <select name="log[height]">
          <option value="">—</option>
          <option :for={n <- @heights} value={n} selected={@d.height == n}>{n}</option>
        </select>
      </label>
      <label :if={@kind == :swim}>
        Distance
        <input
          type="text"
          name="log[distance]"
          value={@d[:yards] && "#{@d.yards} yd"}
          placeholder="e.g. 200 yd"
        />
      </label>
      <label :if={@kind in [:swim, :trial, :laps, :timed]}>
        {if @kind in [:laps, :timed], do: "Minutes", else: "Time"}
        <input
          type="text"
          name="log[time]"
          value={@kind in [:laps, :timed] && @d.seconds && "#{div(@d.seconds, 60)} min"}
          placeholder={if @kind == :laps, do: "e.g. 15 min", else: "e.g. 5:30"}
        />
      </label>
      <label :if={@kind in [:trial, :laps]}>
        {if @kind == :laps, do: "Laps", else: "Strokes per length"}
        <input
          type="text"
          name="log[result]"
          inputmode="numeric"
          placeholder={if @kind == :laps, do: "e.g. 24 laps", else: "e.g. 18"}
        />
      </label>
      <label :if={@kind in [:weight, :reps, :jump]}>
        RPE
        <select name="log[rpe]" title="7: three left in the tank · 8: two · 9: one · 10: none">
          <option value="">—</option>
          <option :for={r <- rpe_options()} value={r} selected={@d.rpe == r}>{r}</option>
        </select>
      </label>
    </div>
    <label :if={@kind in [:weight, :carry, :reps]} class="log-modal-other">
      Another weight
      <input
        type="text"
        name="log[weight_other]"
        placeholder="e.g. 47.5 lbs, 20 kg"
        value={typed_weight(@editing)}
      />
    </label>
    """
  end

  # An entry's weight the dropdown can't hold as it was written (kilograms,
  # a fraction), kept in the typed field so an edit doesn't change it.
  defp typed_weight(%{metrics: %{"weight" => "" <> weight}}) do
    if Regex.match?(~r/\A\d+(\.0)?\s*lbs\z/, weight), do: nil, else: weight
  end

  defp typed_weight(_editing), do: nil

  # A free-text figure an entry carries, for the form's "Something else".
  # A result like "3 x 12" is already the form's sets and reps, so it is not
  # written out a second time.
  defp written(nil, _key), do: nil

  defp written(%{metrics: metrics}, "result") do
    from_result? = metrics["sets"] == nil and Progression.parse_log_metrics(metrics).sets != nil
    if from_result?, do: nil, else: metrics["result"]
  end

  defp written(%{metrics: metrics}, key), do: metrics[key]

  defp reps_range(%{rule: %{low: low, high: high}}), do: {low, high}
  defp reps_range(%{prescription: %{reps: {low, high}}}), do: {low, high}
  defp reps_range(_plan), do: {1, 12}

  # Stepped around where the lift is: 2.5 lb under 25 lb, 5 above; a lift
  # with no weight yet gets the usual dumbbell and plate run.
  defp weight_options(nil),
    do: (Enum.to_list(5..100//5) ++ Enum.to_list(110..400//10)) |> Enum.map(&(&1 * 1.0))

  defp weight_options(ref) do
    step = if ref < 25, do: 2.5, else: 5.0
    for i <- -8..8, w = Float.round(ref + i * step, 1), w > 0, do: w
  end

  defp rpe_options, do: ~w(6 6.5 7 7.5 8 8.5 9 9.5 10)

  defp num(w) when is_float(w) and w == trunc(w), do: Integer.to_string(trunc(w))
  defp num(w), do: to_string(w)

  # ── The page itself (render) ──────────────────────────────────────────────

  attr :logged, :list, required: true

  defp logged_today(assigns) do
    ~H"""
    <section class="day-logged" id="logged-today">
      <h2 class="day-page-section">Logged today</h2>
      <ul class="day-logged-list">
        <li :for={log <- @logged} id={"logged-#{log.id}"}>
          <span class="day-logged-name">{log.exercise.name}</span>
          <span class="day-logged-values">{log_line(log)}</span>
          <button type="button" class="reset-btn" phx-click="edit_log" phx-value-id={log.id}>
            Edit
          </button>
          <button
            type="button"
            class="reset-btn"
            phx-click="delete_log"
            phx-value-id={log.id}
            data-confirm={"Remove this #{log.exercise.name} entry?"}
          >
            Remove
          </button>
        </li>
      </ul>
    </section>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="blog-bento-wrapper steel fitness-landing">
      <%!-- The section's tabs lead, as they do on the wiki and Activities, so
            both are one click from the top. --%>
      <WebWeb.FitnessSubnav.subnav active={:regimen} />

      <nav :if={@strip != []} class="day-strip" aria-label="Days of the week">
        <.link
          :for={day <- @strip}
          navigate={day_path(day.slug)}
          class={["day-strip-link", day.slug == Web.Clock.today_slug() && "is-today"]}
          aria-current={day.slug == @day.slug && "page"}
          title={day.name}
        >
          <span class="day-strip-name">{String.slice(day.name, 0, 3)}</span>
          <span :if={day.theme} class="day-strip-theme">{day.theme}</span>
        </.link>
      </nav>

      <div
        class={"blog-bento-card" <> if(@is_admin, do: " is-admin", else: "")}
        id="weekly-routine"
        phx-hook="GymRoutine"
        data-keep-awake={@is_admin && @live_day? && "true"}
      >
        <div class="fitness-layout">
          <div class="fitness-main">
            <%!-- `.day-details` and `data-day` are what GymRoutine keys a
                  saved tick on (`vault_gym_<data-day>_<index>`), as they were
                  when every day shared one page. --%>
            <article class="day-details day-page" data-day={day_key(@day.slug)}>
              <header class="day-page-head">
                <p :if={!@live_day?} class="day-page-when">
                  <.link navigate={~p"/fitness"} class="day-page-back">Back to today</.link>
                </p>
                <h1 class="day-page-title">{@day.title}</h1>
                <p :if={@block} class="day-page-block" id="block-week">
                  {@block.title} · Week {@block.week} of {@block.weeks}
                </p>
              </header>

              <%!-- The admin's session: today's card, then one station at a
                    time or the list. --%>
              <div :if={@is_admin} class="session-bar" id="session-bar">
                <div :if={@live_day?} class="today-card" id="today-card">
                  <p class="today-card-line">
                    <strong>Today</strong> · {today_progress(@session)}
                  </p>
                  <button
                    :if={@view != "focus" and @session.stations != []}
                    type="button"
                    class="session-nav-btn session-nav-btn--next"
                    phx-click="focus_to"
                    phx-value-i={Session.current(@session)}
                  >
                    {if Enum.any?(@session.stations, & &1.done?), do: "Resume", else: "Start"}
                  </button>
                </div>
                <div
                  class="view-toggle"
                  id="view-toggle"
                  role="group"
                  aria-label="How the day is shown"
                  data-view={@view}
                  data-asked={to_string(@view_asked?)}
                  phx-hook=".ViewMemory"
                >
                  <button
                    :for={{v, label} <- [{"focus", "Focus"}, {"list", "List"}]}
                    type="button"
                    class="view-toggle-btn"
                    aria-pressed={to_string(@view == v)}
                    phx-click="set_view"
                    phx-value-view={v}
                  >
                    {label}
                  </button>
                </div>
              </div>

              <SessionView.session
                :if={@is_admin}
                session={@session}
                view={@view}
                focus={@focus}
                logged={@logged_today}
                open_set={@open_set}
                draft={@draft}
                gym={@gym}
                jump={length(@session.modules) > 1}
              />

              <div :if={!@is_admin} class="day-content vault-day markdown-body">
                {raw(@day.html)}

                <%!-- Rotating days (Friday's swim-or-run, Saturday's four-week
                  cycle) render each option as its own dropdown, with the one
                  in rotation open. Which one is live comes from
                  Web.Fitness.Rotation off the ISO week. --%>
                <div :if={@day.options != []} class="option-list">
                  <details
                    :for={option <- @day.options}
                    class="option-details"
                    data-option={"#{day_key(@day.slug)}_#{option.key}"}
                    open={option.active?}
                  >
                    <summary class="option-summary">
                      <span class="option-label">{option.label}</span>
                      <span :if={option.active?} class="option-badge">this week</span>
                      <.icon name="hero-chevron-down" class="summary-icon" />
                    </summary>
                    <div class="option-content vault-day markdown-body">
                      {raw(option.html)}
                    </div>
                  </details>
                </div>
              </div>
            </article>

            <%!-- The admin's own record of the day: never rendered for a
                  visitor, who is sent an empty list. --%>
            <.logged_today :if={@is_admin and @logged_today != []} logged={@logged_today} />

            <details
              :if={@other_sessions != [] or @extra_modules != []}
              class="day-addons"
              id="day-more"
            >
              <summary class="day-page-section">More</summary>
              <section :if={@other_sessions != []} id="other-sessions">
                <h2 class="day-more-title">Other sessions</h2>
                <ul class="day-other-sessions">
                  <li :for={session <- @other_sessions}>
                    <.link navigate={~p"/fitness/session/#{session.slug}"}>{session.title}</.link>
                  </li>
                </ul>
              </section>
              <section :if={@extra_modules != []} id="day-addons">
                <h2 class="day-more-title">Extras</h2>
                <div class="regimen-list">
                  <%= for day <- @extra_modules do %>
                    <details class="day-details" data-day={day.slug}>
                      <summary class="day-summary">
                        <span class="day-title">{day.title}</span>
                        <.icon name="hero-chevron-down" class="summary-icon" />
                      </summary>
                      <div class="day-content vault-day markdown-body" style="padding: 1rem 0;">
                        {raw(day.html)}
                      </div>
                    </details>
                  <% end %>
                </div>
              </section>
              <p :if={@is_admin and @extra_modules != []} class="day-page-reset">
                <button class="reset-btn" id="reset-ticks" type="button">Clear my ticks</button>
              </p>
            </details>
            <p :if={!@is_admin} class="day-page-reset">
              <button class="reset-btn" id="reset-ticks" type="button">Clear my ticks</button>
            </p>
          </div>
          <nav :if={@strip != []} class="week-rail" aria-label="The week">
            <.link
              :for={day <- @strip}
              navigate={day_path(day.slug)}
              class={["week-rail-link", day.slug == Web.Clock.today_slug() && "is-today"]}
              aria-current={day.slug == @day.slug && "page"}
            >
              <span class="week-rail-day">{day.name}</span>
              <span class="week-rail-what">{day.title}</span>
            </.link>
          </nav>
        </div>
      </div>

      <script :type={Phoenix.LiveView.ColocatedHook} name=".ViewMemory">
        const KEY = "fitness:view"
        const read = () => { try { return localStorage.getItem(KEY) } catch (_) { return null } }
        const keep = (view) => { try { localStorage.setItem(KEY, view) } catch (_) {} }
        export default {
          mounted() {
            const last = read()
            if (this.el.dataset.asked === "false" && last && last !== this.el.dataset.view) {
              this.pushEvent("set_view", { view: last })
            } else {
              keep(this.el.dataset.view)
            }
          },
          updated() { keep(this.el.dataset.view) }
        }
      </script>

      <%!-- The rest after a logged set, for the admin. The server says when a
            rest starts; the hook keeps its end time in this browser, so the
            count is right after a locked screen, a reload or another day's
            page. At zero it beeps (and buzzes where the phone can). --%>
      <div
        :if={@is_admin}
        id="rest-bar"
        class="rest-timer"
        phx-hook=".RestBar"
        phx-update="ignore"
        role="timer"
        hidden
      >
        <span class="rest-timer-label" data-label>Rest</span>
        <span class="rest-timer-left" data-left>0:00</span>
        <button type="button" class="rest-timer-skip" data-more>+30 s</button>
        <button type="button" class="rest-timer-skip" data-skip>Skip</button>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".RestBar">
        const KEY = "fitness:rest"
        export default {
          mounted() {
            this.left = this.el.querySelector("[data-left]")
            this.label = this.el.querySelector("[data-label]")
            this.el.querySelector("[data-skip]").addEventListener("click", () => this.stop())
            this.el.querySelector("[data-more]").addEventListener("click", () => {
              const s = this.load()
              if (s) { s.ends = Math.max(s.ends, Date.now()) + 30000; s.rang = false; this.save(s); this.tick() }
            })
            // Any tap may start the sound, so the beep at zero is allowed.
            this.unlock = () => {
              try {
                const AC = window.AudioContext || window.webkitAudioContext
                if (AC && !this.audio) this.audio = new AC()
                if (this.audio && this.audio.state === "suspended") this.audio.resume()
              } catch (_) {}
            }
            document.addEventListener("pointerdown", this.unlock, { passive: true })
            this.handleEvent("rest:start", ({ seconds, label }) => {
              this.save({ ends: Date.now() + seconds * 1000, label, rang: false })
              this.tick()
            })
            this.onShow = () => this.tick()
            document.addEventListener("visibilitychange", this.onShow)
            this.timer = setInterval(() => this.tick(), 250)
            this.tick()
          },
          load() { try { return JSON.parse(localStorage.getItem(KEY) || "null") } catch (_) { return null } },
          save(s) { try { localStorage.setItem(KEY, JSON.stringify(s)) } catch (_) {} },
          stop() { try { localStorage.removeItem(KEY) } catch (_) {} ; this.el.hidden = true },
          tick() {
            const s = this.load()
            if (!s) { this.el.hidden = true; return }
            const left = Math.ceil((s.ends - Date.now()) / 1000)
            if (left < -30) return this.stop()
            this.el.hidden = false
            this.label.textContent = s.label ? `Rest · ${s.label}` : "Rest"
            if (left > 0) {
              this.el.classList.remove("is-up")
              this.left.textContent = `${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}`
              window.dispatchEvent(new Event("fitness:active"))
            } else {
              this.el.classList.add("is-up")
              this.left.textContent = "Go"
              if (!s.rang) { s.rang = true; this.save(s); this.ring() }
            }
          },
          ring() {
            try { navigator.vibrate && navigator.vibrate([200, 100, 200]) } catch (_) {}
            try {
              if (!this.audio) return
              const now = this.audio.currentTime
              for (const at of [0, 0.25]) {
                const o = this.audio.createOscillator(), g = this.audio.createGain()
                o.frequency.value = 880
                g.gain.setValueAtTime(0.0001, now + at)
                g.gain.exponentialRampToValueAtTime(0.4, now + at + 0.02)
                g.gain.exponentialRampToValueAtTime(0.0001, now + at + 0.18)
                o.connect(g).connect(this.audio.destination)
                o.start(now + at); o.stop(now + at + 0.2)
              }
            } catch (_) {}
          },
          destroyed() {
            clearInterval(this.timer)
            document.removeEventListener("pointerdown", this.unlock)
            document.removeEventListener("visibilitychange", this.onShow)
          }
        }
      </script>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".Circuit">
        // A circuit run on the clock. "A round every 5 minutes" counts the
        // rounds off the clock; "2 minutes between rounds" waits for Round done
        // and counts the rest down. Each change of round buzzes and beeps.
        // Finish sends the rounds and the time, logged as one entry. The run
        // is kept in this browser, so a reload or a locked phone loses nothing.
        export default {
          mounted() {
            const d = this.el.dataset
            this.rounds = Number(d.rounds)
            this.every = Number(d.every) * 1000
            this.rest = Number(d.rest) * 1000
            this.key = `circuit:${d.day}:${d.slug}`
            this.clock = this.el.querySelector("[data-clock]")
            this.cue = this.el.querySelector("[data-cue]")
            this.startBtn = this.el.querySelector("[data-start]")
            this.roundBtn = this.el.querySelector("[data-round]")
            this.finishBtn = this.el.querySelector("[data-finish]")
            try { this.state = JSON.parse(localStorage.getItem(this.key) || "null") } catch (_) { this.state = null }

            this.startBtn.addEventListener("click", () => {
              this.unlockSound()
              this.state = { start: Date.now(), done: 0, restUntil: 0, cued: 1 }
              this.save()
              this.run()
            })
            this.roundBtn.addEventListener("click", () => this.roundDone())
            this.finishBtn.addEventListener("click", () => this.finish())
            if (this.state) this.run()
          },

          save() {
            try { localStorage.setItem(this.key, JSON.stringify(this.state)) } catch (_) {}
          },

          run() {
            this.startBtn.hidden = true
            this.finishBtn.hidden = false
            this.roundBtn.hidden = this.every > 0
            clearInterval(this.timer)
            this.timer = setInterval(() => this.tick(), 250)
            this.tick()
          },

          tick() {
            const s = this.state
            if (!s) return
            const now = Date.now()
            const elapsed = now - s.start
            this.clock.textContent = this.fmt(elapsed)
            window.dispatchEvent(new Event("fitness:active"))

            if (this.every > 0) {
              const total = this.every * this.rounds
              const round = Math.min(Math.floor(elapsed / this.every) + 1, this.rounds)
              if (round > s.cued) { s.cued = round; this.save(); this.buzz() }
              if (elapsed >= total) {
                if (!s.over) { s.over = true; this.save(); this.buzz() }
                this.cue.textContent = `All ${this.rounds} rounds done: finish and log`
              } else {
                const left = this.every - (elapsed % this.every)
                const next = round < this.rounds ? `next round in ${this.fmt(left)}` : `ends in ${this.fmt(left)}`
                this.cue.textContent = `Round ${round} of ${this.rounds} · ${next}`
              }
            } else if (s.restUntil > now) {
              this.cue.textContent = `Rest ${this.fmt(s.restUntil - now)}, then round ${s.done + 1} of ${this.rounds}`
            } else {
              if (s.restUntil && !s.restCued) { s.restCued = true; this.save(); this.buzz() }
              this.cue.textContent = `Round ${s.done + 1} of ${this.rounds}`
            }
          },

          roundDone() {
            const s = this.state
            if (!s) return
            s.done += 1
            if (s.done >= this.rounds) return this.finish()
            s.restUntil = Date.now() + this.rest
            s.restCued = this.rest === 0
            this.save()
            this.tick()
          },

          finish() {
            const s = this.state
            if (!s) return
            const elapsed = Date.now() - s.start
            const rounds = this.every > 0
              ? Math.min(Math.floor(elapsed / this.every) + 1, this.rounds)
              : Math.min(s.restUntil > Date.now() ? s.done : s.done + 1, this.rounds)
            this.pushEvent("circuit_done", {
              slug: this.el.dataset.slug,
              rounds: Math.max(rounds, 1),
              seconds: Math.round(elapsed / 1000)
            })
            clearInterval(this.timer)
            try { localStorage.removeItem(this.key) } catch (_) {}
            this.state = null
            this.cue.textContent = `Logged ${Math.max(rounds, 1)} rounds in ${this.fmt(elapsed)}`
            this.startBtn.textContent = "Start again"
            this.startBtn.hidden = false
            this.roundBtn.hidden = true
            this.finishBtn.hidden = true
          },

          fmt(ms) {
            const t = Math.max(0, Math.round(ms / 1000))
            return `${Math.floor(t / 60)}:${String(t % 60).padStart(2, "0")}`
          },

          // A phone that will not vibrate (an iPhone) still beeps; the sound
          // is allowed because Start was a tap.
          unlockSound() {
            try {
              this.audio = this.audio || new (window.AudioContext || window.webkitAudioContext)()
              this.audio.resume()
            } catch (_) {}
          },

          buzz() {
            try { navigator.vibrate && navigator.vibrate([200, 100, 200]) } catch (_) {}
            try {
              if (!this.audio) return
              const tone = this.audio.createOscillator()
              const gain = this.audio.createGain()
              tone.frequency.value = 880
              gain.gain.value = 0.2
              tone.connect(gain).connect(this.audio.destination)
              tone.start()
              tone.stop(this.audio.currentTime + 0.25)
            } catch (_) {}
          },

          destroyed() {
            clearInterval(this.timer)
          }
        }
      </script>

      <SessionView.figure_sheet :if={@figure} figure={@figure} />
      <SessionView.summary :if={@summary} summary={@summary} />

      <%= if @logging do %>
        <%!-- The form closes on Cancel, Save or Escape only: a stray tap
              outside it (easy on a phone mid-set) must not lose what was
              typed. --%>
        <div class="log-modal-backdrop" phx-window-keydown="log_key">
          <div
            class="log-modal"
            role="dialog"
            aria-label={"Log #{@logging.name}"}
          >
            <h3>{if @logging[:editing], do: "Edit", else: "Log"}: {@logging.name}</h3>
            <p :if={@logging.plan.prescription.text != ""} class="log-modal-plan">
              Plan: {@logging.plan.prescription.text}
            </p>
            <p :if={@logging.last} class="log-modal-last">
              Last time, {Calendar.strftime(@logging.last.date, "%-d %b")}: {log_line(@logging.last)}
            </p>
            <p :if={@logging.plan.target} class="log-modal-target" id="log-target">
              Target: {Progression.target_line(@logging.plan.target)}
            </p>
            <p :if={@logging.plan.guard} class="log-modal-guard" id="log-guard">
              {@logging.plan.guard}<span :if={@logging.plan.instead}>. Instead: {@logging.plan.instead}</span>
            </p>
            <button
              :if={!@logging[:editing] and elem(@logging.plan.verdict, 0) != :stop}
              type="button"
              class="log-planned-btn"
              id="log-planned"
              phx-click="log_planned"
              phx-value-slug={@logging.slug}
              phx-disable-with="Logging…"
            >
              Done as planned
            </button>
            <form phx-submit="save_log" id="log-form">
              <.log_fields plan={@logging.plan} editing={@logging[:editing]} />
              <details
                :if={@logging.plan.prescription.kind not in [:swim, :trial, :laps, :timed]}
                class="log-modal-more"
                open={Enum.any?(~w(distance time result), &written(@logging[:editing], &1))}
              >
                <summary>Something else</summary>
                <label>
                  Distance
                  <input
                    type="text"
                    name="log[distance]"
                    placeholder="e.g. 2 miles"
                    value={written(@logging[:editing], "distance")}
                  />
                </label>
                <label>
                  Time
                  <input
                    type="text"
                    name="log[time]"
                    placeholder="e.g. 8:26 pace"
                    value={written(@logging[:editing], "time")}
                  />
                </label>
                <label>
                  Result
                  <input
                    type="text"
                    name="log[result]"
                    placeholder="e.g. 30 inches"
                    value={written(@logging[:editing], "result")}
                  />
                </label>
              </details>
              <label>
                Note
                <input
                  type="text"
                  name="log[note]"
                  placeholder="optional"
                  value={@logging[:editing] && @logging.editing.note}
                />
              </label>
              <label>
                Day
                <input
                  type="date"
                  name="log[date]"
                  id="log-date"
                  value={Date.to_iso8601((@logging[:editing] && @logging.editing.date) || @log_today)}
                  max={Date.to_iso8601(@log_today)}
                />
              </label>
              <div class="log-modal-actions">
                <button type="button" class="reset-btn" phx-click="close_log">Cancel</button>
                <button type="submit" class="log-save-btn" phx-disable-with="Saving…">Save</button>
              </div>
            </form>
          </div>
        </div>
      <% end %>
    </div>
    """
  end
end
