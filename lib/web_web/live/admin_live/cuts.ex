defmodule WebWeb.AdminLive.Cuts do
  @moduledoc """
  The cutting room's cuts (`/admin/cuts`): each a card with its first picture,
  its length, what it holds, whether it was rendered (and into which log) and
  when it was last changed, and a field in the head to begin a new one.

  The picture is whatever can be had without work: the poster of the log the
  cut was rendered into, else the first print on the timeline (the archive's
  own preview, sized), else the first take's proxy, which the browser draws a
  frame of by itself.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Logs.Log
  alias Web.Cuts
  alias Web.Cuts.Timeline
  alias Web.Negatives

  def mount(_params, session, socket) do
    if session["admin_user"] do
      cuts = Cuts.list_cuts()

      {:ok, assign(socket, page_title: "Cutting room | Admin", cuts: cuts, cards: cards(cuts))}
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

  # What each card shows, worked out once: the timeline laid out, its counts,
  # and the picture to draw.
  defp cards(cuts) do
    for cut <- cuts do
      plan = Timeline.layout(cut.timeline)

      %{
        cut: cut,
        length: plan.length,
        clips: length(plan.clips),
        titles: length(plan.titles),
        sounds: length(plan.sounds),
        picture: picture(cut, plan)
      }
    end
  end

  defp picture(cut, plan) do
    case cut.audio_log && Log.poster_url(cut.audio_log) do
      url when is_binary(url) -> {:image, url}
      _ -> Enum.find_value(plan.clips, &clip_picture(&1, cut))
    end
  end

  defp clip_picture(%{"kind" => "still", "frame" => frame}, _cut) do
    [roll, n] = String.split(frame, "/")
    {:image, Negatives.sized_url("/negatives/frame/#{roll}/#{n}", 480)}
  end

  defp clip_picture(%{"kind" => "take", "media" => id}, cut) do
    case Enum.find(cut.media, &(&1.id == id and &1.status == "ready" and &1.proxy)) do
      nil -> nil
      media -> {:frame, ~p"/admin/cuts/#{cut.id}/media/#{media.proxy}"}
    end
  end

  defp clip_picture(_clip, _cut), do: nil

  defp counted(1, one, _many), do: "1 #{one}"
  defp counted(n, _one, many), do: "#{n} #{many}"

  def render(assigns) do
    ~H"""
    <.page_head title="Cutting room">
      <:lede>
        Put a captain's log together from several takes, prints from the archive, titles and
        music. A cut is rendered into a log, which is published from Captain's Logs like any
        other, and can be cut again: its takes are kept.
      </:lede>
      <:actions>
        <form id="new-cut" phx-submit="new" class="adm-cut-new">
          <label for="new-cut-name" class="adm-sr">A working name for a new cut</label>
          <input
            id="new-cut-name"
            type="text"
            name="name"
            placeholder="Name a new cut"
            class="adm-input adm-input--prose"
            maxlength="120"
            autocomplete="off"
          />
          <button type="submit" class="adm-btn adm-btn--primary">
            <.icon name="hero-plus" class="size-4" /> New cut
          </button>
        </form>
      </:actions>
    </.page_head>

    <div :if={@cards == []} class="adm-cut-empty">
      <.icon name="hero-scissors" class="size-6" />
      <h2 class="adm-cut-empty-title">No cuts yet</h2>
      <p>
        A cut starts as an empty timeline. Add takes from the camera or the disk, prints from the
        archive, titles over them and music beneath, then render it into a log.
      </p>
      <button type="submit" form="new-cut" class="adm-btn adm-btn--primary">
        Start the first cut
      </button>
    </div>

    <div :if={@cards != []} class="st-cards adm-cut-cards">
      <.program_card
        :for={card <- @cards}
        program={:cuts}
        id={"cut-#{card.cut.id}"}
        title={card.cut.name}
        href={~p"/admin/cuts/#{card.cut.id}"}
      >
        <:picture>
          <img
            :if={match?({:image, _}, card.picture)}
            src={elem(card.picture, 1)}
            alt=""
            loading="lazy"
          />
          <video
            :if={match?({:frame, _}, card.picture)}
            src={elem(card.picture, 1) <> "#t=0.1"}
            preload="metadata"
            muted
            playsinline
            tabindex="-1"
            aria-hidden="true"
          ></video>
          <span :if={is_nil(card.picture)} class="adm-cut-card-blank st-bay">
            <.icon name="hero-film" class="size-6" />
            <span>Nothing on the timeline yet</span>
          </span>
          <span class="adm-cut-card-length st-bay" title="Length">
            <span class="adm-sr">Length </span>{clock(card.length)}
          </span>
        </:picture>

        <:state>
          {counted(card.clips, "clip", "clips")} · {counted(card.titles, "title", "titles")} · {counted(
            card.sounds,
            "sound",
            "sounds"
          )}
        </:state>
        <:state :if={card.cut.status == "rendering"} tone={:warn}>Rendering now</:state>
        <:state :if={card.cut.status == "failed"} tone={:fail}>The last render failed</:state>
        <:state
          :if={card.cut.status not in ["rendering", "failed"] and card.cut.audio_log}
          tone={:ok}
        >
          Rendered into
          <.link
            navigate={~p"/admin/logs#log-#{card.cut.audio_log.id}"}
            class="adm-cut-loglink"
          >
            the log of {Log.title(card.cut.audio_log)}
          </.link>
        </:state>
        <:state :if={card.cut.status not in ["rendering", "failed"] and is_nil(card.cut.audio_log)}>
          Not rendered yet
        </:state>
        <:state>
          <span class="adm-cut-changed" title={stamp(card.cut.updated_at)}>
            Changed {ago(card.cut.updated_at)}
          </span>
        </:state>

        <:actions>
          <.link
            navigate={~p"/admin/cuts/#{card.cut.id}"}
            class="adm-btn adm-btn--small adm-btn--primary"
          >
            Open the cut
          </.link>
        </:actions>
      </.program_card>
    </div>
    """
  end

  @doc false
  def clock(ms) do
    seconds = div(ms, 1000)
    "#{div(seconds, 60)}:#{String.pad_leading(to_string(rem(seconds, 60)), 2, "0")}"
  end
end
