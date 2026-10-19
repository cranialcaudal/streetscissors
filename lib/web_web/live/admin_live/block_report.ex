defmodule WebWeb.AdminLive.BlockReport do
  @moduledoc """
  The training block's report (`/admin/fitness/block`): the experiment as
  the block file frames it, a row per week (days trained, volume, the
  check-ins, the guardrails), each lift's e1RM from its first week to its
  latest, the four charts, and once the last week has begun, the answer.

  Under it are the progress photographs (`Web.Fitness.Photos`), uploaded
  here and shown only here. They are served by
  `WebWeb.FitnessPhotoController` to the admin session alone.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Fitness
  alias Web.Fitness.{Block, Photos, Training, Vault}

  @max_photo 15_000_000

  def mount(_params, session, socket) do
    if session["admin_user"] do
      {:ok,
       socket
       |> assign(page_title: "Block report | Admin")
       |> allow_upload(:photos,
         accept: Photos.accept(),
         max_entries: 4,
         max_file_size: @max_photo
       )
       |> load()}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  defp load(socket) do
    today = Web.Clock.local_today()

    case Block.latest(today) do
      nil ->
        assign(socket, block: nil, photos: Photos.list())

      block ->
        weeks = Training.weeks_so_far(block, today)
        entries = Training.all_entries(block)
        checkins = Fitness.checkins_between(block.start, block.finish)

        assign(socket,
          block: block,
          started?: Date.compare(today, block.start) != :lt,
          weeks: weeks,
          entries: entries,
          report: Training.report(entries, block, weeks, checkins),
          framing: Vault.render_markdown(block.body),
          photos: Photos.list()
        )
    end
  end

  def handle_event("validate_photos", _params, socket), do: {:noreply, socket}

  def handle_event("save_photos", _params, socket) do
    today = Web.Clock.local_today()

    stored =
      consume_uploaded_entries(socket, :photos, fn %{path: path}, entry ->
        {:ok, Photos.store(today, path, Path.extname(entry.client_name))}
      end)

    flash =
      case Enum.count(stored, &match?({:ok, _}, &1)) do
        0 -> {:error, "No photograph was kept."}
        1 -> {:info, "Photograph kept."}
        n -> {:info, "#{n} photographs kept."}
      end

    {:noreply,
     socket |> put_flash(elem(flash, 0), elem(flash, 1)) |> assign(photos: Photos.list())}
  end

  def handle_event("delete_photo", %{"date" => date, "file" => file}, socket) do
    Photos.delete(date, file)

    {:noreply,
     socket |> put_flash(:info, "Photograph set aside.") |> assign(photos: Photos.list())}
  end

  def render(assigns) do
    ~H"""
    <.page_head slug="Training / Fitness" title="Block report">
      <:lede>
        <%= if @block do %>
          {@block.title}, {Calendar.strftime(@block.start, "%-d %b")} to {Calendar.strftime(
            @block.finish,
            "%-d %b %Y"
          )}.
          <%= if @started? do %>
            Week {@block.week} of {@block.weeks}: {@block.phase}.
          <% else %>
            It has not begun.
          <% end %>
        <% else %>
          No training block in the vault.
        <% end %>
        Check-ins and the charts are on <.link
          navigate={~p"/admin/fitness?tab=checkin"}
          class="adm-link"
        >Fitness</.link>.
      </:lede>
    </.page_head>

    <%= if @block do %>
      <p :if={@report.answer} class="adm-fit-answer" id="block-answer">{@report.answer}</p>

      <.panel title="The experiment">
        <div class="adm-fit-framing">{raw(@framing)}</div>
      </.panel>

      <.panel title="Week by week">
        <.rows id="block-weeks" rows={@report.rows}>
          <:col :let={r} label="Week">W{r.week}</:col>
          <:col :let={r} label="Phase">{r.phase}</:col>
          <:col :let={r} label="Days trained">{r.done} of {r.planned}</:col>
          <:col :let={r} label="Volume (lb)">{round(r.volume)}</:col>
          <:col :let={r} label="Pain">{r.pain || "–"}</:col>
          <:col :let={r} label="Sleep (h)">{r.sleep || "–"}</:col>
          <:col :let={r} label="Energy">{r.energy || "–"}</:col>
          <:col :let={r} label="Held · stopped">{r.held} · {r.stopped}</:col>
        </.rows>
      </.panel>

      <.panel title="Lifts">
        <%= if @report.lifts == [] do %>
          <.empty>No lift has an e1RM yet: log a weight and reps on the regimen page.</.empty>
        <% else %>
          <.rows id="block-lifts" rows={@report.lifts}>
            <:col :let={l} label="Lift">{l.name}</:col>
            <:col :let={l} label="Pattern">{WebWeb.FitnessCharts.pattern_name(l.pattern)}</:col>
            <:col :let={l} label="First">W{elem(l.from, 0)}: {round(elem(l.from, 1))} lb</:col>
            <:col :let={l} label="Latest">W{elem(l.to, 0)}: {round(elem(l.to, 1))} lb</:col>
            <:col :let={l} label="Change">{if l.change, do: "#{l.change}%", else: "–"}</:col>
          </.rows>
        <% end %>
      </.panel>

      <.panel title="Charts">
        <WebWeb.FitnessCharts.block_charts block={@block} entries={@entries} weeks={@weeks} />
      </.panel>
    <% end %>

    <.panel title="Progress photographs">
      <p class="adm-hint">
        Kept beside the uploads, never under them; shown only here, and copied nightly and to the drive.
      </p>
      <form id="photo-form" phx-submit="save_photos" phx-change="validate_photos">
        <.drop_zone
          upload={@uploads.photos}
          title="Drop up to four photographs"
          hint="JPEG, PNG or WebP, 15 MB each."
          error_message={&photo_error/1}
        />
        <button
          type="submit"
          class="adm-btn adm-btn--primary"
          disabled={@uploads.photos.entries == []}
        >
          Keep photographs
        </button>
      </form>

      <div :for={day <- @photos} class="adm-fit-photo-day" id={"photos-#{day.date}"}>
        <h3 class="adm-fit-photo-date">{Calendar.strftime(day.date, "%a %-d %b %Y")}</h3>
        <ul class="adm-fit-photos">
          <li :for={file <- day.files}>
            <img
              src={~p"/admin/fitness/photos/#{Date.to_iso8601(day.date)}/#{file}"}
              alt={"Progress photograph, #{day.date}"}
              loading="lazy"
            />
            <button
              type="button"
              class="adm-btn adm-btn--quiet adm-btn--small"
              phx-click="delete_photo"
              phx-value-date={Date.to_iso8601(day.date)}
              phx-value-file={file}
              data-confirm="Set this photograph aside?"
            >
              Set aside
            </button>
          </li>
        </ul>
      </div>
    </.panel>
    """
  end

  defp photo_error(:too_large), do: "over 15 MB"
  defp photo_error(:not_accepted), do: "not a JPEG, PNG or WebP"
  defp photo_error(:too_many_files), do: "four at a time"
  defp photo_error(other), do: to_string(other)
end
