defmodule WebWeb.FitnessLive.Index do
  @moduledoc """
  The training plan, one day to a page (`/fitness` is today by the Pacific
  clock; `/fitness/day/thursday` is Thursday, whatever day it is). The day's
  exercises are read from the vault (`content/fitness/weekly/<day>.md` and the
  modules it lists) by `Web.Fitness.Vault`, and shown as a checklist whose
  ticks the browser remembers (the `GymRoutine` hook,
  `assets/js/gym_routine.js`).

  **For the admin, the page is also the training log.** Each exercise gets a
  Log button. During a training block the line under it says what today's
  target is and why (`Web.Fitness.Coach`), and the log form starts from the
  plan's own numbers. Visitors see only the plan.

  The days link to each other with `navigate`, never `patch` (the comment
  above `mount/3` explains why).

  ## How this file is laid out

  1. **Opening a day** (`mount/3`, `mount_day/4`, `handle_params/3`): which
     day, its plan, and its strip of days.
  2. **Logging** (`handle_event/3`): opening, filling, saving, editing and
     removing a log entry. Admin only; each event checks. An entry is filed
     under today unless the form names an earlier day.
  3. **Saving an entry** (`save/4`).
  4. **Targets** (`assign_coach/1` to `format_n/1`): what the plan's own
     lines and the training block ask of each exercise today.
  5. **What a logged entry says** (`log_line/1` to `blank_to_nil/1`).
  6. **The log form's fields** (`log_fields/1` to `num/1`): which fields,
     for which kind of exercise.
  7. **The page itself** (`render/1`).
  """

  use WebWeb, :live_view

  alias Web.Fitness
  alias Web.Fitness.{Block, Checks, Coach, Entry, Guardrails, Prescription, Progression, Vault}

  @weekdays ~w[monday tuesday wednesday thursday friday saturday sunday]
  @fuelling "nutrition-module"

  # ── Opening a day ─────────────────────────────────────────────────────────

  # One day to a page. `/fitness` is always today, by the Pacific clock, so
  # it moves on by itself; `/fitness/day/thursday` is Thursday whatever the
  # day, so the day being looked at is in the address and a reload keeps it.
  # The days link to each other with `navigate`, not `patch`: the checklist
  # is raw HTML whose ticks GymRoutine restores on mount, and a patch would
  # carry one day's ticked boxes over onto the next day's list.
  @impl true
  def mount(params, session, socket) do
    today = Web.Clock.today_slug()

    case params["day"] || today do
      slug when slug in @weekdays ->
        {:ok, mount_day(socket, slug, today, session["admin_user"] == true)}

      _ ->
        {:ok, push_navigate(socket, to: ~p"/fitness")}
    end
  end

  defp mount_day(socket, slug, today, is_admin) do
    listed = Vault.list_days()

    week =
      case Web.Fitness.Week.load() do
        {:ok, week} -> week
        :error -> nil
      end

    socket
    |> assign(:is_admin, is_admin)
    |> assign(:week, week)
    |> assign(:today_slug, today)
    |> assign(:weekdays, strip(week, listed))
    |> assign(
      :day,
      listed
      |> Enum.find(%{slug: slug, title: String.capitalize(slug)}, &(&1.slug == slug))
      |> with_html()
    )
    |> assign(:blocks, blocks(week, slug))
    |> assign(:fuelling, with_html(Enum.find(listed, &(&1.slug == @fuelling))))
    |> assign(
      :extra_modules,
      listed |> Enum.reject(&(&1.slug in [@fuelling | @weekdays])) |> Enum.map(&with_html/1)
    )
    # The block's week, the check-ins and every number are the admin's: a
    # visitor's page says nothing of training state (see the privacy tests).
    |> assign(:block, if(is_admin, do: Block.current(Web.Clock.local_today())))
    |> assign(:logging, nil)
    |> assign(:log_today, Web.Clock.local_today())
    |> assign_coach()
    |> assign_logged_today()
    |> assign(:page_title, "#{String.capitalize(slug)} · Fitness & Sport")
  end

  # A day's checklist, plus any rotating options. Days that do the same thing
  # every week come back with `options: []`, so the template handles both
  # shapes the same way.
  defp with_html(nil), do: nil

  defp with_html(day) do
    case Vault.get_day_with_options(day.slug) do
      {:ok, %{html: html, options: options}} -> Map.merge(day, %{html: html, options: options})
      _ -> Map.merge(day, %{html: "", options: []})
    end
  end

  # The day's line in week.md: what it holds, in order.
  defp blocks(nil, _slug), do: []

  defp blocks(week, slug) do
    case Enum.find(week.days, &(&1.slug == slug)) do
      nil -> []
      day -> day.blocks
    end
  end

  # The days in the order week.md lists them, so the strip and The Week under
  # it read the same way.
  defp strip(week, listed) do
    in_week = if week, do: for(day <- week.days, day.slug in @weekdays, do: day.slug), else: []
    order = if Enum.sort(in_week) == Enum.sort(@weekdays), do: in_week, else: @weekdays

    for slug <- order do
      theme = Enum.find_value(listed, &(&1.slug == slug && &1[:theme]))
      %{slug: slug, name: String.capitalize(slug), theme: theme}
    end
  end

  defp day_path(slug, today) when slug == today, do: ~p"/fitness"
  defp day_path(slug, _today), do: ~p"/fitness/day/#{slug}"

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  # ── Logging: the form's buttons ───────────────────────────────────────────

  # Fired by the inline "Log" button that Web.Fitness.Vault stitches onto any
  # checkbox line referencing a `[[slug]]` exercise (see
  # Vault.render_markdown/1's ⟦LOG:slug⟧ marker). Any exercise the wiki has
  # can be logged (`Fitness.loggable_exercise/1`); the form opens showing the
  # last entry for it, which is the number to beat.
  @impl true
  def handle_event("open_log", _params, %{assigns: %{is_admin: false}} = socket) do
    {:noreply, socket}
  end

  def handle_event("open_log", %{"slug" => slug}, socket) do
    case Fitness.loggable_exercise(slug) do
      {:ok, exercise} ->
        {:noreply,
         assign(socket, :logging, %{
           slug: slug,
           name: exercise.name,
           last: Fitness.last_exercise_log(exercise.id),
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

  def handle_event("save_log", _params, %{assigns: %{is_admin: false}} = socket) do
    {:noreply, socket}
  end

  def handle_event("save_log", %{"log" => params}, %{assigns: %{logging: %{slug: slug}}} = socket) do
    save(socket, slug, Entry.metrics(params), blank_to_nil(params["note"]), Entry.date(params["date"]))
  end

  def handle_event("save_log", _params, socket), do: {:noreply, socket}

  # One tap: the set the plan (or the target) asks for, logged as done. From
  # the "Done" button under a line, or the form's "Done as planned".
  def handle_event("log_planned", _params, %{assigns: %{is_admin: false}} = socket) do
    {:noreply, socket}
  end

  def handle_event("log_planned", %{"slug" => slug}, socket) do
    with {:ok, exercise} <- Fitness.loggable_exercise(slug) do
      plan = plan_for(socket, slug, exercise.name)
      save(socket, slug, planned_metrics(plan), nil, Web.Clock.local_today())
    else
      :error ->
        {:noreply, put_flash(socket, :error, "There is no exercise by that name in the wiki.")}
    end
  end

  # Today's check-in, from the day page itself: one tap per check, saved over
  # whatever today already had (the admin's /admin/fitness?tab=checkin is the
  # same record, with its history and any other day).
  def handle_event("save_checkin", _params, %{assigns: %{is_admin: false}} = socket) do
    {:noreply, socket}
  end

  def handle_event("save_checkin", %{"checkin" => params}, socket) do
    attrs = %{
      "date" => Web.Clock.local_today(),
      "answers" => Map.get(params, "answers", %{}),
      "note" => blank_to_nil(params["note"])
    }

    case Fitness.save_checkin(attrs, socket.assigns.checks) do
      {:ok, _} ->
        {:noreply, socket |> put_flash(:info, "Check-in saved.") |> assign_coach()}

      {:error, changeset} ->
        message =
          changeset.errors
          |> Enum.map_join("; ", fn {_field, error} -> WebWeb.CoreComponents.translate_error(error) end)

        {:noreply, put_flash(socket, :error, "Check-in not saved: #{message}.")}
    end
  end

  # An entry already made opens the same form, its fields at what it says.
  def handle_event("edit_log", _params, %{assigns: %{is_admin: false}} = socket) do
    {:noreply, socket}
  end

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

  def handle_event("delete_log", _params, %{assigns: %{is_admin: false}} = socket) do
    {:noreply, socket}
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
           |> assign_logged_today()}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Couldn't save that — try again.")}
      end
    else
      _ -> {:noreply, put_flash(socket, :error, "Enter at least one value to log.")}
    end
  end

  defp close_log(socket), do: assign(socket, :logging, nil)

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
  # line under it, its guardrail, its target and what its form starts from;
  # and the day's check-in standing beside the block's week. Nothing for a
  # visitor.
  defp assign_coach(%{assigns: %{is_admin: true, day: day, block: block}} = socket) do
    today = Web.Clock.local_today()
    recent = Fitness.recent_checkins(today)
    checks = Checks.all()

    standing =
      recent
      |> Guardrails.today(today, checks)
      |> Enum.map_join(" · ", fn {label, answer, _level} -> "#{label}: #{answer}" end)

    todays = Enum.find(recent, &(&1.date == today))

    assign(socket,
      coach: Coach.day(day.slug, today, block),
      standing: blank_to_nil(standing),
      checks: checks,
      checkin_answers: (todays && todays.answers) || %{}
    )
  end

  defp assign_coach(socket),
    do: assign(socket, coach: %{}, standing: nil, checks: [], checkin_answers: %{})

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

  # The admin's notes under each Log button in the rendered plan: the line
  # (last time, the target), the guardrail, and the one-tap Done. Escaped
  # text only; no checkbox and no `data-day`, which GymRoutine counts.
  defp annotate(html, coach) when coach == %{}, do: html

  defp annotate(html, coach) do
    Regex.replace(
      ~r{(<button type="button" class="log-trigger" phx-click="open_log" phx-value-slug="([a-z0-9-]+)">Log</button>)},
      html,
      fn whole, _button, slug ->
        case coach[slug] do
          nil -> whole
          plan -> whole <> notes(plan)
        end
      end
    )
  end

  defp notes(plan) do
    esc = &(&1 |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string())
    level = plan.verdict |> elem(0) |> to_string()

    parts =
      [
        plan.hint && ~s(<span class="log-hint">#{esc.(plan.hint)}</span>),
        plan.guard &&
          ~s(<span class="log-guard log-guard--#{level}">#{esc.(plan.guard)}#{if plan.instead, do: esc.(". Instead: " <> plan.instead), else: ""}</span>),
        elem(plan.verdict, 0) != :stop && planned_metrics(plan) != %{} &&
          ~s(<button type="button" class="log-quick" phx-click="log_planned" phx-value-slug="#{plan.slug}" phx-disable-with="Logging…" title="Log the planned set as done">Done</button>)
      ]
      |> Enum.filter(& &1)

    if parts == [], do: "", else: ~s(<span class="log-notes">#{Enum.join(parts)}</span>)
  end

  # On today's page, the admin's lines whose exercise is logged today carry
  # `data-logged` on their Log button, and GymRoutine shows their boxes
  # ticked: a log is the record, a tick only a reminder. A tick alone still
  # saves nothing, and a visitor's ticks stay in their own browser.
  defp mark_logged(html, []), do: html

  defp mark_logged(html, slugs) do
    Enum.reduce(slugs, html, fn slug, html ->
      String.replace(
        html,
        ~s(class="log-trigger" phx-click="open_log" phx-value-slug="#{slug}"),
        ~s(class="log-trigger" phx-click="open_log" phx-value-slug="#{slug}" data-logged)
      )
    end)
  end

  defp logged_slugs(logs, day_slug, today_slug) when day_slug == today_slug,
    do: logs |> Enum.map(& &1.exercise.slug) |> Enum.uniq()

  defp logged_slugs(_logs, _day_slug, _today_slug), do: []

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
    |> put_number("distance", d.metres && p.kind == :carry && "#{d.metres} m")
  end

  defp put_number(map, _key, v) when v in [nil, false, ""], do: map
  defp put_number(map, key, v), do: Map.put(map, key, to_string(v))

  defp format_n(w) when is_float(w) and w == trunc(w), do: Integer.to_string(trunc(w))
  defp format_n(w), do: to_string(w)

  # What has been logged today, for the admin only: the proof an entry went
  # in, and the place to take a wrong one back out.
  defp assign_logged_today(%{assigns: %{is_admin: true}} = socket),
    do: assign(socket, :logged_today, Fitness.exercise_logs_on(Web.Clock.local_today()))

  defp assign_logged_today(socket), do: assign(socket, :logged_today, [])

  # ── What a logged entry says ──────────────────────────────────────────────

  @doc "A log entry's values in a line (`Web.Fitness.entry_line/1`)."
  def log_line(log), do: Fitness.entry_line(log)


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
      <label>
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="blog-bento-wrapper steel fitness-landing">
      <%!-- The section's tabs lead, as they do on the wiki and Activities,
            so both are one click from the top. Then what is about to be done:
            the days, each over the one word its file gives as `theme:`, then
            the one being looked at. The week and the other modules are
            underneath it. --%>
      <WebWeb.FitnessSubnav.subnav active={:regimen} />

      <nav class="day-strip" aria-label="Days of the week">
        <.link
          :for={day <- @weekdays}
          navigate={day_path(day.slug, @today_slug)}
          class={["day-strip-link", day.slug == @today_slug && "is-today"]}
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
      >
        <div class="fitness-layout">
          <div class="fitness-main">
            <%!-- `.day-details` and `data-day` are what GymRoutine keys a
                  saved tick on (`vault_gym_<data-day>_<index>`), as they were
                  when every day shared one page. --%>
            <article class="day-details day-page" data-day={@day.slug}>
              <header class="day-page-head">
                <p class="day-page-when">
                  <%= if @day.slug == @today_slug do %>
                    Today
                  <% else %>
                    Not today
                    <.link navigate={~p"/fitness"} class="day-page-back">
                      Today is {String.capitalize(@today_slug)}
                    </.link>
                  <% end %>
                </p>
                <h1 class="day-page-title">{@day.title}</h1>
                <p :if={@block} class="day-page-block" id="block-week">
                  {@block.title} · Week {@block.week} of {@block.weeks} — {@block.phase}
                  <span :if={@standing} class="day-page-guard" id="block-guard">· {@standing}</span>
                  ·
                  <.link navigate={~p"/admin/fitness/block"} class="day-page-back">
                    Block report
                  </.link>
                </p>
                <%!-- Today's check-in, for the admin only, where the training
                      is, so a sore joint is told before the session it changes. --%>
                <details
                  :if={@is_admin and @checks != []}
                  class="day-checkin"
                  id="day-checkin"
                  open={@checkin_answers == %{}}
                >
                  <summary class="day-checkin-summary">
                    {if @checkin_answers == %{}, do: "Check in for today", else: "Today's check-in"}
                  </summary>
                  <form id="day-checkin-form" phx-submit="save_checkin" class="day-checkin-form">
                    <fieldset :for={check <- @checks} class="day-check" id={"day-check-#{check.id}"}>
                      <legend>{check.label}</legend>
                      <%= if check.kind == :state do %>
                        <div class="day-check-states">
                          <label
                            :for={state <- check.states}
                            class={["day-check-state", "day-check-state--#{Checks.level(check, state)}"]}
                          >
                            <input
                              type="radio"
                              name={"checkin[answers][#{check.id}]"}
                              value={state}
                              checked={@checkin_answers[check.id] == state}
                            />
                            <span>{state}</span>
                          </label>
                          <label class="day-check-state day-check-state--skip">
                            <input
                              type="radio"
                              name={"checkin[answers][#{check.id}]"}
                              value=""
                              checked={is_nil(@checkin_answers[check.id])}
                            />
                            <span>skip</span>
                          </label>
                        </div>
                      <% else %>
                        <input
                          type="text"
                          inputmode="decimal"
                          name={"checkin[answers][#{check.id}]"}
                          value={@checkin_answers[check.id]}
                          placeholder={check.unit}
                          class="day-check-number"
                        />
                      <% end %>
                    </fieldset>
                    <button type="submit" class="log-save-btn" phx-disable-with="Saving…">
                      Save check-in
                    </button>
                  </form>
                </details>
                <ul :if={@blocks != []} class="week-chips day-page-blocks">
                  <li
                    :for={block <- @blocks}
                    class={"week-chip week-chip--#{block.kind}"}
                    title={block.label}
                  >
                    {block.label}<span :if={@is_admin} class="week-chip-time">{Web.Fitness.Week.span(block)}</span>
                  </li>
                </ul>
              </header>

              <div class="day-content vault-day markdown-body">
                {raw(
                  @day.html
                  |> annotate(@coach)
                  |> mark_logged(logged_slugs(@logged_today, @day.slug, @today_slug))
                )}

                <%!-- Rotating days (Friday's swim-or-run, Saturday's four-week
                  cycle) render each option as its own dropdown, with the one
                  in rotation open. Which one is live comes from
                  Web.Fitness.Rotation off the ISO week. --%>
                <div :if={@day.options != []} class="option-list">
                  <details
                    :for={option <- @day.options}
                    class="option-details"
                    data-option={"#{@day.slug}_#{option.key}"}
                    open={option.active?}
                  >
                    <summary class="option-summary">
                      <span class="option-label">{option.label}</span>
                      <span :if={option.active?} class="option-badge">this week</span>
                      <.icon name="hero-chevron-down" class="summary-icon" />
                    </summary>
                    <div class="option-content vault-day markdown-body">
                      {raw(
                        option.html
                        |> annotate(@coach)
                        |> mark_logged(logged_slugs(@logged_today, @day.slug, @today_slug))
                      )}
                    </div>
                  </details>
                </div>
              </div>
            </article>

            <%!-- The admin's own record of the day: never rendered for a
                  visitor, who is sent an empty list. --%>
            <section :if={@is_admin and @logged_today != []} class="day-logged" id="logged-today">
              <h2 class="day-page-section">Logged today</h2>
              <ul class="day-logged-list">
                <li :for={log <- @logged_today} id={"logged-#{log.id}"}>
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

            <p class="day-page-reset">
              <button class="reset-btn" id="reset-week" type="button">Reset All Checkboxes</button>
            </p>

            <%= if @extra_modules != [] do %>
              <h2 class="day-page-section">Additional Modules</h2>
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
            <% end %>
          </div>

          <%!-- Fuelling is a daily reference, not the day's work, so it rides
                beside the day in a sticky rail (the /negatives roll rail's
                shape) and folds below it on narrow screens — it comes after the
                workout in the markup for exactly that reason. It stays inside
                #weekly-routine and keeps its .day-details class and data-day,
                because GymRoutine keys saved ticks on
                `vault_gym_<data-day>_<index>` scoped to this element — move it
                out or rename the scope and every saved tick silently detaches. --%>
          <aside :if={@fuelling} class="fuelling-rail" aria-label="Daily fuelling">
            <details class="day-details" data-day={@fuelling.slug} open>
              <summary class="day-summary">
                <span class="day-title">{@fuelling.title}</span>
                <.icon name="hero-chevron-down" class="summary-icon" />
              </summary>
              <div class="day-content vault-day markdown-body">
                {raw(@fuelling.html)}
              </div>
            </details>
          </aside>
        </div>
      </div>

      <%!-- The big picture, under the day. Visitors get untimed chips; the
            clock times render for the admin only. --%>
      <WebWeb.FitnessWeek.week :if={@week} week={@week} today_slug={@today_slug} timed={@is_admin} />

      <%= if @logging do %>
        <%!-- No phx-click on the backdrop: LiveView hands a click to the
              nearest ancestor that has one, so every click *inside* the form,
              on a field included, closed it. Clicking outside the form is
              phx-click-away's job, and Escape closes it too. --%>
        <div class="log-modal-backdrop" phx-window-keydown="log_key">
          <div
            class="log-modal"
            phx-click-away="close_log"
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
