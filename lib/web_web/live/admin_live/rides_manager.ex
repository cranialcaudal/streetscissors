defmodule WebWeb.AdminLive.RidesManager do
  @moduledoc """
  Activities: the Komoot mirror's controls, what a stranger can see of it,
  and the way heart rate gets in.

  There is nothing to edit here — Komoot is the only input — so the page is:

    * **Komoot.** A "Sync now" button, when the last pass ran and what came
      of it (`KomootSync.last_run/0`, written by every pass), and the
      tripwire's verdict (`Web.Rides.Privacy`): whether any activity, read
      the way a visitor's browser reads it, still shows a private place.
      "Sync now" forces every tour to be looked at again, so it is also the
      button for "check what strangers can see".
    * **Heart & energy.** Komoot keeps none, so this is where Apple Health
      comes in: drop the Health app's export and it is read in the
      background (`Web.Rides.HealthImport`), or make a token for an app that
      posts workouts as they happen (`WebWeb.HealthWebhookController`).
    * **The archive**, with what each activity has: a share link, a map, a
      heart rate.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Rides
  alias Web.Rides.{AppleHealth, HealthImport, KomootSync, Privacy, Units, Workout}

  # Apple's export of a few years on a watch runs to hundreds of megabytes.
  @max_export_size 4_000_000_000

  def mount(_params, _session, socket) do
    if connected?(socket), do: HealthImport.subscribe()

    {:ok,
     socket
     |> assign(
       page_title: "Activities | Admin",
       komoot_enabled: KomootSync.enabled?(),
       zones: Privacy.zones(),
       sync_running: false,
       new_token: nil
     )
     |> load()
     |> allow_upload(:health_export,
       accept: ~w(.zip .xml),
       max_entries: 1,
       max_file_size: @max_export_size,
       auto_upload: true,
       progress: &handle_progress/3,
       # Straight into the import's own inbox, never /tmp.
       writer: fn _name, _entry, _socket -> {WebWeb.HealthExportWriter, []} end
     )}
  end

  defp load(socket) do
    rides = Rides.list_rides()

    assign(socket,
      rides: rides,
      last_run: KomootSync.last_run(),
      views: Enum.frequencies_by(rides, & &1.stranger_view),
      measured: Enum.count(rides, &match?(%Workout{}, &1.health)),
      import: HealthImport.last(),
      webhook_open: AppleHealth.webhook_open?()
    )
  end

  # --- Komoot ----------------------------------------------------------------

  def handle_event("sync_komoot", _params, socket) do
    {:noreply,
     socket
     |> assign(sync_running: true)
     # force: true — the button exists for "read Komoot again now", so it
     # must not be answered by a cached ETag saying nothing changed, and it
     # re-reads every tour as a stranger rather than only the ones that moved.
     |> start_async(:komoot_sync, fn -> KomootSync.sync(force: true) end)}
  end

  # --- Apple Health ----------------------------------------------------------

  def handle_event("validate_export", _params, socket), do: {:noreply, socket}

  def handle_event("create_token", _params, socket) do
    {:noreply, socket |> assign(new_token: AppleHealth.create_webhook_token()) |> load()}
  end

  def handle_event("revoke_token", _params, socket) do
    AppleHealth.revoke_webhook_token()

    {:noreply,
     socket
     |> assign(new_token: nil)
     |> load()
     |> put_flash(:info, "The webhook's token is revoked.")}
  end

  defp handle_progress(:health_export, entry, socket) do
    if entry.done? do
      # The writer put it in the import's inbox; the import deletes it when
      # it has been read.
      [path] =
        consume_uploaded_entries(socket, :health_export, fn %{path: path}, _entry ->
          {:ok, path}
        end)

      case HealthImport.start(path) do
        :ok ->
          {:noreply,
           socket |> load() |> put_flash(:info, "Reading the export. This takes a minute.")}

        {:error, :running} ->
          {:noreply, put_flash(socket, :error, "An import is already running.")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_info(:health_import, socket), do: {:noreply, load(socket)}

  def handle_async(:komoot_sync, {:ok, result}, socket) do
    socket = assign(socket, sync_running: false)

    case result do
      {:ok, summary} ->
        {:noreply,
         socket
         |> load()
         |> put_flash(
           :info,
           "Komoot sync: #{summary.imported} imported, #{summary.updated} updated, " <>
             "#{summary.deleted} deleted, #{summary.failed} failed."
         )}

      :disabled ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Komoot sync is disabled — set KOMOOT_EMAIL and KOMOOT_PASSWORD."
         )}

      {:error, reason} ->
        {:noreply,
         socket
         |> load()
         |> put_flash(:error, "Komoot sync failed: #{inspect(reason)}")}
    end
  end

  def handle_async(:komoot_sync, {:exit, reason}, socket) do
    KomootSync.record_run({:error, {:crashed, reason}})

    {:noreply,
     socket
     |> assign(sync_running: false)
     |> load()
     |> put_flash(:error, "Komoot sync crashed: #{inspect(reason)}")}
  end

  def render(assigns) do
    ~H"""
    <.page_head slug="Sync / Activities" title="Activities">
      <:lede>
        Every tour recorded on Komoot, checked hourly and drawn by Komoot's own embed. Edits,
        privacy changes and deletions in the app carry over on their own.
      </:lede>
      <:actions>
        <button
          :if={@komoot_enabled}
          phx-click="sync_komoot"
          class="adm-btn adm-btn--primary"
          disabled={@sync_running}
        >
          <.icon name="hero-arrow-path" class="size-4" />
          {if @sync_running, do: "Syncing…", else: "Sync now"}
        </button>
      </:actions>
    </.page_head>

    <.panel title="Komoot" id="komoot">
      <ul class="adm-status">
        <li :if={!@komoot_enabled}>
          <span class="adm-status-dot" aria-hidden="true"></span>
          <span class="adm-status-name">Sync</span>
          <span class="adm-status-detail">
            Disabled — set <code>KOMOOT_EMAIL</code>
            and <code>KOMOOT_PASSWORD</code>
            in the environment.
          </span>
        </li>
        <li :if={@komoot_enabled}>
          <span class={["adm-status-dot", run_class(@last_run.status)]} aria-hidden="true"></span>
          <span class="adm-status-name">Last pass</span>
          <span class="adm-status-detail">
            {run_line(@last_run)}
          </span>
        </li>
        <li :if={@komoot_enabled} id="privacy-status">
          <span class={["adm-status-dot", privacy_class(@zones, @views)]} aria-hidden="true"></span>
          <span class="adm-status-name">What strangers see</span>
          <span class="adm-status-detail">{privacy_line(@zones, @views)}</span>
        </li>
      </ul>
      <p class="adm-help">
        Komoot hides home with the privacy zone set in its app. The site keeps its own note of
        where home is (<code>RIDE_PRIVACY_ZONES</code>) and checks each tour as a stranger is
        shown it: one that comes within {Privacy.tripwire_m()} m loses its embed and map until it
        no longer does. A zone trims where a tour starts and ends, not a pass back through it, so
        a ride that came home and went out again is held back too, with no alarm: split or trim
        it in the app to show it. "Sync now" looks at every tour again.
      </p>
    </.panel>

    <.panel title="Heart & energy" id="health">
      <ul class="adm-status">
        <li id="health-coverage">
          <span
            class={["adm-status-dot", @measured > 0 && "adm-status-dot--ok"]}
            aria-hidden="true"
          >
          </span>
          <span class="adm-status-name">On file</span>
          <span class="adm-status-detail">
            Heart rate and energy for {@measured} of {length(@rides)} activities.
          </span>
        </li>
        <li :if={@import} id="health-import">
          <span class={["adm-status-dot", import_class(@import.status)]} aria-hidden="true"></span>
          <span class="adm-status-name">Last import</span>
          <span class="adm-status-detail">{import_line(@import)}</span>
        </li>
        <li id="health-webhook">
          <span class={["adm-status-dot", @webhook_open && "adm-status-dot--ok"]} aria-hidden="true">
          </span>
          <span class="adm-status-name">Automatic</span>
          <span class="adm-status-detail">
            {if @webhook_open,
              do: "Open: an app holding the token can post workouts as they are recorded.",
              else: "Closed. No token has been made, so nothing can post here."}
          </span>
        </li>
      </ul>

      <p class="adm-help">
        Komoot keeps no heart rate and no calories: the watch writes them to Apple Health. On the
        phone, open Health, tap your picture, then <strong>Export All Health Data</strong>, and
        drop the file it makes here. Only workouts that match an activity are kept, with the
        heart rate during them; the rest of the file is never read, and the file is deleted as
        soon as it has been.
      </p>

      <form id="health-export-form" phx-change="validate_export">
        <.drop_zone
          upload={@uploads.health_export}
          title="Drop export.zip here"
          hint="Apple Health's own export, as the zip it shares or the export.xml inside it."
          error_message={&upload_error_message/1}
          class="adm-drop--spaced"
        />
      </form>

      <div class="adm-form-actions">
        <button
          :if={!@webhook_open}
          type="button"
          phx-click="create_token"
          id="health-token-create"
          class="adm-btn adm-btn--quiet"
        >
          Make a token for automatic delivery
        </button>
        <button
          :if={@webhook_open}
          type="button"
          phx-click="revoke_token"
          id="health-token-revoke"
          class="adm-link adm-link--danger"
          data-confirm="Revoke the token? Whatever is posting workouts with it will be refused."
        >
          Revoke the token
        </button>
      </div>

      <div :if={@new_token} id="health-token" class="adm-sheet">
        <p class="adm-help">
          Shown once. In the Health Auto Export app, add a REST API automation for
          <strong>Workouts</strong>
          (JSON, with heart-rate data) that posts to the address below, with the header
          <code>Authorization: Bearer</code>
          followed by this token.
        </p>
        <.copy_field
          id="health-webhook-url"
          value={WebWeb.Endpoint.url() <> "/api/health/ingest"}
          label="Copy the address"
          names="The webhook's address"
        />
        <.copy_field
          id="health-webhook-token"
          value={@new_token}
          label="Copy the token"
          names="The webhook's token"
        />
      </div>
    </.panel>

    <.panel title="Archive" count={length(@rides)}>
      <.rows id="rides" rows={@rides} row_id={&"ride-#{&1.id}"}>
        <:col :let={ride} label="Name" class="adm-cell-title">{ride.name || "Untitled"}</:col>
        <:col :let={ride} label="Date">{Units.date(ride.started_at)}</:col>
        <:col :let={ride} label="Sport">{Units.sport(ride.sport)}</:col>
        <:col :let={ride} label="Distance" class="adm-cell-num">
          {Units.distance(ride.distance_m)}
        </:col>
        <:col :let={ride} label="Heart" class="adm-cell-num">
          {heart(ride.health)}
        </:col>
        <:col :let={ride} label="On Komoot">
          <.pill :if={ride.visibility == "private"} tone="quiet" class="ride-private">Private</.pill>
          <.pill :if={ride.visibility != "private"} tone="live">Public</.pill>
          <.pill :if={ride.stranger_view == "exposed"} tone="failed">Exposed</.pill>
          <.pill :if={ride.stranger_view == "passing"} tone="held">Passes home</.pill>
          <.pill :if={ride.stranger_view == "hidden"} tone="quiet">Hidden by Komoot</.pill>
          <.pill :if={is_nil(ride.stranger_view)} tone="held">Not checked yet</.pill>
        </:col>
        <:action :let={ride}>
          <.link navigate={~p"/fitness/rides/#{ride.id}"} class="adm-link">View</.link>
        </:action>
        <:empty>Nothing synced yet.</:empty>
      </.rows>
    </.panel>
    """
  end

  defp heart(%Workout{avg_hr: avg}) when is_integer(avg), do: Units.bpm(avg)
  defp heart(_health), do: "—"

  defp run_line(%{at: nil}), do: "No pass recorded yet."
  defp run_line(%{at: at, detail: detail}), do: "#{ago(at)} — #{detail}"

  defp run_class(:ok), do: "adm-status-dot--ok"
  defp run_class(:partial), do: "adm-status-dot--warn"
  defp run_class(:failed), do: "adm-status-dot--fail"
  defp run_class(_), do: nil

  # Says how many, never where.
  defp privacy_line(:invalid, _views),
    do:
      "RIDE_PRIVACY_ZONES can't be read, so no tour can be checked: every embed and map is withheld until it is fixed."

  defp privacy_line({:ok, []}, views),
    do:
      "Not checked. Komoot's privacy zone is trusted as it stands; set RIDE_PRIVACY_ZONES (lat,lng) to have each tour verified." <>
        also(views)

  defp privacy_line({:ok, zones}, views) do
    case Map.get(views, "exposed", 0) do
      0 ->
        "No activity begins or ends near #{places(zones)} as a stranger is shown it. Komoot's privacy zone is doing its job."

      n ->
        "#{activities(n)} still #{if n == 1, do: "begins or ends", else: "begin or end"} at a private place as a stranger is shown #{if n == 1, do: "it", else: "them"}: " <>
          "Komoot's privacy zone is not hiding #{if n == 1, do: "it", else: "them"}. " <>
          "#{if n == 1, do: "Its embed and map are", else: "Their embeds and maps are"} withheld. " <>
          "Check the zone in the Komoot app, then Sync now."
    end <> also(views)
  end

  # The quieter states, when there are any: tours that pass home mid-way,
  # tours Komoot keeps from strangers altogether, and tours the sync has not
  # yet asked about.
  defp also(views) do
    passing =
      case Map.get(views, "passing", 0) do
        0 ->
          []

        1 ->
          [
            "1 passes it mid-tour, which a zone does not trim, and is shown without Komoot's map until it is split or trimmed in the app."
          ]

        n ->
          [
            "#{n} pass it mid-tour, which a zone does not trim, and are shown without Komoot's map until they are split or trimmed in the app."
          ]
      end

    hidden =
      case Map.get(views, "hidden", 0) do
        0 ->
          []

        1 ->
          ["1 lies wholly inside Komoot's zone, and Komoot shows a stranger nothing of it."]

        n ->
          ["#{n} lie wholly inside Komoot's zone, and Komoot shows a stranger nothing of them."]
      end

    waiting =
      case Map.get(views, nil, 0) do
        0 ->
          []

        n ->
          ["#{activities(n)} not checked yet: nothing of Komoot's is shown for one until it is."]
      end

    Enum.map_join(passing ++ hidden ++ waiting, &(" " <> &1))
  end

  defp places([_]), do: "the private place on file"
  defp places(zones), do: "the #{length(zones)} private places on file"

  defp activities(1), do: "1 activity"
  defp activities(n), do: "#{n} activities"

  defp privacy_class(:invalid, _views), do: "adm-status-dot--fail"
  defp privacy_class({:ok, []}, _views), do: "adm-status-dot--warn"
  defp privacy_class({:ok, _zones}, %{"exposed" => _n}), do: "adm-status-dot--fail"
  defp privacy_class({:ok, _zones}, _views), do: "adm-status-dot--ok"

  defp import_line(%{status: :running, at: at}), do: "Reading the export, started #{ago(at)}."

  defp import_line(%{status: :ok, at: at} = result) do
    "#{ago(at)} — #{result.in_export} workouts in the export, #{result.matched} matched to an " <>
      "activity, #{result.heart_samples} heart-rate points kept."
  end

  defp import_line(%{status: :failed, at: at, reason: reason}),
    do: "#{ago(at)} — it failed: #{reason}."

  defp import_class(:ok), do: "adm-status-dot--ok"
  defp import_class(:running), do: "adm-status-dot--warn"
  defp import_class(:failed), do: "adm-status-dot--fail"

  defp upload_error_message(:too_large), do: "That file is too large."
  defp upload_error_message(:not_accepted), do: "That is not a .zip or .xml file."
  defp upload_error_message(:too_many_files), do: "One export at a time."
  defp upload_error_message(error), do: to_string(error)
end
