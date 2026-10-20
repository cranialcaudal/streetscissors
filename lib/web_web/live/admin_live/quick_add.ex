defmodule WebWeb.AdminLive.QuickAdd do
  @moduledoc """
  `/admin/quick`: one place to put something down in a few taps, from the
  "+" in the admin bar on every public page, or from the phone's home screen
  (the web app's shortcuts in `priv/static/manifest.json`).

  Three tabs, each in the address (`?tab=log|checkin|note`):

  * **Log** a set of any exercise the wiki has, filed by the same rules as
    the day page (`Web.Fitness.Entry`): today unless an earlier day is named.
  * **Check in** for today, the checks `content/fitness/checkins.md` lists
    (`Fitness.save_checkin/2`, over whatever today already had).
  * **Note**: a line appended to the private `content/notes/inbox.md`
    (`Web.Notes`), with keywords if given.

  It sits in `live_session :admin`, so nobody else reaches it.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Fitness
  alias Web.Fitness.{Checks, Entry, Vault}

  @tabs ~w(log checkin note)

  def mount(_params, session, socket) do
    if session["admin_user"] do
      {:ok,
       assign(socket,
         page_title: "Quick add | Admin",
         exercises: exercises(),
         checks: Checks.all(),
         today: Web.Clock.local_today(),
         last: nil
       )}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  def handle_params(params, _uri, socket) do
    tab = if params["tab"] in @tabs, do: params["tab"], else: "log"
    {:noreply, socket |> assign(tab: tab) |> assign_answers()}
  end

  # Every exercise the wiki has, by name, for the Log tab's suggestions.
  defp exercises do
    for {_group, list} <- Vault.list_all_exercises(), exercise <- list do
      %{slug: exercise.slug, name: exercise.name}
    end
    |> Enum.sort_by(&String.downcase(&1.name))
  end

  defp assign_answers(socket) do
    today = socket.assigns.today
    todays = Fitness.checkin_on(today)
    assign(socket, answers: (todays && todays.answers) || %{})
  end

  # The exercise as typed: a wiki name or a slug, either way round.
  defp exercise_for(typed, exercises) do
    wanted = typed |> to_string() |> String.trim() |> String.downcase()

    Enum.find(exercises, fn %{slug: slug, name: name} ->
      wanted in [slug, String.downcase(name)]
    end)
  end

  def handle_event("log", %{"log" => params}, socket) do
    metrics = Entry.metrics(params)

    with %{slug: slug} <- exercise_for(params["exercise"], socket.assigns.exercises),
         {:ok, exercise} <- Fitness.loggable_exercise(slug),
         true <- map_size(metrics) > 0,
         {:ok, log} <-
           Fitness.create_exercise_log(%{
             exercise_id: exercise.id,
             date: Entry.date(params["date"]),
             metrics: metrics,
             note: blank(params["note"])
           }) do
      line = "#{exercise.name}: #{Fitness.entry_line(log)}"
      {:noreply, socket |> assign(last: line) |> put_flash(:info, "Logged #{line}.")}
    else
      nil -> {:noreply, put_flash(socket, :error, "There is no exercise by that name in the wiki.")}
      false -> {:noreply, put_flash(socket, :error, "Enter at least one value to log.")}
      _ -> {:noreply, put_flash(socket, :error, "Couldn't save that — try again.")}
    end
  end

  def handle_event("checkin", %{"checkin" => params}, socket) do
    attrs = %{
      "date" => socket.assigns.today,
      "answers" => Map.get(params, "answers", %{}),
      "note" => blank(params["note"])
    }

    case Fitness.save_checkin(attrs, socket.assigns.checks) do
      {:ok, _} -> {:noreply, socket |> assign_answers() |> put_flash(:info, "Check-in saved.")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "Check-in not saved: check the numbers.")}
    end
  end

  def handle_event("note", %{"note" => params}, socket) do
    case Web.Notes.append(params["text"], params["keywords"] || "") do
      :ok -> {:noreply, put_flash(socket, :info, "Noted.")}
      {:error, :blank} -> {:noreply, put_flash(socket, :error, "Write something first.")}
      {:error, reason} -> {:noreply, put_flash(socket, :error, "Not noted: #{inspect(reason)}")}
    end
  end

  defp blank(nil), do: nil
  defp blank(value), do: if(String.trim(value) == "", do: nil, else: String.trim(value))

  def render(assigns) do
    ~H"""
    <.page_head slug="Quick add" title="Put it down">
      <:lede>A set, today's check-in, or a thought, in a few taps.</:lede>
    </.page_head>

    <.tabs label="What to add">
      <:tab patch={~p"/admin/quick?tab=log"} active={@tab == "log"}>Log a set</:tab>
      <:tab patch={~p"/admin/quick?tab=checkin"} active={@tab == "checkin"}>Check in</:tab>
      <:tab patch={~p"/admin/quick?tab=note"} active={@tab == "note"}>Note</:tab>
    </.tabs>

    <form :if={@tab == "log"} id="quick-log" phx-submit="log" class="adm-quick">
      <datalist id="quick-exercises">
        <option :for={exercise <- @exercises} value={exercise.name} />
      </datalist>
      <label class="adm-field">
        <span class="adm-label">Exercise</span>
        <input
          type="text"
          name="log[exercise]"
          list="quick-exercises"
          class="adm-input"
          autocomplete="off"
          required
        />
      </label>
      <div class="adm-form-row">
        <label class="adm-field">
          <span class="adm-label">Sets</span>
          <input type="number" name="log[sets]" min="1" max="20" inputmode="numeric" class="adm-input" />
        </label>
        <label class="adm-field">
          <span class="adm-label">Reps</span>
          <input type="number" name="log[reps]" min="1" max="200" inputmode="numeric" class="adm-input" />
        </label>
        <label class="adm-field">
          <span class="adm-label">Weight</span>
          <input type="text" name="log[weight_other]" placeholder="e.g. 35 lbs" class="adm-input" />
        </label>
        <label class="adm-field">
          <span class="adm-label">RPE</span>
          <input type="text" name="log[rpe]" inputmode="decimal" placeholder="8" class="adm-input" />
        </label>
      </div>
      <div class="adm-form-row">
        <label class="adm-field">
          <span class="adm-label">Time or distance</span>
          <input type="text" name="log[result]" placeholder="e.g. 2 miles, 8:26 pace" class="adm-input" />
        </label>
        <label class="adm-field">
          <span class="adm-label">Day</span>
          <input
            type="date"
            name="log[date]"
            value={Date.to_iso8601(@today)}
            max={Date.to_iso8601(@today)}
            class="adm-input"
          />
        </label>
      </div>
      <label class="adm-field">
        <span class="adm-label">Note</span>
        <input type="text" name="log[note]" placeholder="optional" class="adm-input" />
      </label>
      <p :if={@last} class="adm-help" id="quick-last">Last logged: {@last}</p>
      <div>
        <button type="submit" class="adm-btn adm-btn--primary" phx-disable-with="Saving…">Log it</button>
      </div>
    </form>

    <form :if={@tab == "checkin"} id="quick-checkin" phx-submit="checkin" class="adm-quick">
      <.empty :if={@checks == []}>
        No checks are defined. A check-in asks what <code>content/fitness/checkins.md</code> lists.
      </.empty>
      <fieldset :for={check <- @checks} class="adm-fit-check" id={"quick-check-#{check.id}"}>
        <legend class="adm-label">{check.label}</legend>
        <%= if check.kind == :state do %>
          <div class="adm-fit-states">
            <label
              :for={state <- check.states}
              class={["adm-fit-state", "adm-fit-state--#{Checks.level(check, state)}"]}
            >
              <input
                type="radio"
                name={"checkin[answers][#{check.id}]"}
                value={state}
                checked={@answers[check.id] == state}
              />
              <span>{state}</span>
            </label>
            <label class="adm-fit-state adm-fit-state--skip">
              <input
                type="radio"
                name={"checkin[answers][#{check.id}]"}
                value=""
                checked={is_nil(@answers[check.id])}
              />
              <span>skip</span>
            </label>
          </div>
        <% else %>
          <input
            type="text"
            inputmode="decimal"
            name={"checkin[answers][#{check.id}]"}
            value={@answers[check.id]}
            class="adm-input"
            placeholder={check.unit}
          />
        <% end %>
      </fieldset>
      <div :if={@checks != []}>
        <button type="submit" class="adm-btn adm-btn--primary" phx-disable-with="Saving…">
          Save check-in
        </button>
      </div>
    </form>

    <form :if={@tab == "note"} id="quick-note" phx-submit="note" class="adm-quick">
      <label class="adm-field">
        <span class="adm-label">The thought</span>
        <textarea name="note[text]" rows="4" class="adm-input adm-input--prose" required></textarea>
      </label>
      <label class="adm-field">
        <span class="adm-label">Keywords</span>
        <input type="text" name="note[keywords]" placeholder="optional, comma-separated" class="adm-input" />
      </label>
      <p class="adm-help">Kept in content/notes/inbox.md, which no public page shows.</p>
      <div>
        <button type="submit" class="adm-btn adm-btn--primary" phx-disable-with="Saving…">Note it</button>
      </div>
    </form>
    """
  end
end
