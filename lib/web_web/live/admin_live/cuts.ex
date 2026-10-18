defmodule WebWeb.AdminLive.Cuts do
  @moduledoc """
  The cutting room's cuts (`/admin/cuts`): each with its length, what it holds
  and the log it was rendered into, and a field to begin a new one.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Audio.Log
  alias Web.Cuts
  alias Web.Cuts.Timeline

  def mount(_params, session, socket) do
    if session["admin_user"] do
      {:ok, assign(socket, page_title: "Cutting room | Admin", cuts: Cuts.list_cuts())}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  def handle_event("new", %{"name" => name}, socket) do
    name = if String.trim(name) == "", do: "Untitled cut", else: name

    case Cuts.create_cut(name) do
      {:ok, cut} -> {:noreply, push_navigate(socket, to: ~p"/admin/cuts/#{cut.id}")}
      {:error, _} -> {:noreply, put_flash(socket, :error, "That name will not do.")}
    end
  end

  def render(assigns) do
    ~H"""
    <.page_head slug="Write / Cutting room" title="Cutting room">
      <:lede>
        A captain's log put together from several takes, prints from the archive, titles and
        music. A cut is rendered into a log, which is published from Captain's Logs like any
        other, and can be cut again: its takes are kept.
      </:lede>
    </.page_head>

    <.panel title="Begin a cut">
      <form id="new-cut" phx-submit="new" class="adm-form-row">
        <input type="text" name="name" placeholder="A working name" class="adm-input" maxlength="120" />
        <button type="submit" class="adm-btn adm-btn--primary">Begin</button>
      </form>
    </.panel>

    <.panel title="Cuts" count={length(@cuts)}>
      <.empty :if={@cuts == []}>No cuts yet.</.empty>
      <ul :if={@cuts != []} class="adm-cut-list">
        <li :for={cut <- @cuts} id={"cut-#{cut.id}"}>
          <.link navigate={~p"/admin/cuts/#{cut.id}"} class="adm-cut-row">
            <span class="adm-cut-row-name">{cut.name}</span>
            <span class="adm-cut-row-figures">
              {clock(Timeline.layout(cut.timeline).length)} · {length(cut.timeline["clips"] || [])} clips · {length(
                cut.media
              )} in the bin
            </span>
            <span class="adm-cut-row-state">
              <.pill :if={cut.status == "rendering"} tone="held">rendering</.pill>
              <.pill :if={cut.status == "failed"} tone="failed">render failed</.pill>
              <span :if={cut.audio_log}>{Log.title(cut.audio_log)}</span>
            </span>
          </.link>
        </li>
      </ul>
    </.panel>
    """
  end

  @doc false
  def clock(ms) do
    seconds = div(ms, 1000)
    "#{div(seconds, 60)}:#{String.pad_leading(to_string(rem(seconds, 60)), 2, "0")}"
  end
end
