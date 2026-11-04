defmodule WebWeb.FitnessLive.SessionView do
  @moduledoc """
  The admin's training day as a session, drawn from `Web.Fitness.Session`'s
  structure rather than from the plan's HTML: one station at a time (focus)
  or all of them with the finished ones folded (list).

  Every button sends the day page's own events (`set_done`, `set_open`,
  `open_log`, `log_planned`, `focus_step`, …), handled in
  `WebWeb.FitnessLive.Index`, which also checks each one is the admin's.
  """

  use WebWeb, :html

  alias Web.Fitness
  alias Web.Fitness.{Entry, Plates, Session}

  attr :session, :map, required: true
  attr :view, :string, required: true
  attr :focus, :integer, default: 0
  attr :logged, :list, required: true
  attr :open_set, :any, default: nil
  attr :draft, :map, default: %{}
  attr :gym, :map, required: true
  attr :jump, :boolean, default: false

  def session(%{view: "focus"} = assigns) do
    stations = assigns.session.stations
    i = assigns.focus |> max(0) |> min(max(length(stations) - 1, 0))
    station = Enum.at(stations, i)
    module = station && Enum.at(assigns.session.modules, station.module_index)

    assigns =
      assign(assigns,
        i: i,
        station: station,
        notes: notes(module),
        next: Enum.at(stations, i + 1),
        count: length(stations)
      )

    ~H"""
    <section id="session-focus" class="session session--focus" phx-hook=".Swipe" data-at={@i}>
      <p :if={@station == nil} class="session-empty">Nothing to log on this day.</p>
      <%!-- A page of modules done in any order: go straight to the one being done. --%>
      <nav :if={@jump and @station} class="session-jumps" aria-label="Modules">
        <button
          :for={{label, at} <- Session.jumps(@session)}
          type="button"
          class="session-jump"
          aria-current={label == module_label(@station, @session) && "true"}
          phx-click="focus_to"
          phx-value-i={at}
        >
          {label}
        </button>
      </nav>
      <div :if={@station} class="session-focus-card" id={"station-#{@i}"}>
        <p class="session-progress">
          <span>{@i + 1} of {@count}</span>
          <span :if={@station.module && @station.type != :brief} class="session-module">{@station.module}</span>
        </p>
        <ul :if={@notes != [] and @station.type != :brief} class="session-notes">
          <li :for={note <- @notes}>{Session.inline(note)}</li>
        </ul>
        <.station station={@station} logged={@logged} open_set={@open_set} draft={@draft} gym={@gym} />
      </div>
      <nav :if={@station} class="session-nav" aria-label="Exercises">
        <button
          type="button"
          class="session-nav-btn"
          phx-click="focus_step"
          phx-value-by="-1"
          disabled={@i == 0}
        >
          Back
        </button>
        <%= if @next do %>
          <button
            type="button"
            class="session-nav-btn session-nav-btn--next"
            phx-click="focus_step"
            phx-value-by="1"
          >
            Next: {label(@next)}
          </button>
        <% else %>
          <button
            type="button"
            class="session-nav-btn session-nav-btn--next"
            phx-click="finish_session"
          >
            Finish session
          </button>
        <% end %>
      </nav>
    </section>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Swipe">
      // A sideways swipe on the card moves to the next or the last exercise;
      // an up-and-down one is a scroll and is left alone.
      export default {
        // Focus opens on the card, not the top of the page; moving to another
        // station brings its top back into view. Logging a set does not.
        updated() {
          if (this.el.dataset.at !== this.at) { this.at = this.el.dataset.at; this.top() }
        },
        top() {
          const y = this.el.getBoundingClientRect().top + window.scrollY - 8
          window.scrollTo({ top: y, behavior: "smooth" })
        },
        mounted() {
          this.at = this.el.dataset.at
          requestAnimationFrame(() => this.top())
          this.el.addEventListener("touchstart", (e) => {
            const t = e.touches[0]
            this.start = { x: t.clientX, y: t.clientY, at: Date.now() }
          }, { passive: true })
          this.el.addEventListener("touchend", (e) => {
            if (!this.start) return
            const t = e.changedTouches[0]
            const dx = t.clientX - this.start.x
            const dy = t.clientY - this.start.y
            const quick = Date.now() - this.start.at < 600
            this.start = null
            if (quick && Math.abs(dx) > 70 && Math.abs(dx) > 2 * Math.abs(dy)) {
              this.pushEvent("focus_step", { by: dx < 0 ? "1" : "-1" })
            }
          }, { passive: true })
        }
      }
    </script>
    """
  end

  def session(assigns) do
    current = Session.current(assigns.session)
    next = Enum.at(assigns.session.stations, current)

    # Each module's lines with its stations put in place, so the template
    # only draws.
    modules =
      for {m, mi} <- Enum.with_index(assigns.session.modules) do
        items =
          for item <- m.items do
            if item.type in [:exercise, :superset, :circuit, :brief] do
              key = Map.take(item, [:type, :slug, :title])

              station =
                Enum.find(assigns.session.stations, fn s ->
                  s.module_index == mi and Map.take(s, [:type, :slug, :title]) == key
                end)

              {:station, station}
            else
              {item.type, item}
            end
          end

        %{title: m.title, items: items}
      end

    assigns = assign(assigns, current: current, next: next, modules: modules)

    ~H"""
    <section id="session-list" class="session session--list">
      <div :for={m <- @modules} class="session-module-block">
        <h2 :if={m.title} class="session-module-title">{m.title}</h2>
        <%= for {kind, item} <- m.items do %>
          <p :if={kind == :note} class="session-note">{Session.inline(item.text)}</p>
          <h3 :if={kind == :heading} class="session-heading">{item.text}</h3>
          <details
            :if={kind == :station and item.done?}
            class="session-done"
            id={"station-#{item.index}"}
          >
            <summary>
              <span class="session-done-mark" aria-hidden="true">✓</span>
              {label(item)}
              <span class="session-done-line">{done_line(item, @logged)}</span>
            </summary>
            <.station station={item} logged={@logged} open_set={@open_set} draft={@draft} gym={@gym} />
          </details>
          <div
            :if={kind == :station and not item.done?}
            id={"station-#{item.index}"}
            class={["session-station", item.index == @current && "is-current"]}
          >
            <.station station={item} logged={@logged} open_set={@open_set} draft={@draft} gym={@gym} />
          </div>
        <% end %>
      </div>
      <div :if={@next && !@next.done?} class="session-next-up">
        <a href={"#station-#{@current}"}>Next up: {label(@next)}</a>
      </div>
      <p class="session-finish-row">
        <button type="button" class="session-nav-btn session-nav-btn--next" phx-click="finish_session">
          Finish session
        </button>
      </p>
    </section>
    """
  end

  defp module_label(station, session) do
    Enum.find_value(Session.jumps(session), fn {label, at} ->
      first = Enum.at(session.stations, at)
      first.module_index == station.module_index && label
    end)
  end

  # The module's notes, shown above its station in focus mode: this week's
  # line, the guardrails.
  defp notes(nil), do: []
  defp notes(module), do: for(%{type: :note, text: text} <- module.items, do: text)

  @doc "What a station is called on its Next button."
  def label(%{type: :superset, title: title}), do: title
  def label(%{type: :brief, title: title}), do: title || "The ride"
  def label(%{type: :circuit, plan: %{prescription: p}}), do: p.name
  def label(%{type: :circuit, circuit: c}), do: c.name || "Circuit"
  def label(%{type: :exercise} = s), do: Session.name(s)

  defp done_line(%{type: :superset, items: items}, logged),
    do: Enum.map_join(items, " · ", &done_line(&1, logged))

  defp done_line(%{type: :brief}, _logged), do: ""

  defp done_line(%{slug: slug}, logged) do
    case Session.todays(logged, slug) do
      nil -> ""
      log -> Fitness.entry_line(log)
    end
  end

  # ── A station ─────────────────────────────────────────────────────────────

  attr :station, :map, required: true
  attr :logged, :list, required: true
  attr :open_set, :any
  attr :draft, :map, default: %{}
  attr :gym, :map, required: true

  def station(%{station: %{type: :superset}} = assigns) do
    ~H"""
    <div class="session-superset">
      <h3 class="session-superset-title">{@station.title}</h3>
      <.exercise
        :for={item <- @station.items}
        item={item}
        logged={@logged}
        open_set={@open_set}
        draft={@draft}
        gym={@gym}
      />
    </div>
    """
  end

  def station(%{station: %{type: :brief}} = assigns) do
    ~H"""
    <div class="session-card session-brief">
      <h3 class="session-brief-title">{@station.title}</h3>
      <ul class="session-notes">
        <li :for={note <- @station.notes}>{Session.inline(note)}</li>
      </ul>
      <.komoot activities={@station.komoot} />
    </div>
    """
  end

  def station(%{station: %{type: :circuit}} = assigns) do
    log = Session.todays(assigns.logged, assigns.station.slug)
    assigns = assign(assigns, :log, log)

    ~H"""
    <div class="session-circuit">
      <h3 class="session-card-name">{label(@station)}</h3>
      {Phoenix.HTML.raw(WebWeb.FitnessLive.Index.circuit_bar(@station.slug, @station.circuit, @log))}
      <ul :if={@station.moves != []} class="session-circuit-moves">
        <li :for={move <- @station.moves}>
          <%= case Session.link(move) do %>
            <% {slug, name} -> %>
              <button
                type="button"
                class="session-card-name session-circuit-move"
                phx-click="show_figure"
                phx-value-slug={slug}
              >
                {name}
              </button>
              <span class="session-circuit-dose">{Session.inline(Session.detail(move))}</span>
            <% nil -> %>
              <span class="session-circuit-dose">{Session.inline(move)}</span>
          <% end %>
        </li>
      </ul>
    </div>
    """
  end

  def station(assigns) do
    ~H"""
    <.exercise item={@station} logged={@logged} open_set={@open_set} draft={@draft} gym={@gym} />
    """
  end

  # ── An exercise ───────────────────────────────────────────────────────────

  attr :item, :map, required: true
  attr :logged, :list, required: true
  attr :open_set, :any
  attr :draft, :map, default: %{}
  attr :gym, :map, required: true

  def exercise(assigns) do
    plan = assigns.item.plan
    slug = assigns.item.slug
    sets = Session.sets(assigns.logged, slug)
    log = Session.todays(assigns.logged, slug)

    assigns =
      assign(assigns,
        plan: plan,
        slug: slug,
        name: Session.name(assigns.item),
        sets: sets,
        log: log,
        chips?: Session.chips?(plan),
        log_button?: not (Session.chips?(plan) or done?(plan) or log_quick?(plan, assigns.item)),
        plates: plates(assigns.item, plan, sets, assigns.gym),
        level: plan.verdict |> elem(0) |> to_string()
      )

    ~H"""
    <article class="session-card" id={"card-#{@slug}"}>
      <header class="session-card-head">
        <button
          type="button"
          class="session-card-name"
          phx-click="show_figure"
          phx-value-slug={@slug}
          title="See how it's done"
        >
          {@name}
        </button>
        <button
          :if={@log_button?}
          type="button"
          class="log-trigger session-card-log"
          phx-click="open_log"
          phx-value-slug={@slug}
        >
          Log
        </button>
      </header>
      <p :if={Session.detail(@item.text) != ""} class="session-card-plan">
        {Session.inline(Session.detail(@item.text))}
      </p>
      <p :if={@plan[:last_line]} class="session-card-last">Last, {@plan.last_line}</p>
      <p :if={advice(@plan.hint)} class="session-card-hint">{advice(@plan.hint)}</p>
      <p :if={@plan.guard} class={"session-card-guard log-guard log-guard--#{@level}"}>
        {@plan.guard}<span :if={@plan.instead}>. Instead: {@plan.instead}</span>
      </p>
      <p :if={@plates} class="session-card-plates">{@plates}</p>

      <%= if @chips? do %>
        <.chips plan={@plan} sets={@sets} open={@open_set} draft={@draft[@slug]} />
      <% else %>
        <p class="session-card-actions">
          <button
            :if={done?(@plan)}
            type="button"
            class="log-quick"
            phx-click="log_planned"
            phx-value-slug={@slug}
            phx-disable-with="Logging…"
          >
            Done
          </button>
          <button
            :if={log_quick?(@plan, @item)}
            type="button"
            class="log-quick"
            phx-click="open_log"
            phx-value-slug={@slug}
          >
            {case @plan.prescription.kind do
              :laps -> "Log laps"
              :timed -> "Log minutes"
              _ -> "Log time"
            end}
          </button>
        </p>
      <% end %>
      <p :if={@log && !@chips?} class="session-card-logged">Logged: {Fitness.entry_line(@log)}</p>
      <.komoot activities={@item[:komoot] || []} />
    </article>
    """
  end

  # A card's own quick way to log. With neither, and no chips, it keeps the
  # plain Log button.
  defp done?(%{prescription: p, verdict: verdict}) do
    (p.kind in [:hold, :carry, :swim] or (p.kind == :timed and is_integer(p.seconds))) and
      elem(verdict, 0) != :stop
  end

  defp log_quick?(%{prescription: p}, item) do
    (item[:komoot] || []) == [] and
      (p.kind in [:laps, :trial] or (p.kind == :timed and is_nil(p.seconds)))
  end

  # The line under "Last": what the block says next. The last time itself is
  # already on the card, so a hint's own "Last" part is dropped.
  defp advice(nil), do: nil

  defp advice("Last" <> _ = hint) do
    case String.split(hint, " → ", parts: 2) do
      [_last, next] -> next
      _ -> nil
    end
  end

  defp advice(hint), do: hint

  # What goes on the bar for the weight being lifted (today's last set, else
  # the next one), and the warm-up ramp where the line asks for one.
  defp plates(item, plan, sets, gym) do
    with {bar_name, bar} <- Plates.bar(item.slug, gym),
         w when is_number(w) and w > 0 <- (List.last(sets) || Session.next_set(plan, sets))["w"],
         {side, left} <- Plates.per_side(w, bar, gym.plates) do
      plates =
        "#{Entry.number(w * 1.0)} lb: #{Plates.describe(side)} a side (#{bar_name} #{Entry.number(bar)})" <>
          if(left > 0, do: ", #{Entry.number(left)} lb short", else: "")

      ramp =
        if item.text =~ ~r/\bramp\b/i do
          " · Warm-up: " <>
            Enum.map_join(Plates.ramp(w, bar, gym.plates), ", ", fn {r, lbs} ->
              "#{r}×#{Entry.number(lbs)}"
            end)
        else
          ""
        end

      plates <> ramp
    else
      _ -> nil
    end
  end

  # ── What Komoot recorded ──────────────────────────────────────────────────

  attr :activities, :list, default: []

  def komoot(assigns) do
    ~H"""
    <p :for={a <- @activities} class="session-card-logged session-komoot">
      From Komoot: {a.km} km · {a.minutes} min moving<span :if={a.watts}> · ≈{a.watts} W</span><span :if={
        a[:peak_watts]
      }> (≈{a.peak_watts} W peak)</span>
      ·
      <.link navigate={~p"/fitness/rides/#{a.id}"}>the {if a.kind == :run, do: "run", else: "ride"}</.link>
    </p>
    """
  end

  # ── The set buttons ───────────────────────────────────────────────────────

  attr :plan, :map, required: true
  attr :sets, :list, required: true
  attr :open, :any
  attr :draft, :map, default: nil

  def chips(assigns) do
    plan = assigns.plan
    planned = Session.planned_sets(plan)
    sets = assigns.sets

    assigns =
      assign(assigns,
        slug: plan.slug,
        planned: planned,
        next_set: assigns.draft || Session.next_set(plan, sets),
        next: Session.set_label(assigns.draft || Session.next_set(plan, sets)),
        todo: if(length(sets) < planned, do: Enum.to_list((length(sets) + 1)..planned), else: []),
        open_i:
          case assigns.open do
            {slug, i} when slug == plan.slug -> i
            _ -> nil
          end
      )

    ~H"""
    <div
      :if={length(@sets) < @planned or @draft}
      class="log-stepper session-next"
      id={"next-#{@slug}"}
      role="group"
      aria-label="The next set"
    >
      <span class="log-rpe-label">Next set</span>
      <span class="log-step">
        <.draft_step
          :if={@plan.prescription.kind == :weight}
          slug={@slug}
          field="w"
          by={-25}
          text="−25"
          label="25 lb lighter"
        />
        <.draft_step
          slug={@slug}
          field="w"
          by={-step_of(@next_set)}
          text={"−#{Entry.number(step_of(@next_set))}"}
          label="Lighter"
        />
        <output class="log-step-value">{weight_of(@next_set)}</output>
        <.draft_step
          slug={@slug}
          field="w"
          by={step_of(@next_set)}
          text={"+#{Entry.number(step_of(@next_set))}"}
          label="Heavier"
        />
        <.draft_step
          :if={@plan.prescription.kind == :weight}
          slug={@slug}
          field="w"
          by={25}
          text="+25"
          label="25 lb heavier"
        />
      </span>
      <span class="log-step">
        <.draft_step slug={@slug} field="r" by={-1} text="−" label="One rep fewer" />
        <output class="log-step-value">{@next_set["r"]} reps</output>
        <.draft_step slug={@slug} field="r" by={1} text="+" label="One rep more" />
      </span>
    </div>
    <div class="log-sets session-sets" id={"sets-#{@slug}"}>
      <button
        :for={{set, i} <- Enum.with_index(@sets)}
        type="button"
        class={["log-set", "is-done", @open_i == i && "is-open"]}
        phx-click="set_open"
        phx-value-slug={@slug}
        phx-value-i={i}
        aria-label={"Set #{i + 1}, #{Session.set_label(set)}, logged: change it"}
      >
        {Session.set_label(set)}
      </button>
      <button
        :for={n <- @todo}
        type="button"
        class="log-set"
        phx-click="set_done"
        phx-value-slug={@slug}
        aria-label={"Log set #{n}, #{@next}"}
      >
        {@next}
      </button>
      <button
        :if={@todo == []}
        type="button"
        class="log-set log-set--more"
        phx-click="set_done"
        phx-value-slug={@slug}
        aria-label={"Log another set, #{@next}"}
      >
        + set
      </button>
    </div>
    <.stepper
      :if={@open_i && Enum.at(@sets, @open_i)}
      plan={@plan}
      set={Enum.at(@sets, @open_i)}
      i={@open_i}
    />
    <div
      :if={@sets != [] and length(@sets) >= @planned}
      class="log-rpe"
      id={"rpe-#{@slug}"}
      role="group"
      aria-label="How hard was the last set? RPE"
    >
      <span class="log-rpe-label">Last set, RPE</span>
      <button
        :for={rpe <- ~w(7 8 9 10)}
        type="button"
        class="log-rpe-btn"
        phx-click="set_rpe"
        phx-value-slug={@slug}
        phx-value-rpe={rpe}
        aria-pressed={to_string(rpe_of(List.last(@sets)) == rpe)}
      >
        {rpe}
      </button>
    </div>
    """
  end

  defp step_of(set), do: if((set["w"] || 0) < 25, do: 2.5, else: 5.0)

  defp weight_of(%{"w" => w}) when is_number(w) and w > 0, do: "#{Entry.number(w * 1.0)} lb"
  defp weight_of(_set), do: "no weight"

  attr :slug, :string, required: true
  attr :field, :string, required: true
  attr :by, :any, required: true
  attr :text, :string, required: true
  attr :label, :string, required: true

  defp draft_step(assigns) do
    ~H"""
    <button
      type="button"
      class="log-step-btn"
      phx-click="draft_adjust"
      phx-value-slug={@slug}
      phx-value-field={@field}
      phx-value-by={@by}
      aria-label={@label}
    >
      {@text}
    </button>
    """
  end

  defp rpe_of(%{"rpe" => rpe}) when is_number(rpe), do: Entry.number(rpe * 1.0)
  defp rpe_of(_), do: nil

  attr :plan, :map, required: true
  attr :set, :map, required: true
  attr :i, :integer, required: true

  def stepper(assigns) do
    w = assigns.set["w"] || 0
    small = if w < 25, do: 2.5, else: 5.0

    assigns =
      assign(assigns,
        small: small,
        big?: assigns.plan.prescription.kind == :weight,
        weight: if(w > 0, do: "#{Entry.number(w * 1.0)} lb", else: "no weight")
      )

    ~H"""
    <div class="log-stepper" id={"stepper-#{@plan.slug}"} role="group" aria-label={"Set #{@i + 1}"}>
      <span class="log-step">
        <.step :if={@big?} plan={@plan} i={@i} field="w" by={-25} text="−25" label="25 lb lighter" />
        <.step
          plan={@plan}
          i={@i}
          field="w"
          by={-@small}
          text={"−#{Entry.number(@small)}"}
          label={"#{Entry.number(@small)} lb lighter"}
        />
        <output class="log-step-value">{@weight}</output>
        <.step
          plan={@plan}
          i={@i}
          field="w"
          by={@small}
          text={"+#{Entry.number(@small)}"}
          label={"#{Entry.number(@small)} lb heavier"}
        />
        <.step :if={@big?} plan={@plan} i={@i} field="w" by={25} text="+25" label="25 lb heavier" />
      </span>
      <span class="log-step">
        <.step plan={@plan} i={@i} field="r" by={-1} text="−" label="One rep fewer" />
        <output class="log-step-value">{@set["r"]} reps</output>
        <.step plan={@plan} i={@i} field="r" by={1} text="+" label="One rep more" />
      </span>
      <button
        type="button"
        class="log-step-btn log-step-btn--quiet"
        phx-click="set_remove"
        phx-value-slug={@plan.slug}
        phx-value-i={@i}
      >
        Remove set
      </button>
      <button type="button" class="log-step-btn log-step-btn--quiet" phx-click="set_close">Close</button>
    </div>
    """
  end

  attr :plan, :map, required: true
  attr :i, :integer, required: true
  attr :field, :string, required: true
  attr :by, :any, required: true
  attr :text, :string, required: true
  attr :label, :string, required: true

  defp step(assigns) do
    ~H"""
    <button
      type="button"
      class="log-step-btn"
      phx-click="set_adjust"
      phx-value-slug={@plan.slug}
      phx-value-i={@i}
      phx-value-field={@field}
      phx-value-by={@by}
      aria-label={@label}
    >
      {@text}
    </button>
    """
  end

  # ── The figure sheet ──────────────────────────────────────────────────────

  attr :figure, :map, required: true

  def figure_sheet(assigns) do
    ~H"""
    <div class="figure-sheet-backdrop" phx-window-keydown="close_figure" phx-key="Escape">
      <div class="figure-sheet" role="dialog" aria-label={@figure.name} id="figure-sheet">
        <header class="figure-sheet-head">
          <h3>{@figure.name}</h3>
          <button type="button" class="reset-btn" phx-click="close_figure">Close</button>
        </header>
        <WebWeb.FitnessFigure.figure
          :if={@figure.clip}
          id={"sheet-figure-#{@figure.slug}"}
          clip={@figure.clip}
          label={@figure.name}
        />
        <p :if={!@figure.clip} class="figure-sheet-none">No figure for this one yet.</p>
        <p :if={@figure.description} class="figure-sheet-desc">{@figure.description}</p>
        <.link navigate={~p"/fitness/wiki/#{@figure.slug}"} class="figure-sheet-wiki">
          How to do it, in full
        </.link>
      </div>
    </div>
    """
  end

  # ── The session's end ─────────────────────────────────────────────────────

  attr :summary, :map, required: true

  def summary(assigns) do
    ~H"""
    <div class="figure-sheet-backdrop">
      <div
        class="figure-sheet session-summary"
        role="dialog"
        aria-label="Session summary"
        id="session-summary"
      >
        <header class="figure-sheet-head">
          <h3>Session done</h3>
          <button type="button" class="reset-btn" phx-click="close_summary">Close</button>
        </header>
        <p class="session-summary-head">
          <span :if={@summary.minutes}>{@summary.minutes} min</span>
          <span>{@summary.sets} sets</span>
          <span :if={@summary.volume > 0}>{Entry.number(@summary.volume)} lb moved</span>
        </p>
        <ul class="session-summary-list">
          <li :for={row <- @summary.rows}>
            <span class="session-summary-name">{row.name}</span>
            <span class="session-summary-line">{row.line}</span>
            <span :if={row.best} class="session-summary-best">New best: {row.best}</span>
          </li>
        </ul>
        <p :if={@summary.missed != []} class="session-summary-missed">
          Not finished: {Enum.join(@summary.missed, ", ")}
        </p>
      </div>
    </div>
    """
  end
end
