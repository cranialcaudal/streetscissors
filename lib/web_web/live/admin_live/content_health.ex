defmodule WebWeb.AdminLive.ContentHealth do
  @moduledoc """
  The report `Web.ContentHealth` makes, as a page: what in the vault points at
  nothing, what is missing its description or keywords, what nothing uses, and
  which rolls are not showing their marks.

  The report renders every page it checks, so it is built with `start_async`
  rather than in `mount/3`: the page is on screen at once and says it is
  reading. Nothing here repairs anything. Each row says what is wrong and,
  where there is one, links to the place it is put right.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.ContentHealth

  def mount(_params, session, socket) do
    if session["admin_user"] do
      {:ok, socket |> assign(page_title: "Content health | Admin", report: nil) |> check()}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  def handle_event("check", _params, socket), do: {:noreply, check(socket)}

  def handle_async(:report, {:ok, report}, socket) do
    {:noreply, assign(socket, report: report, checking: false)}
  end

  def handle_async(:report, {:exit, reason}, socket) do
    {:noreply,
     socket
     |> assign(:checking, false)
     |> put_flash(:error, "The check did not finish: #{inspect(reason)}")}
  end

  # Only once the socket is connected: the first, static render would
  # otherwise start a report that is thrown away with it.
  defp check(socket) do
    if connected?(socket) do
      socket |> assign(:checking, true) |> start_async(:report, &ContentHealth.report/0)
    else
      assign(socket, :checking, true)
    end
  end

  defp missing_words(missing) do
    missing
    |> Enum.map(fn
      :description -> "no description"
      :keywords -> "no keywords"
    end)
    |> Enum.join(", ")
  end

  defp kind_label(:image), do: "image"
  defp kind_label(:module), do: "module"
  defp kind_label(:day), do: "day"

  def render(assigns) do
    ~H"""
    <.page_head slug="Write / Content health" title="Content health">
      <:lede>
        The vault read the way the site reads it: every link asked of the site itself, every
        embed looked up, every file accounted for. Nothing here changes anything.
      </:lede>
      <:actions>
        <button type="button" phx-click="check" class="adm-btn" disabled={@checking}>
          <.icon name="hero-arrow-path" class="size-4" />
          {if @checking, do: "Reading…", else: "Check again"}
        </button>
      </:actions>
    </.page_head>

    <.empty :if={is_nil(@report)}>Reading the vault…</.empty>

    <div :if={@report} id="health-report">
      <p class="adm-help" id="health-summary">
        {case ContentHealth.count(@report) do
          0 -> "Nothing needs fixing."
          1 -> "1 thing to look at."
          n -> "#{n} things to look at."
        end} Checked {ago(@report.checked_at)}. {@report.external} links to other sites were counted and not followed.
      </p>

      <.panel title="Links that go nowhere" count={length(@report.broken)} id="health-broken">
        <.rows id="broken" rows={@report.broken}>
          <:col :let={row} label="In" class="adm-cell-title">
            <.link :if={row.source.edit} navigate={row.source.edit} class="adm-link">
              {row.source.label}
            </.link>
            <span :if={!row.source.edit}>{row.source.label}</span>
          </:col>
          <:col :let={row} label="Points at"><code>{row.target}</code></:col>
          <:col :let={row} label="Problem">{row.problem}</:col>
          <:empty>Every link on the site leads somewhere.</:empty>
        </.rows>
      </.panel>

      <.panel title="Embeds that point at nothing" count={length(@report.embeds)} id="health-embeds">
        <.rows id="embeds" rows={@report.embeds}>
          <:col :let={row} label="In" class="adm-cell-title">
            <.link :if={row.source.edit} navigate={row.source.edit} class="adm-link">
              {row.source.label}
            </.link>
            <span :if={!row.source.edit}>{row.source.label}</span>
          </:col>
          <:col :let={row} label="Embed"><code>{row.target}</code></:col>
          <:col label="Problem">no such roll, frame, ride or figure, so it shows as this text</:col>
          <:empty>Every embed found what it names.</:empty>
        </.rows>
      </.panel>

      <.panel title="Posts missing their particulars" count={length(@report.posts)} id="health-posts">
        <.rows id="undescribed" rows={@report.posts}>
          <:col :let={row} label="Post" class="adm-cell-title">
            <.link navigate={~p"/admin/blog/#{row.post.slug}/edit"} class="adm-link">
              {row.post.title}
            </.link>
          </:col>
          <:col :let={row} label="Missing">{missing_words(row.missing)}</:col>
          <:empty>Every published post has a description and keywords.</:empty>
        </.rows>
        <p class="adm-help">
          Without a description the first paragraph stands in on the index, in feeds and when the
          post is shared. Without keywords no filter reaches it.
        </p>
      </.panel>

      <.panel title="Files nothing uses" count={length(@report.unused)} id="health-unused">
        <.rows id="unused" rows={@report.unused}>
          <:col :let={row} label="Kind">{kind_label(row.kind)}</:col>
          <:col :let={row} label="File" class="adm-cell-title"><code>{row.name}</code></:col>
          <:col :let={row} label="Why it is listed">{row.detail}</:col>
          <:empty>Everything on disk is used by something.</:empty>
        </.rows>
      </.panel>

      <.panel
        title="Rolls not showing their marks"
        count={length(@report.archive)}
        id="health-archive"
      >
        <.rows id="archive" rows={@report.archive}>
          <:col :let={row} label="Roll" class="adm-cell-title">
            <.link href={~p"/negatives/roll/#{row.roll}"} target="_blank" class="adm-link">
              {row.roll}
            </.link>
          </:col>
          <:col :let={row} label="Prints">
            {row.prints}
            <.pill :if={row.prints > 0} tone="held">rings missing</.pill>
          </:col>
          <:col :let={row} label="Why">{row.reason}</:col>
          <:col :let={row} label="Fix"><code>{row.fix}</code></:col>
          <:empty>Every roll's marks can be drawn.</:empty>
        </.rows>
        <p class="adm-help">
          A printed frame is circled on its sheet only when the roll's analysis still describes it.
          A roll with no prints has nothing to circle, so it matters only once one is made.
        </p>
      </.panel>
    </div>
    """
  end
end
