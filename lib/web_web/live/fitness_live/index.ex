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
  2. **Logging** (`handle_event/3`): opening, filling, saving and removing a
     log entry. Admin only; each event checks.
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
  alias Web.Fitness.{Block, Checks, Coach, Guardrails, Prescription, Progression, Vault}

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
    save(socket, slug, log_metrics(params), blank_to_nil(params["note"]))
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
      save(socket, slug, planned_metrics(plan), nil)
    else
      :error ->
        {:noreply, put_flash(socket, :error, "There is no exercise by that name in the wiki.")}
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

  defp save(socket, slug, metrics, note) do
    with {:ok, exercise} <- Fitness.loggable_exercise(slug),
         true <- map_size(metrics) > 0 do
      attrs = %{
        exercise_id: exercise.id,
        # The day it is here, not in Greenwich: an evening session was being
        # filed under tomorrow.
        date: Web.Clock.local_today(),
        metrics: metrics,
        note: note
      }

      case Fitness.create_exercise_log(attrs) do
        {:ok, log} ->
          {:noreply,
           socket
           |> put_flash(:info, "Logged #{exercise.name}: #{Fitness.entry_line(log)}.")
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

  # ── Targets: what the plan and the block ask for ──────────────────────────

  # Every exercise on the day as the admin sees it (Web.Fitness.Coach): the
  # line under it, its guardrail, its target and what its form starts from;
  # and the day's check-in standing beside the block's week. Nothing for a
  # visitor.
  defp assign_coach(%{assigns: %{is_admin: true, day: day, block: block}} = socket) do
    today = Web.Clock.local_today()

    standing =
      Fitness.recent_checkins(today)
      |> Guardrails.today(today, Checks.all())
      |> Enum.map_join(" · ", fn {label, answer, _level} -> "#{label}: #{answer}" end)

    assign(socket, coach: Coach.day(day.slug, today, block), standing: blank_to_nil(standing))
  end

  defp assign_coach(socket), do: assign(socket, coach: %{}, standing: nil)

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
          ~s(<button type="button" class="log-quick" phx-click="log_planned" phx-value-slug="#{plan.slug}" title="Log the planned set as done">Done</button>)
      ]
      |> Enum.filter(& &1)

    if parts == [], do: "", else: ~s(<span class="log-notes">#{Enum.join(parts)}</span>)
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

  # The form's fields as the `metrics` map the CSV export reads: strings
  # like "35 lbs", "3", "45 sec", "40 m", "20 in". A typed weight wins over
  # the stepped one; a field left at its blank is no value.
  defp log_metrics(params) do
    weight =
      case {blank_to_nil(params["weight_other"]), blank_to_nil(params["weight"])} do
        {typed, _} when is_binary(typed) -> String.trim(typed)
        {nil, "0"} -> nil
        {nil, picked} when is_binary(picked) -> "#{picked} lbs"
        _ -> nil
      end

    %{}
    |> put_metric("weight", weight)
    |> put_metric("sets", params["sets"])
    |> put_metric("reps", params["reps"])
    |> put_metric("rpe", params["rpe"])
    |> put_metric("time", params["seconds"] |> blank_to_nil() |> suffix(" sec") || params["time"])
    |> put_metric(
      "distance",
      params["metres"] |> blank_to_nil() |> suffix(" m") || params["distance"]
    )
    |> put_metric(
      "result",
      params["height"] |> blank_to_nil() |> suffix(" in") || params["result"]
    )
  end

  defp suffix(nil, _unit), do: nil
  defp suffix(value, unit), do: value <> unit

  defp put_metric(map, _key, nil), do: map
  defp put_metric(map, _key, ""), do: map
  defp put_metric(map, key, value), do: Map.put(map, key, String.trim(value))

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(v), do: v

  # The log form's fields, fitted to the exercise (`Prescription` kinds):
  # dropdowns that start at the target, else the last entry, else the plan,
  # so logging the usual is a Save and a change is one pick.
  attr :plan, :map, required: true

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
      Another weight <input type="text" name="log[weight_other]" placeholder="e.g. 47.5 lbs, 20 kg" />
    </label>
    """
  end

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
                {raw(annotate(@day.html, @coach))}

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
                      {raw(annotate(option.html, @coach))}
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
            <h3>Log: {@logging.name}</h3>
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
              :if={elem(@logging.plan.verdict, 0) != :stop}
              type="button"
              class="log-planned-btn"
              id="log-planned"
              phx-click="log_planned"
              phx-value-slug={@logging.slug}
            >
              Done as planned
            </button>
            <form phx-submit="save_log" id="log-form">
              <.log_fields plan={@logging.plan} />
              <details class="log-modal-more">
                <summary>Something else</summary>
                <label>
                  Distance <input type="text" name="log[distance]" placeholder="e.g. 2 miles" />
                </label>
                <label>
                  Time <input type="text" name="log[time]" placeholder="e.g. 8:26 pace" />
                </label>
                <label>
                  Result <input type="text" name="log[result]" placeholder="e.g. 30 inches" />
                </label>
              </details>
              <label>
                Note <input type="text" name="log[note]" placeholder="optional" />
              </label>
              <div class="log-modal-actions">
                <button type="button" class="reset-btn" phx-click="close_log">Cancel</button>
                <button type="submit" class="log-save-btn">Save</button>
              </div>
            </form>
          </div>
        </div>
      <% end %>
    </div>

    <style>
      .regimen-list { display: flex; flex-direction: column; gap: 1rem; }
      .day-details {
        background: rgba(23, 20, 15, 0.03);
        border: 1px solid rgba(23, 20, 15, 0.1);
        border-radius: 8px;
        overflow: hidden;
      }
      .day-summary {
        padding: 1.25rem 1.5rem;
        cursor: pointer;
        list-style: none; /* Hide default arrow */
        display: flex;
        align-items: center;
        gap: 1rem;
        background: rgba(23, 20, 15, 0.02);
        transition: background 0.2s;
      }
      .day-summary::-webkit-details-marker { display: none; }
      .day-summary:hover { background: rgba(194, 69, 29, 0.1); }
      .day-details[open] .day-summary { border-bottom: 1px solid rgba(23, 20, 15, 0.1); background: rgba(23, 20, 15, 0.05); }

      .day-title { font-size: 1.3rem; font-weight: bold; color: var(--theme-color); font-family: var(--font-heading); text-transform: uppercase; letter-spacing: 1px; min-width: 150px;}
      .day-desc { color: var(--ink-3); font-style: italic; font-size: 0.95rem; flex: 1; }
      .summary-icon { color: var(--ink-3); transition: transform 0.3s; font-size: 1.1rem; width: 1.1rem; height: 1.1rem; }
      .day-details[open] .summary-icon { transform: rotate(180deg); color: var(--ink); }

      .reset-btn { background: transparent; border: 1px solid var(--rule); color: var(--ink-3); padding: 0.4rem 0.8rem; cursor: pointer; border-radius: 4px; font-size: 0.85rem; text-transform: uppercase; letter-spacing: 1px; transition: 0.2s;}
      .reset-btn:hover { border-color: var(--accent-color); color: var(--accent-color); background: rgba(194, 69, 29, 0.1); }

      /* Vault markdown day rendering */
      .vault-day h2 { color: var(--theme-color); font-size: 1.05rem; text-transform: uppercase; letter-spacing: 1px; margin-top: 2rem; margin-bottom: 0.5rem; padding: 0.6rem 1rem; background: rgba(194, 69, 29, 0.08); border-left: 3px solid var(--theme-color); border-radius: 4px; }
      .vault-day ul { list-style: none; padding: 0 1rem; margin: 0.5rem 0 1.5rem 0; }
      .vault-day li { padding: 0.35rem 0; display: flex; align-items: flex-start; gap: 0.8rem; color: var(--ink-2); font-size: 0.95rem; line-height: 1.5; }
      .vault-day li p { margin: 0; padding: 0; color: inherit; display: inline; }
      .vault-day li input[type="checkbox"] { width: 18px; height: 18px; accent-color: var(--theme-color); cursor: pointer; flex-shrink: 0; margin-top: 0.15rem; background: transparent; border: 1px solid var(--rule); }
      .vault-day blockquote { border-left: 3px solid #60a5fa; margin: 1rem 1rem 1.5rem 1rem; color: #93c5fd; font-size: 0.9rem; background: rgba(96, 165, 250, 0.08); padding: 0.75rem 1rem; border-radius: 0 4px 4px 0; }
      .vault-day blockquote p { margin: 0; padding: 0; color: inherit; }
      .vault-day em { color: #9ca3af; font-style: italic; }
      .vault-day p { color: #9ca3af; margin: 0.5rem 1rem 0.5rem 1rem; padding: 0; font-size: 0.95rem; line-height: 1.5; }

      /* Inline "Log" trigger stitched onto loggable checklist lines — logging
         is an admin-only write, same as every other mutation on this site,
         so the trigger only renders for the admin session. */
      .log-trigger { display: none; }
      .is-admin .log-trigger { display: inline-block; background: transparent; border: 1px solid rgba(23, 20, 15, 0.15); color: var(--ink-3); padding: 0.1rem 0.5rem; margin-left: 0.5rem; border-radius: 4px; font-size: 0.75rem; text-transform: uppercase; letter-spacing: 0.5px; cursor: pointer; flex-shrink: 0; }
      .is-admin .log-trigger:hover { border-color: var(--theme-color); color: var(--theme-color); background: rgba(194, 69, 29, 0.1); }

      /* Log-entry modal */
      .log-modal-backdrop { position: fixed; inset: 0; background: rgba(0,0,0,0.6); display: flex; align-items: center; justify-content: center; z-index: 10001; }
      .log-modal-last { margin: -0.5rem 0 1rem; color: var(--ink-3); font-size: 0.85rem; }
      .day-logged-list { list-style: none; margin: 0 0 1.5rem; padding: 0; }
      .day-logged-list li { display: flex; flex-wrap: wrap; align-items: baseline; gap: 0.4rem 1rem; padding: 0.6rem 0; border-bottom: 1px solid var(--rule); }
      .day-logged-name { color: var(--ink); font-weight: 600; }
      .day-logged-values { flex: 1; color: var(--ink-2); }
      .log-modal { background: var(--paper-sunk); border: 1px solid rgba(23, 20, 15, 0.15); border-radius: 8px; padding: 1.5rem; width: 90%; max-width: 360px; }
      .log-modal h3 { color: var(--theme-color); font-family: var(--font-heading); text-transform: uppercase; letter-spacing: 1px; font-size: 1.1rem; margin: 0 0 1rem 0; }
      .log-modal label { display: block; color: var(--ink-3); font-size: 0.85rem; margin-bottom: 0.75rem; }
      .log-modal input { display: block; width: 100%; margin-top: 0.25rem; padding: 0.5rem; background: rgba(23, 20, 15, 0.05); border: 1px solid var(--rule); border-radius: 4px; color: var(--ink-2); font-size: 0.9rem; }
      .log-modal-actions { display: flex; justify-content: flex-end; gap: 0.75rem; margin-top: 1rem; }
      .log-modal-target { margin: -0.5rem 0 1rem; color: var(--ink); font-family: var(--font-data); font-size: 0.85rem; }
      .log-notes { display: flex; flex-wrap: wrap; align-items: center; gap: 0.25rem 0.75rem; margin: 0.2rem 0 0.1rem; font-size: 0.8rem; }
      .log-hint { font-family: var(--font-data); color: var(--ink-2); }
      .log-guard { color: var(--ink); font-weight: 600; }
      .log-guard--stop { color: var(--color-orange); }
      .log-quick { padding: 0.15rem 0.6rem; font-family: var(--font-ui); font-size: 0.75rem; color: var(--accent-ink, var(--ink)); background: none; border: 1px solid currentColor; border-radius: 3px; cursor: pointer; }
      .log-modal-plan { margin: -0.5rem 0 0.75rem; color: var(--ink-2); font-size: 0.85rem; }
      .log-modal select { display: block; width: 100%; margin-top: 0.25rem; padding: 0.5rem; background: rgba(23, 20, 15, 0.05); border: 1px solid var(--rule); border-radius: 4px; color: var(--ink-2); font-size: 0.9rem; }
      .log-modal-row { display: grid; grid-template-columns: repeat(auto-fit, minmax(5.5rem, 1fr)); gap: 0.75rem; }
      .log-planned-btn { display: block; width: 100%; margin: 0 0 1rem; padding: 0.75rem; font-family: var(--font-ui); font-weight: 600; color: var(--paper); background: var(--accent-ink, var(--ink)); border: 0; border-radius: 4px; cursor: pointer; }
      .log-modal-more { margin: 0 0 0.75rem; font-size: 0.85rem; color: var(--ink-3); }
      .log-modal-more summary { cursor: pointer; margin-bottom: 0.5rem; }
      .log-modal-guard { margin: -0.5rem 0 1rem; color: var(--accent-ink, var(--ink)); font-size: 0.85rem; }
      .log-save-btn { background: var(--theme-color); border: none; color: var(--paper); padding: 0.4rem 1rem; border-radius: 4px; font-size: 0.85rem; text-transform: uppercase; letter-spacing: 1px; cursor: pointer; font-weight: bold; }
    </style>
    """
  end
end
