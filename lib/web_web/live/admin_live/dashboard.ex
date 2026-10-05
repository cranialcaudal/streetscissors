defmodule WebWeb.AdminLive.Dashboard do
  @moduledoc """
  The admin's front page: what needs you, what is on file, who came by, and
  whether the machine is looking after itself.

  It used to be four unrelated screens stacked into one — traffic, the
  contact inbox, the subscriber table and a Spotify setting. Those now live
  on their own pages (Inbox, Newsletter, Settings), and this one only points
  at them: every row in "Needs you" is a link to the page where the thing
  gets done, and a row appears only when there is something to do.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.{Analytics, Audio, Blog, Contact, General, Newsletter, Rides, SystemStatus}

  def mount(_params, session, socket) do
    if session["admin_user"] do
      {:ok, socket |> assign(page_title: "Overview | Admin") |> load()}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  # The checks Web.Monitor makes on a schedule, as opposed to on each mount.
  @monitored [:certificate, :front_door, :dns, :disk, :units]

  defp load(socket) do
    posts = Blog.list_posts()
    logs = Audio.count_by_status()
    messages = Contact.count_by_status()
    checks = SystemStatus.checks()
    {views_window, trend} = Analytics.get_biweekly_trends(28)

    assign(socket,
      queue:
        queue(%{
          held: General.count_held_guestbook_entries(),
          citations: Web.Webmentions.count_held(),
          attention: Map.get(messages, "attention", 0),
          inbox: Map.get(messages, "inbox", 0),
          failed_logs: Map.get(logs, "failed", 0),
          encoding: Map.get(logs, "pending", 0) + Map.get(logs, "processing", 0),
          unkeyworded: Enum.count(posts, &(&1.keywords == [])),
          checks: checks
        }),
      on_file: %{
        posts: length(posts),
        logs: logs |> Map.drop(["draft"]) |> Map.values() |> Enum.sum(),
        log_drafts: Map.get(logs, "draft", 0),
        subscribers: length(Newsletter.list_active_emails()),
        activities: length(Rides.list_rides()),
        signatures: General.count_guestbook_entries()
      },
      visitors_today: Analytics.count_unique_visitors_today() || 0,
      views_today: Analytics.count_hits_today() || 0,
      views_window: views_window,
      trend: trend,
      trend_max: trend |> Enum.map(fn {_, _, count} -> count end) |> Enum.max(fn -> 0 end),
      top_pages: Analytics.top_pages(10),
      checks: checks
    )
  end

  # One row per kind of waiting thing, in the order they should be dealt
  # with: people first, then broken things, then housekeeping.
  defp queue(n) do
    check = fn key -> Enum.find(n.checks, &(&1.key == key)) end

    people = [
      n.held > 0 &&
        row(
          n.held,
          plural(n.held, "signature waits", "signatures wait") <> " for approval",
          ~p"/admin/guestbook?show=held"
        ),
      n.attention > 0 &&
        row(
          n.attention,
          plural(n.attention, "message is", "messages are") <> " flagged",
          ~p"/admin/inbox?box=attention"
        ),
      n.inbox > 0 &&
        row(
          n.inbox,
          plural(n.inbox, "message", "messages") <> " in the inbox",
          ~p"/admin/inbox?box=inbox"
        ),
      n.citations > 0 &&
        row(
          n.citations,
          plural(n.citations, "site cites", "sites cite") <> " a piece, awaiting approval",
          ~p"/admin/citations?show=held"
        )
    ]

    broken = [
      n.failed_logs > 0 &&
        row(
          n.failed_logs,
          plural(n.failed_logs, "log", "logs") <> " failed to transcode",
          ~p"/admin/logs",
          :fail
        ),
      check.(:komoot).state == :fail &&
        row("!", "The last Komoot sync failed", ~p"/admin/rides", :fail),
      check.(:ride_privacy).state == :fail &&
        row("!", "Ride privacy: " <> check.(:ride_privacy).detail, ~p"/admin/rides", :fail),
      check.(:mail).state == :fail && row("!", check.(:mail).detail, ~p"/admin/newsletter", :fail),
      check.(:database).state in [:warn, :fail] &&
        row("!", "The database snapshot is overdue", "#system", :fail),
      check.(:content).state in [:warn, :fail] &&
        row("!", "The content backup is overdue", "#system", :fail),
      check.(:restore).state == :fail &&
        row("!", "The restore drill failed: " <> check.(:restore).detail, "#system", :fail)
    ]

    # What the monitor's last pass found failing: each says what is wrong.
    faults =
      for %{key: key, state: :fail, label: label, detail: detail} <- n.checks,
          key in @monitored,
          do: row("!", "#{label}: #{detail}", "#system", :fail)

    housekeeping = [
      check.(:alerts).state == :warn &&
        row("!", "Faults have nobody to write to yet: set an address", ~p"/admin/settings"),
      n.encoding > 0 &&
        row(
          n.encoding,
          plural(n.encoding, "log is", "logs are") <> " transcoding now",
          ~p"/admin/logs",
          :info
        ),
      n.unkeyworded > 0 &&
        row(
          n.unkeyworded,
          plural(n.unkeyworded, "post has", "posts have") <> " no keywords",
          ~p"/admin/blog?filter=missing"
        )
    ]

    Enum.filter(people ++ broken ++ faults ++ housekeeping, & &1)
  end

  defp row(count, text, href, tone \\ :held),
    do: %{count: count, text: text, href: href, tone: tone}

  # The count sits in its own column, so the text carries only the noun.
  defp plural(1, one, _many), do: one
  defp plural(_n, _one, many), do: many

  def render(assigns) do
    ~H"""
    <.page_head slug="Overview" title="The composing room">
      <:lede>{today_line()}</:lede>
    </.page_head>

    <div class="adm-split">
      <.panel title="Needs you" count={length(@queue)} id="needs-you">
        <p :if={@queue == []} class="adm-clear">Nothing needs you.</p>
        <ul :if={@queue != []} class="adm-queue">
          <li :for={item <- @queue} class={["adm-queue-item", "adm-queue--#{item.tone}"]}>
            <.link
              navigate={!String.starts_with?(item.href, "#") && item.href}
              href={String.starts_with?(item.href, "#") && item.href}
              class="adm-queue-link"
            >
              <span class="adm-queue-count">{item.count}</span>
              <span class="adm-queue-text">{item.text}</span>
              <span class="adm-queue-go" aria-hidden="true">Open →</span>
            </.link>
          </li>
        </ul>
      </.panel>

      <.panel title="The machine" id="system">
        <ul class="adm-status">
          <li :for={check <- @checks}>
            <span class={["adm-status-dot", status_class(check.state)]} aria-hidden="true"></span>
            <span class="adm-status-name">{check.label}</span>
            <span class="adm-status-detail">
              {check.detail}<span :if={check.at}> · {ago(check.at)}</span>
            </span>
          </li>
        </ul>
      </.panel>
    </div>

    <.panel title="On file">
      <div class="adm-stats">
        <.stat value={@on_file.posts} label="Posts" href={~p"/admin/blog"} />
        <.stat
          value={@on_file.logs}
          label="Captain's logs"
          note={@on_file.log_drafts > 0 && "#{@on_file.log_drafts} unpublished"}
          href={~p"/admin/logs"}
        />
        <.stat value={@on_file.subscribers} label="Subscribers" href={~p"/admin/newsletter"} />
        <.stat value={@on_file.activities} label="Activities" href={~p"/admin/rides"} />
        <.stat value={@on_file.signatures} label="Signatures" href={~p"/admin/guestbook"} />
      </div>
    </.panel>

    <.panel title="Traffic">
      <div class="adm-stats">
        <.stat
          value={@visitors_today}
          label="Visitors today"
          note="distinct, since midnight"
          tone="act"
        />
        <.stat value={@views_today} label="Views today" note="every load, reloads included" />
        <.stat value={@views_window} label="Views, 56 weeks" note="28 fortnights, below" />
      </div>

      <div class="adm-trend" role="img" aria-label="Views per fortnight over the last 56 weeks">
        <span
          :for={{{start, _end, count}, index} <- Enum.with_index(@trend)}
          class={["adm-trend-bar", index == length(@trend) - 1 && "is-current"]}
          style={"--h: #{bar_height(count, @trend_max)}%"}
          data-label={"#{Calendar.strftime(start, "%b %d")} · #{count}"}
        >
        </span>
      </div>
      <div :if={@trend != []} class="adm-trend-axis">
        <span>{@trend |> List.first() |> elem(0) |> Calendar.strftime("%b %Y")}</span>
        <span>this fortnight</span>
      </div>

      <h3 class="adm-group-title adm-group-title--spaced">Most viewed, all time</h3>
      <.empty :if={@top_pages == []}>No views recorded yet.</.empty>
      <ol :if={@top_pages != []} class="adm-ranked">
        <li :for={{path, count} <- @top_pages}>
          <span class="adm-ranked-path">{path}</span>
          <span class="adm-ranked-count">{count}</span>
        </li>
      </ol>
    </.panel>
    """
  end

  defp bar_height(_count, 0), do: 2
  defp bar_height(count, max), do: max(round(count / max * 100), 2)

  defp status_class(:ok), do: "adm-status-dot--ok"
  defp status_class(:warn), do: "adm-status-dot--warn"
  defp status_class(:fail), do: "adm-status-dot--fail"
  defp status_class(:off), do: nil

  defp today_line do
    Calendar.strftime(Web.Clock.local_today(DateTime.utc_now()), "%A, %B %-d")
  end
end
