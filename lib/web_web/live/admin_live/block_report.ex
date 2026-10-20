defmodule WebWeb.AdminLive.BlockReport do
  @moduledoc """
  The training block's report (`/admin/fitness/block`), the block read as
  an experiment:

    * the hypothesis as the block file states it, and each `predict:` line
      against what happened;
    * the author's own retrospective (the block file's `## Retrospective`);
    * a row per week: sets and days done of planned, volume, stress, each
      check-in's answers, the days the check-ins held or stopped the block;
    * each lift's e1RM from its first week to its latest, and the charts;
    * the progress photographs, the first of each pose beside its latest.

  The photographs (`Web.Fitness.Photos`) are uploaded here and shown only
  here, served by `WebWeb.FitnessPhotoController` to the admin alone.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Fitness
  alias Web.Fitness.{Block, Checks, Photos, Report, Training, Vault}

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
    checks = Checks.all()

    socket =
      assign(socket,
        reports: Report.list(),
        rendering: Map.get(socket.assigns, :rendering, false)
      )

    case Block.latest(today) do
      nil ->
        assign(socket, block: nil, checks: checks, poses: [], photos: Photos.list(), by_pose: %{})

      block ->
        weeks = Training.weeks_so_far(block, today)
        entries = Training.all_entries(block)
        checkins = Fitness.checkins_between(block.opens, block.finish)
        plan = Training.plan(block)

        assign(socket,
          block: block,
          checks: checks,
          plan: plan,
          started?: Date.compare(today, block.opens) != :lt,
          weeks: weeks,
          entries: entries,
          report: Training.report(entries, block, weeks, checkins, checks, plan),
          framing: Vault.render_markdown(block.body),
          poses: block.poses,
          photos: Photos.list(),
          by_pose: Photos.by_pose(block.poses)
        )
    end
  end

  def handle_event("validate_photos", _params, socket), do: {:noreply, socket}

  def handle_event("save_photos", params, socket) do
    today = Web.Clock.local_today()
    pose = if params["pose"] in socket.assigns.poses, do: params["pose"]

    stored =
      consume_uploaded_entries(socket, :photos, fn %{path: path}, entry ->
        {:ok, Photos.store(today, path, Path.extname(entry.client_name), pose)}
      end)

    flash =
      case Enum.count(stored, &match?({:ok, _}, &1)) do
        0 -> {:error, "No photograph was kept."}
        1 -> {:info, "Photograph kept."}
        n -> {:info, "#{n} photographs kept."}
      end

    {:noreply, socket |> put_flash(elem(flash, 0), elem(flash, 1)) |> load()}
  end

  def handle_event("render_report", _params, socket) do
    {:noreply,
     socket
     |> assign(rendering: true)
     |> start_async(:render, fn -> Report.render(Web.Clock.local_today()) end)}
  end

  def handle_event("delete_photo", %{"date" => date, "file" => file}, socket) do
    Photos.delete(date, file)
    {:noreply, socket |> put_flash(:info, "Photograph set aside.") |> load()}
  end

  def handle_async(:render, {:ok, {:ok, _path}}, socket),
    do:
      {:noreply,
       socket |> assign(rendering: false) |> put_flash(:info, "Report rendered.") |> load()}

  def handle_async(:render, {:ok, {:error, reason}}, socket),
    do:
      {:noreply,
       socket
       |> assign(rendering: false)
       |> put_flash(:error, "The report did not render: #{report_error(reason)}")}

  def handle_async(:render, {:exit, _}, socket),
    do:
      {:noreply,
       socket |> assign(rendering: false) |> put_flash(:error, "The report did not render.")}

  defp report_error(:no_quarto), do: "Quarto is not installed."
  defp report_error(:no_report_script), do: "scripts/fitness_report.qmd is missing."
  defp report_error(:busy), do: "one is already rendering."

  defp report_error({:quarto, status, _}),
    do: "Quarto stopped with status #{status}; see the journal."

  defp report_error(other), do: inspect(other)

  def render(assigns) do
    ~H"""
    <.page_head slug="Training / Fitness" title="Block report">
      <:lede>
        <%= if @block do %>
          {@block.title}, {Calendar.strftime(@block.opens, "%-d %b")} to {Calendar.strftime(
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
      <:actions>
        <.link :if={@reports != []} href={~p"/admin/fitness/report"} class="adm-btn" target="_blank">
          Weekly report, {Calendar.strftime(hd(@reports), "%-d %b")}
        </.link>
        <button
          type="button"
          class="adm-btn adm-btn--quiet"
          phx-click="render_report"
          disabled={@rendering}
          id="render-report"
        >
          {if @rendering, do: "Rendering…", else: "Render now"}
        </button>
      </:actions>
    </.page_head>

    <%= if @block do %>
      <p :if={@report.answer} class="adm-fit-answer" id="block-answer">{@report.answer}</p>

      <.panel title="Predicted and actual">
        <p :if={@block.hypothesis} class="adm-fit-hypothesis" id="block-hypothesis">
          “{@block.hypothesis}”
        </p>
        <%= if @report.predictions == [] do %>
          <.empty>The block file has no <code>predict:</code> line to check.</.empty>
        <% else %>
          <.rows id="block-predictions" rows={@report.predictions}>
            <:col :let={p} label="Measure">{measure_name(p.measure)}</:col>
            <:col :let={p} label="Predicted">{signed(p.value)}{unit(p.unit)}</:col>
            <:col :let={p} label="So far">
              {if p.actual, do: "#{signed(p.actual)}#{unit(p.unit)}", else: "–"}
            </:col>
            <:col :let={p} label="">{if p.actual, do: if(p.met, do: "met", else: "not yet")}</:col>
          </.rows>
        <% end %>
      </.panel>

      <.panel title="Retrospective">
        <%= if @report.retrospective do %>
          <div class="adm-fit-framing" id="block-retrospective">
            {raw(Vault.render_markdown(@report.retrospective))}
          </div>
        <% else %>
          <.empty>
            Not written yet: it goes under <code>## Retrospective</code> in the block file.
          </.empty>
        <% end %>
      </.panel>

      <.panel title="Week by week">
        <.rows id="block-weeks" rows={@report.rows}>
          <:col :let={r} label="Week">W{r.week}</:col>
          <:col :let={r} label="Phase">{r.phase}</:col>
          <:col :let={r} label="Sets done">{r.sets_done} of {r.sets_planned}</:col>
          <:col :let={r} label="Days">{r.days_done} of {r.days_planned}</:col>
          <:col :let={r} label="Volume (lb)">{round(r.volume)}</:col>
          <:col :let={r} label="Stress">{round(r.stress || 0)}</:col>
          <:col :let={r} :for={check <- @checks} label={check.label}>{r.checks[check.id]}</:col>
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
        <WebWeb.FitnessCharts.block_charts
          block={@block}
          entries={@entries}
          weeks={@weeks}
          plan={@plan}
        />
      </.panel>

      <.panel title="The experiment">
        <div class="adm-fit-framing">{raw(@framing)}</div>
      </.panel>
    <% end %>

    <.panel title="Progress photographs">
      <p class="adm-hint">
        The same poses, the same light, the same spot, any camera: the standard is what makes two
        comparable. Kept beside the uploads, never under them; shown only here, and copied nightly
        and to the drive.
      </p>

      <div :if={@poses != []} class="adm-fit-compare" id="photo-compare">
        <figure :for={pose <- @poses} class="adm-fit-pose">
          <figcaption class="adm-fit-photo-date">{String.capitalize(pose)}</figcaption>
          <%= case Map.get(@by_pose, pose, []) do %>
            <% [] -> %>
              <p class="adm-hint">None yet.</p>
            <% [only] -> %>
              <.photo date={only.date} file={only.file} />
            <% shots -> %>
              <div class="adm-fit-pair">
                <.photo date={hd(shots).date} file={hd(shots).file} />
                <.photo date={List.last(shots).date} file={List.last(shots).file} />
              </div>
          <% end %>
        </figure>
      </div>

      <form id="photo-form" phx-submit="save_photos" phx-change="validate_photos">
        <div :if={@poses != []} class="adm-fit-states" role="radiogroup" aria-label="Pose">
          <label :for={{pose, i} <- Enum.with_index(@poses)} class="adm-fit-state">
            <input type="radio" name="pose" value={pose} checked={i == 0} />
            <span>{pose}</span>
          </label>
        </div>
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
            <.photo date={day.date} file={file} />
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

  attr :date, Date, required: true
  attr :file, :string, required: true

  defp photo(assigns) do
    ~H"""
    <img
      src={~p"/admin/fitness/photos/#{Date.to_iso8601(@date)}/#{@file}"}
      alt={"Progress photograph, #{@file}, #{@date}"}
      title={Calendar.strftime(@date, "%-d %b %Y")}
      loading="lazy"
    />
    """
  end

  defp measure_name("e1rm"), do: "e1RM (mean of the lifts)"
  defp measure_name("compliance"), do: "Prescribed sets done"
  defp measure_name(other), do: String.capitalize(other)

  defp signed(v) when v > 0, do: "+#{trim(v)}"
  defp signed(v), do: trim(v)

  defp trim(v) when is_float(v) and v == trunc(v), do: Integer.to_string(trunc(v))
  defp trim(v), do: to_string(v)

  defp unit("%"), do: "%"
  defp unit(""), do: ""
  defp unit(u), do: " " <> u

  defp photo_error(:too_large), do: "over 15 MB"
  defp photo_error(:not_accepted), do: "not a JPEG, PNG or WebP"
  defp photo_error(:too_many_files), do: "four at a time"
  defp photo_error(other), do: to_string(other)
end
