defmodule WebWeb.AdminLive.Dashboard do
  @moduledoc """
  The studio floor, the admin's front page: what needs you, where each of the
  site's programs stands, and the instruments read in passing.

  **What needs you** is a few calm lines, each a link to the page where the
  thing gets done, and there is a line only when there is something to do.

  **The programs are the point.** A card each for the Darkroom, the Cutting
  room (with the Captain's Logs), Writing, Training and Mail
  (`WebWeb.AdminComponents.program_card/1`), each showing its own state and
  work, a picture where there is one, and its main actions. What a card says
  is gathered by `Web.Studio`.

  **Figures are passive**: the machine's health collapsed into one item (or
  each check that is warn or fail as its own), the counts on file and today's
  traffic sit in one status strip. Under it, closed, are the machine's full
  checks and the most viewed pages.

  **It stays cheap.** The mount reads stored state only (the monitor's last
  pass, files, a few small queries) and never probes. The one expensive read,
  the traffic of the last 56 weeks, runs after the page is on screen
  (`assign_async/3`), so it costs the first paint nothing.

  ## How this file is laid out

  1. **Gathering the floor** (`mount/3`): everything the page shows,
     from what is already stored. Nothing is probed or computed on the spot,
     and the slow year of traffic arrives afterwards (`assign_async`).
  2. **The page itself** (`render/1`): "Needs you" first, then a card per
     program, then the status strip.
  3. **The programs**: one function per program's card.
  4. **The status strip**: the quiet line of figures at the foot.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Phoenix.LiveView.JS
  alias Web.{Analytics, Rides, Studio, SystemStatus}

  # ── Gathering the floor (from stored state only) ──────────────────────────

  def mount(_params, session, socket) do
    if session["admin_user"] do
      {:ok, socket |> assign(page_title: "Studio | Admin") |> load() |> load_traffic()}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  # The checks Web.Monitor makes on a schedule, as opposed to on each mount.
  @monitored [:certificate, :front_door, :dns, :disk, :units]

  defp load(socket) do
    floor = Studio.floor(counts: socket.assigns[:admin_counts])
    checks = SystemStatus.checks()

    assign(socket,
      floor: floor,
      queue: queue(floor, checks),
      checks: checks,
      monitored?: Enum.any?(checks, &(&1.key in @monitored))
    )
  end

  # Traffic reads every hit of the last 56 weeks, so it is left until the
  # page is up. Nothing in the strip or the details waits on it.
  defp load_traffic(socket) do
    assign_async(socket, :traffic, fn ->
      {views_window, trend} = Analytics.get_biweekly_trends(28)

      {:ok,
       %{
         traffic: %{
           visitors: Analytics.count_unique_visitors_today() || 0,
           views: Analytics.count_hits_today() || 0,
           window: views_window,
           trend: trend,
           trend_max: trend |> Enum.map(fn {_, _, count} -> count end) |> Enum.max(fn -> 0 end),
           top_pages: Analytics.top_pages(10)
         }
       }}
    end)
  end

  # One line per kind of waiting thing, in the order they should be dealt
  # with: people first, then broken things, then housekeeping. A tone is only
  # given to what has gone wrong: `:fail` for a real failure, `:warn` for
  # something overdue or unset; the rest is just waiting.
  defp queue(%{mail: mail, cuts: cuts, writing: writing}, checks) do
    check = fn key -> Enum.find(checks, &(&1.key == key)) end
    inbox = mail.open - mail.flagged

    people = [
      mail.held > 0 &&
        row(
          "#{mail.held} " <>
            plural(mail.held, "signature waits", "signatures wait") <> " for approval",
          ~p"/admin/guestbook?show=held"
        ),
      mail.flagged > 0 &&
        row(
          "#{mail.flagged} " <> plural(mail.flagged, "message is", "messages are") <> " flagged",
          ~p"/admin/inbox?box=attention"
        ),
      inbox > 0 &&
        row(
          "#{inbox} " <> plural(inbox, "message", "messages") <> " in the inbox",
          ~p"/admin/inbox?box=inbox"
        ),
      mail.citations > 0 &&
        row(
          "#{mail.citations} " <>
            plural(mail.citations, "site cites", "sites cite") <> " a piece, awaiting approval",
          ~p"/admin/citations?show=held"
        )
    ]

    broken = [
      cuts.logs.failed > 0 &&
        row(
          "#{cuts.logs.failed} " <>
            plural(cuts.logs.failed, "log", "logs") <> " failed to transcode",
          ~p"/admin/logs",
          :fail
        ),
      check.(:komoot).state == :fail &&
        row("The last Komoot sync failed", ~p"/admin/rides", :fail),
      check.(:ride_privacy).state == :fail &&
        row("Ride privacy: " <> check.(:ride_privacy).detail, ~p"/admin/rides", :fail),
      check.(:mail).state == :fail && row(check.(:mail).detail, ~p"/admin/newsletter", :fail),
      check.(:database).state in [:warn, :fail] &&
        row("The database snapshot is overdue", "#system", check.(:database).state),
      check.(:content).state in [:warn, :fail] &&
        row("The content backup is overdue", "#system", check.(:content).state),
      check.(:restore).state == :fail &&
        row("The restore drill failed: " <> check.(:restore).detail, "#system", :fail)
    ]

    # What the monitor's last pass found failing: each says what is wrong.
    faults =
      for %{key: key, state: :fail, label: label, detail: detail} <- checks,
          key in @monitored,
          do: row("#{label}: #{detail}", "#system", :fail)

    housekeeping = [
      check.(:alerts).state == :warn &&
        row("Faults have nobody to write to yet: set an address", ~p"/admin/settings", :warn),
      cuts.logs.transcoding > 0 &&
        row(
          "#{cuts.logs.transcoding} " <>
            plural(cuts.logs.transcoding, "log is", "logs are") <> " transcoding now",
          ~p"/admin/logs"
        ),
      writing.no_keywords > 0 &&
        row(
          "#{writing.no_keywords} " <>
            plural(writing.no_keywords, "post has", "posts have") <> " no keywords",
          ~p"/admin/blog?filter=missing"
        )
    ]

    Enum.filter(people ++ broken ++ faults ++ housekeeping, & &1)
  end

  defp row(text, href, tone \\ nil), do: %{text: text, href: href, tone: tone}

  defp plural(1, one, _many), do: one
  defp plural(_n, _one, many), do: many

  # ── The page itself (render) ──────────────────────────────────────────────

  def render(assigns) do
    ~H"""
    <.page_head title="The studio">
      <:lede>{today_line()}<span :if={@queue == []}>. Nothing needs you.</span></:lede>
    </.page_head>

    <section :if={@queue != []} id="needs-you" class="ov-needs" aria-labelledby="needs-you-title">
      <h2 id="needs-you-title" class="ov-needs-title">Needs you</h2>
      <ul class="ov-needs-list">
        <li :for={item <- @queue}>
          <.link
            navigate={!String.starts_with?(item.href, "#") && item.href}
            href={String.starts_with?(item.href, "#") && item.href}
            phx-click={String.starts_with?(item.href, "#") && open_machine()}
            class={["ov-need", item.tone && "ov-need--#{item.tone}"]}
          >
            <span class="ov-need-dot" aria-hidden="true"></span>
            <span class="ov-need-text">{item.text}</span>
            <span class="ov-need-go">Open</span>
          </.link>
        </li>
      </ul>
    </section>

    <div class="st-cards ov-floor">
      <.darkroom_card d={@floor.darkroom} />
      <.cutting_card c={@floor.cuts} />
      <.writing_card w={@floor.writing} />
      <.training_card t={@floor.training} />
      <.mail_card m={@floor.mail} />
    </div>

    <.status_strip
      id="figures"
      label="The machine, the counts on file and today's traffic"
      items={strip_items(@checks, @monitored?, @floor.on_file, @traffic)}
    />

    <details id="machine" class="ov-details">
      <summary>The machine in full</summary>
      <ul id="system" class="adm-status">
        <li :for={check <- @checks}>
          <span class={["adm-status-dot", status_class(check.state)]} aria-hidden="true"></span>
          <span class="adm-status-name">{check.label}</span>
          <span class="adm-status-detail">
            {check.detail}<span :if={check.at}> · {ago(check.at)}</span>
          </span>
        </li>
      </ul>
    </details>

    <details id="most-viewed" class="ov-details">
      <summary>Most viewed</summary>
      <.async_result :let={traffic} assign={@traffic}>
        <:loading>
          <p class="ov-quiet">Reading the traffic.</p>
        </:loading>
        <:failed>
          <p class="ov-quiet">The traffic could not be read just now.</p>
        </:failed>

        <div
          :if={traffic.trend != []}
          class="ov-trend"
          role="img"
          aria-label="Views per fortnight over the last 56 weeks"
        >
          <span
            :for={{{start, _end, count}, index} <- Enum.with_index(traffic.trend)}
            class={["ov-trend-bar", index == length(traffic.trend) - 1 && "is-current"]}
            style={"--h: #{bar_height(count, traffic.trend_max)}%"}
            title={"#{Calendar.strftime(start, "%b %-d")}: #{count} views"}
          >
          </span>
        </div>
        <p :if={traffic.trend != []} class="ov-trend-axis">
          <span>{traffic.trend |> List.first() |> elem(0) |> Calendar.strftime("%b %Y")}</span>
          <span>this fortnight</span>
        </p>

        <.empty :if={traffic.top_pages == []}>No views recorded yet.</.empty>
        <ol :if={traffic.top_pages != []} class="ov-ranked">
          <li :for={{path, count} <- traffic.top_pages}>
            <span class="ov-ranked-path">{path}</span>
            <span class="ov-ranked-count">{count}</span>
          </li>
        </ol>
      </.async_result>
    </details>
    """
  end

  # A line that points at the machine's checks opens them as well as scrolling
  # there; they are closed until asked for.
  defp open_machine, do: JS.set_attribute({"open", ""}, to: "#machine")

  # ── The programs ──────────────────────────────────────────────────────

  # The lines of a card are sentences with their figures in the data face.
  # A figure is made by `num/3` and set inside `{}`, never as a component of
  # its own, so no stray space is left before the comma that follows it.

  attr :d, :map, required: true

  defp darkroom_card(assigns) do
    d = assigns.d
    prints = if d.recent != [], do: d.recent, else: List.wrap(d.newest_print)

    quiet? =
      is_nil(d.bench) and d.waiting == [] and d.edited == 0 and prints == [] and d.choices == 0

    assigns = assign(assigns, prints: prints, quiet?: quiet?)

    ~H"""
    <.program_card
      id="program-darkroom"
      program={:darkroom}
      title="Darkroom"
      href={~p"/admin/scanner"}
      class={length(@prints) > 1 && "ov-strip-#{length(@prints)}"}
    >
      <:picture :if={@prints != []}>
        <div class={["ov-prints", "ov-prints--#{length(@prints)}"]}>
          <img
            :for={print <- @prints}
            src={print.url}
            alt={"Frame #{print.frame} of roll #{print.roll}"}
            loading="lazy"
            decoding="async"
          />
        </div>
      </:picture>
      <:state :if={@quiet?}>
        Nothing on the bench and no prints yet. Scan a roll to begin.
      </:state>
      <:state :if={!@quiet? and @d.bench}>
        Roll <b class="ov-num">{@d.bench.roll}</b>
        on the bench, {num(@d.bench.strips, "strip", "strips")}{owed(@d.bench.owed)}
      </:state>
      <:state :if={!@quiet? and is_nil(@d.bench)}>Nothing on the bench</:state>
      <:state :if={@d.waiting != []}>
        {num(length(@d.waiting), "roll", "rolls")} scanned, waiting to be published
      </:state>
      <:state :if={!@quiet? and @d.edited > 0}>
        {num(@d.edited, "print", "prints")} edited{last_edit(@d.recent)}
      </:state>
      <:state :if={!@quiet? and @d.edited == 0}>No print edited yet</:state>
      <:state :if={@d.recent != []}>
        In the picture, newest edit first: {print_names(@d.recent)}
      </:state>
      <:state :if={@d.newest_print}>
        In the picture, the newest print: {print_name(@d.newest_print)}
      </:state>
      <:state :if={!@quiet? and @d.choices > 0}>
        {num(@d.choices, "Taste choice", "Taste choices")} kept
      </:state>
      <:state :if={!@quiet? and @d.choices == 0}>No Taste choices yet</:state>
      <:actions>
        <.link navigate={~p"/admin/scanner"} class="adm-btn adm-btn--primary">Scan</.link>
        <.link navigate={~p"/admin/darkroom"} class="adm-btn">Prints</.link>
        <.link navigate={~p"/admin/darkroom/taste"} class="adm-btn">Taste</.link>
      </:actions>
    </.program_card>
    """
  end

  defp owed(0), do: ""
  defp owed(n), do: ", #{n} #{plural(n, "single", "singles")} still to scan"

  defp last_edit([]), do: ""
  defp last_edit([newest | _]), do: ", the last #{ago(newest.at)}"

  attr :c, :map, required: true

  defp cutting_card(assigns) do
    c = assigns.c
    quiet? = c.total == 0 and is_nil(c.newest_log)
    assigns = assign(assigns, quiet?: quiet?, logs: c.logs, last_cut: List.first(c.cuts))

    ~H"""
    <.program_card id="program-cuts" program={:cuts} title="Cutting room" href={~p"/admin/cuts"}>
      <:picture :if={@c.newest_log && @c.newest_log.poster}>
        <img src={@c.newest_log.poster} alt="" loading="lazy" decoding="async" />
      </:picture>
      <:state :if={@quiet?}>
        No cuts and no logs yet. Record a log, or begin a cut.
      </:state>
      <:state :for={cut <- @c.cuts} tone={cut_tone(cut)}>
        <span class="ov-words">{cut.name}</span>, {cut_figures(cut)} {cut_state(cut)}
      </:state>
      <:state :if={@c.total > length(@c.cuts)}>
        and {num(@c.total - length(@c.cuts), "other cut", "other cuts")}
      </:state>
      <:state :if={@logs.unpublished > 0}>
        {num(@logs.unpublished, "log", "logs")} ready, not yet published
      </:state>
      <:state :if={@logs.transcoding > 0}>
        {num(@logs.transcoding, "log", "logs")} transcoding now
      </:state>
      <:state :if={@logs.failed > 0} tone={:fail}>
        {num(@logs.failed, "log", "logs")} failed to transcode
      </:state>
      <:state :if={@c.newest_log}>
        Newest log {short_date(@c.newest_log.recorded_on)}{newest_caption(@c.newest_log)}
      </:state>
      <:actions>
        <.link navigate={~p"/admin/logs"} class="adm-btn adm-btn--primary">Record a log</.link>
        <.link :if={@last_cut} navigate={~p"/admin/cuts/#{@last_cut.id}"} class="adm-btn">
          Open the last cut
        </.link>
        <.link :if={!@last_cut} navigate={~p"/admin/cuts#new-cut"} class="adm-btn">New cut</.link>
      </:actions>
    </.program_card>
    """
  end

  defp cut_tone(%{status: "failed"}), do: :fail
  defp cut_tone(_cut), do: nil

  # `0:42, 3 clips,` for a cut with something on its timeline.
  defp cut_figures(%{clips: 0}), do: ""

  defp cut_figures(cut) do
    assigns = %{length: clock(cut.length_ms), clips: num(cut.clips, "clip", "clips")}

    ~H'<b class="ov-num">{@length}</b>, {@clips},'
  end

  defp cut_state(%{status: "rendering"}), do: "rendering now"
  defp cut_state(%{status: "failed"}), do: "the render failed"
  defp cut_state(%{rendered?: true, log: log}) when is_binary(log), do: "rendered as log #{log}"
  defp cut_state(%{rendered?: true}), do: "rendered"
  defp cut_state(%{clips: 0}), do: "nothing on the timeline yet"
  defp cut_state(_cut), do: "not rendered yet"

  defp newest_caption(%{caption: caption}) when caption in [nil, ""], do: ""

  defp newest_caption(%{caption: caption}) do
    assigns = %{caption: caption}
    ~H', <span class="ov-words">{@caption}</span>'
  end

  attr :w, :map, required: true

  defp writing_card(assigns) do
    ~H"""
    <.program_card id="program-writing" program={:writing} title="Writing" href={~p"/admin/blog"}>
      <:state :if={@w.published + @w.drafts == 0}>
        No posts yet. Start the first one.
      </:state>
      <:state :if={@w.drafts > 0}>
        {num(@w.drafts, "draft", "drafts")}, the newest
        <.link navigate={~p"/admin/blog/#{@w.newest_draft.slug}/edit"} class="ov-words">
          {@w.newest_draft.title}
        </.link>
      </:state>
      <:state :if={@w.published > 0 and @w.drafts == 0}>No drafts</:state>
      <:state :if={@w.last}>
        Last published <span class="ov-words">{@w.last.title}</span>, {short_date(@w.last.date)}
      </:state>
      <:state :if={@w.last && @w.no_description + @w.no_keywords == 0}>
        Every published post has a description and keywords
      </:state>
      <:state :if={@w.no_description > 0}>
        {num(@w.no_description, "post has", "posts have")} no description
      </:state>
      <:state :if={@w.no_keywords > 0}>
        <.link navigate={~p"/admin/blog?filter=missing"}>
          {num(@w.no_keywords, "post has", "posts have")} no keywords
        </.link>
      </:state>
      <:state :if={@w.published > 0}>
        <.link navigate={~p"/admin/health"}>Content health</.link>
        checks every page, so it runs when you open it
      </:state>
      <:actions>
        <.link navigate={~p"/admin/blog#new-post-form"} class="adm-btn adm-btn--primary">
          New post
        </.link>
        <.link navigate={~p"/admin/keywords"} class="adm-btn">Keywords</.link>
      </:actions>
    </.program_card>
    """
  end

  attr :t, :map, required: true

  defp training_card(assigns) do
    t = assigns.t
    quiet? = is_nil(t.today) and is_nil(t.newest) and is_nil(t.sync.at)
    assigns = assign(assigns, :quiet?, quiet?)

    ~H"""
    <.program_card
      id="program-training"
      program={:training}
      title="Training"
      href={~p"/admin/fitness"}
    >
      <:picture :if={@t.newest && @t.newest.picture}>
        <img src={@t.newest.picture} alt="" loading="lazy" decoding="async" />
      </:picture>
      <:state :if={@quiet?}>
        No regimen for today, no activities and no Komoot sync yet. Open Fitness to set the week.
      </:state>
      <:state :if={@t.today}>
        Today is {String.capitalize(@t.today.slug)}: {@t.today.word || @t.today.title}
      </:state>
      <:state :if={!@quiet? and is_nil(@t.today)}>No regimen written for today</:state>
      <:state :if={@t.newest}>
        Newest activity <span class="ov-words">{@t.newest.name}</span>, <b class="ov-num">{Rides.Units.distance(@t.newest.distance_m)}</b>, {Rides.Units.date(
          @t.newest.started_at
        )}
      </:state>
      <:state :if={!@quiet? and is_nil(@t.newest)}>No activities yet</:state>
      <:state :if={!@quiet?} tone={sync_tone(@t.sync)}>{sync_line(@t.sync)}</:state>
      <:actions>
        <.link navigate={~p"/admin/fitness"} class="adm-btn adm-btn--primary">Fitness</.link>
        <.link navigate={~p"/admin/rides"} class="adm-btn">Activities</.link>
      </:actions>
    </.program_card>
    """
  end

  defp sync_tone(%{status: :failed}), do: :fail
  defp sync_tone(%{status: :partial}), do: :warn
  defp sync_tone(_sync), do: nil

  defp sync_line(%{at: nil}), do: "No Komoot sync recorded yet"
  defp sync_line(%{status: :failed, at: at}), do: "The last Komoot sync failed, #{ago(at)}"

  defp sync_line(%{status: :partial, at: at}),
    do: "Komoot synced #{ago(at)}, some tours did not import"

  defp sync_line(%{at: at}), do: "Komoot synced #{ago(at)}"

  attr :m, :map, required: true

  defp mail_card(assigns) do
    m = assigns.m
    quiet? = m.open == 0 and m.held == 0 and m.citations == 0
    assigns = assign(assigns, :quiet?, quiet?)

    ~H"""
    <.program_card id="program-mail" program={:mail} title="Mail" href={~p"/admin/inbox"}>
      <:state :if={@quiet?}>
        Nothing waits in the inbox, the guestbook or the citations.
      </:state>
      <:state :if={@m.open > 0}>
        {num(@m.open, "message", "messages")} open{flagged(@m.flagged)}
      </:state>
      <:state :if={@m.held > 0}>
        {num(@m.held, "signature", "signatures")} held for approval
      </:state>
      <:state :if={@m.citations > 0}>
        {num(@m.citations, "citation", "citations")} awaiting approval
      </:state>
      <:state :if={@m.newest}>
        Newest, from <span class="ov-words">{@m.newest.name}</span>, {ago(@m.newest.at)}:
        <span class="ov-words ov-quote">“{@m.newest.line}”</span>
      </:state>
      <:actions>
        <.link navigate={~p"/admin/inbox"} class="adm-btn adm-btn--primary">Inbox</.link>
        <.link navigate={~p"/admin/guestbook"} class="adm-btn">Guestbook</.link>
      </:actions>
    </.program_card>
    """
  end

  defp flagged(0), do: ""
  defp flagged(n), do: ", #{n} flagged"

  # A number in a sentence: the figure in the data face, the noun after it.
  defp num(n, one, many) do
    assigns = %{n: n, noun: plural(n, one, many)}
    ~H'<b class="ov-num">{@n}</b> {@noun}'
  end

  # ── The status strip ──────────────────────────────────────────────────

  # The machine first, as one item whatever its state (each check that is not
  # as it should be is already a line under "Needs you", and the strip is
  # read in passing), then today's traffic once it has been read, then what
  # is on file.
  defp strip_items(checks, monitored?, on_file, traffic) do
    machine(checks, monitored?) ++ traffic_items(traffic) ++ file_items(on_file)
  end

  defp machine(checks, monitored?) do
    case Enum.filter(checks, &(&1.state in [:warn, :fail])) do
      [] when monitored? ->
        [%{label: "Machine", value: "all well", href: "#system"}]

      [] ->
        [%{label: "Machine", value: "not yet looked at", tone: :warn, href: "#system"}]

      bad ->
        tone = if Enum.any?(bad, &(&1.state == :fail)), do: :fail, else: :warn

        value =
          if length(bad) == 1, do: "1 check needs you", else: "#{length(bad)} checks need you"

        [%{label: "Machine", value: value, tone: tone, href: "#system"}]
    end
  end

  defp traffic_items(%{ok?: true, result: traffic}) do
    [
      %{label: "Visitors today", value: traffic.visitors},
      %{label: "Views today", value: traffic.views},
      %{
        label: "Views in 56 weeks",
        value: traffic.window,
        spark: Enum.map(traffic.trend, fn {_, _, count} -> count end)
      }
    ]
  end

  defp traffic_items(_loading), do: []

  defp file_items(on_file) do
    [
      %{label: "Posts", value: on_file.posts, href: ~p"/admin/blog"},
      %{label: "Captain's logs", value: on_file.logs, href: ~p"/admin/logs"},
      %{label: "Subscribers", value: on_file.subscribers, href: ~p"/admin/newsletter"},
      %{label: "Activities", value: on_file.activities, href: ~p"/admin/rides"},
      %{label: "Signatures", value: on_file.signatures, href: ~p"/admin/guestbook"}
    ]
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

  defp print_name(%{roll: roll, frame: frame}), do: "frame #{frame} of roll #{roll}"

  defp print_names(prints), do: Enum.map_join(prints, ", ", &print_name/1)

  # `0:42` for a cut's length.
  defp clock(ms) do
    seconds = div(ms, 1000)
    "#{div(seconds, 60)}:#{String.pad_leading(to_string(rem(seconds, 60)), 2, "0")}"
  end

  defp short_date(%Date{} = date), do: Calendar.strftime(date, "%b %-d")
end
