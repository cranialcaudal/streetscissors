defmodule WebWeb.AdminLive.LogsManager do
  use WebWeb, :live_view

  alias Web.Audio
  alias Web.Audio.Log
  import WebWeb.CmsStyles
  import WebWeb.LogsLive.Format, only: [format_duration: 1]

  @moduledoc """
  Admin for the captain's logs.

  Metadata comes first: a log is described (title, recording date, keywords)
  and the file is attached to that description, rather than the old hub's
  extension-sniffing drop zone that invented a title from the filename and
  left every log with `duration: 0` and no keywords at all.

  The upload is consumed on submit, not on drop, so a rejected form leaves
  nothing on disk.
  """

  @accept ~w(.mp3 .wav .m4a .webm)

  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Captain's Logs | Admin")
     |> assign(:accept, @accept)
     |> assign(:editing, nil)
     |> assign_new_form()
     |> load_logs()
     |> allow_upload(:audio, accept: @accept, max_entries: 1, max_file_size: 200_000_000)}
  end

  def handle_event("validate", %{"log" => params}, socket) do
    changeset =
      socket.assigns.editing
      |> log_or_new()
      |> Audio.change_log(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :form, to_form(changeset))}
  end

  def handle_event("save", %{"log" => params}, socket) do
    case socket.assigns.editing do
      nil -> create(socket, params)
      log -> update_existing(socket, log, params)
    end
  end

  def handle_event("edit", %{"id" => id}, socket) do
    log = Audio.get_log!(id)

    {:noreply,
     socket
     |> assign(:editing, log)
     |> assign(:form, to_form(Audio.change_log(log)))}
  end

  def handle_event("cancel_edit", _params, socket) do
    {:noreply, socket |> assign(:editing, nil) |> assign_new_form()}
  end

  def handle_event("toggle_published", %{"id" => id}, socket) do
    log = Audio.get_log!(id)
    {:ok, _log} = Audio.update_log(log, %{published: !log.published})
    {:noreply, load_logs(socket)}
  end

  def handle_event("delete", %{"id" => id}, socket) do
    id |> Audio.get_log!() |> Audio.delete_log()

    {:noreply,
     socket
     |> assign(:editing, nil)
     |> assign_new_form()
     |> load_logs()
     |> put_flash(:info, "Log purged.")}
  end

  # A new log needs its file; validate everything else before copying
  # anything into place so a rejected save cannot orphan an upload.
  defp create(socket, params) do
    probe = Audio.change_log(%Log{}, Map.put(params, "file_path", "pending"))

    cond do
      socket.assigns.uploads.audio.entries == [] ->
        {:noreply, put_flash(socket, :error, "Choose an audio file to upload.")}

      not probe.valid? ->
        {:noreply, assign(socket, :form, to_form(Map.put(probe, :action, :validate)))}

      true ->
        [file_path] =
          consume_uploaded_entries(socket, :audio, fn %{path: path}, entry ->
            {:ok, Audio.store_upload(path, entry.client_name)}
          end)

        case Audio.create_log(Map.put(params, "file_path", file_path)) do
          {:ok, log} ->
            {:noreply,
             socket
             |> assign_new_form()
             |> load_logs()
             |> put_flash(:info, "Logged “#{log.title}”.")}

          {:error, changeset} ->
            # Insert lost a race (a duplicate slug, say) — take the file back out.
            Audio.discard_upload(file_path)
            {:noreply, assign(socket, :form, to_form(changeset))}
        end
    end
  end

  # Editing keeps the existing recording unless a replacement was attached.
  defp update_existing(socket, log, params) do
    params =
      case consume_uploaded_entries(socket, :audio, fn %{path: path}, entry ->
             {:ok, Audio.store_upload(path, entry.client_name)}
           end) do
        [file_path] -> Map.put(params, "file_path", file_path)
        [] -> params
      end

    case Audio.update_log(log, params) do
      {:ok, updated} ->
        if params["file_path"], do: Audio.discard_upload(log.file_path)

        {:noreply,
         socket
         |> assign(:editing, nil)
         |> assign_new_form()
         |> load_logs()
         |> put_flash(:info, "Updated “#{updated.title}”.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :form, to_form(changeset))}
    end
  end

  defp log_or_new(nil), do: %Log{}
  defp log_or_new(%Log{} = log), do: log

  defp assign_new_form(socket) do
    changeset =
      Audio.change_log(%Log{recorded_on: Date.utc_today(), published: true, duration: 0})

    assign(socket, :form, to_form(changeset))
  end

  defp load_logs(socket) do
    assign(socket,
      logs: Audio.list_logs(),
      play_counts: Audio.get_all_play_counts()
    )
  end

  defp upload_error_message(:too_large), do: "File is too large (200MB max)."
  defp upload_error_message(:not_accepted), do: "That file type is not accepted."
  defp upload_error_message(:too_many_files), do: "One file at a time."
  defp upload_error_message(error), do: to_string(error)

  def render(assigns) do
    ~H"""
    <div class="cms">
      <h1 class="cms-title">Captain's Logs</h1>
      <p class="cms-lede">
        Spoken work. Published logs appear at
        <.link navigate={~p"/logs"} class="cms-link">/logs</.link>
        and are filterable by keyword.
      </p>

      <section class="cms-panel">
        <h2>{if @editing, do: "Edit log", else: "New log"}</h2>

        <.form
          for={@form}
          id="log-form"
          phx-change="validate"
          phx-submit="save"
          phx-hook="AudioDuration"
        >
          <.input
            field={@form[:title]}
            type="text"
            label="Title"
            class="cms-input"
            autocomplete="off"
            data-audio-title
          />
          <.input field={@form[:recorded_on]} type="date" label="Recorded on" class="cms-input" />
          <.input
            field={@form[:keywords]}
            type="text"
            label="Keywords"
            class="cms-input"
            autocomplete="off"
            placeholder="ferry, nyc, night-walk"
          />
          <p class="cms-hint">
            Comma separated. Normalized on save — “Bowling Green” files as “bowling-green”.
          </p>
          <.input field={@form[:description]} type="textarea" label="Notes" class="cms-input" />

          <div class="cms-field">
            <span class="label">Audio file</span>
            <div class="cms-drop" phx-drop-target={@uploads.audio.ref}>
              <div class="cms-drop-title">
                {if @editing, do: "REPLACE RECORDING", else: "ATTACH RECORDING"}
              </div>
              <p class="cms-hint">{Enum.join(@accept, ", ")}</p>
              <label class="cms-browse">
                CHOOSE FILE <.live_file_input upload={@uploads.audio} class="cms-file-input" />
              </label>

              <div :for={entry <- @uploads.audio.entries} class="cms-entry">
                {entry.client_name}
                <div class="cms-progress">
                  <div class="cms-progress-bar" style={"width: #{entry.progress}%"}></div>
                </div>
                <p :for={err <- upload_errors(@uploads.audio, entry)} class="cms-error">
                  {upload_error_message(err)}
                </p>
              </div>

              <p :for={err <- upload_errors(@uploads.audio)} class="cms-error">
                {upload_error_message(err)}
              </p>
            </div>
            <p :if={@editing} class="cms-hint">
              Leave empty to keep the current recording.
            </p>
          </div>
          <%!-- Filled in by the AudioDuration hook from the picked file's own
                metadata — which is why a log no longer ships with duration: 0. --%>
          <.input field={@form[:duration]} type="hidden" data-audio-duration />

          <.input field={@form[:published]} type="checkbox" label="Publish now" />

          <div class="cms-actions">
            <button type="submit" class="theme-btn">
              {if @editing, do: "Save changes", else: "Save log"}
            </button>
            <button :if={@editing} type="button" phx-click="cancel_edit" class="cms-link">
              Cancel
            </button>
          </div>
        </.form>
      </section>

      <section class="cms-panel">
        <h2>Archive ({length(@logs)})</h2>

        <div :if={@logs == []} class="cms-empty">No logs recorded yet.</div>

        <div class="cms-list">
          <div :for={log <- @logs} class="cms-item">
            <div class="cms-item-head">
              <div>
                <h3 class="cms-item-title">{log.title}</h3>
                <div class="cms-item-meta">
                  <span>{Calendar.strftime(log.recorded_on, "%Y-%m-%d")}</span>
                  <span :if={format_duration(log.duration)}>{format_duration(log.duration)}</span>
                  <span>{Map.get(@play_counts, log.id, 0)} plays</span>
                  <span>/logs/{log.slug}</span>
                </div>
                <div :if={Log.keyword_list(log) != []} class="cms-keywords">
                  <span :for={keyword <- Log.keyword_list(log)} class="cms-keyword">
                    {keyword}
                  </span>
                </div>
                <div :if={Log.keyword_list(log) == []} class="cms-keyword-missing">
                  ⚠ no keywords — this log cannot be filtered
                </div>
              </div>

              <div class="cms-item-actions">
                <button phx-click="edit" phx-value-id={log.id} class="cms-link">Edit</button>
                <button
                  phx-click="toggle_published"
                  phx-value-id={log.id}
                  class={[
                    "cms-link",
                    log.published && "cms-live",
                    !log.published && "cms-hidden-state"
                  ]}
                >
                  {if log.published, do: "LIVE", else: "HIDDEN"}
                </button>
                <button
                  phx-click="delete"
                  phx-value-id={log.id}
                  class="cms-link danger"
                  data-confirm="Purge this log and its audio file?"
                >
                  Delete
                </button>
              </div>
            </div>
          </div>
        </div>
      </section>

      <.cms_styles />
    </div>
    """
  end
end
