defmodule WebWeb.AdminComponents do
  @moduledoc """
  The admin's vocabulary — "the studio". Every `/admin/*` page is built from
  these, and every rule they lean on lives under `assets/css/admin/` (the
  shared classes in `base.css`, each program's own in its file) under
  `.admin-layout`, so a page carries no `<style>` block and no inline colour of
  its own. Colour is the `--st-*` tokens, dark or light by the system's
  setting, and the page's accent follows its program (`WebWeb.AdminNav.program/1`).

  The type: IBM Plex Sans for the interface, IBM Plex Mono for figures,
  timecodes, ids and file names, and Fraunces for page titles and for words
  people wrote — a post's title, a log's caption, a guestbook signature, a
  message in the inbox.

  Beyond the furniture (`rail`, `page_head`, `panel`, `tabs`, `rows`, `pill`,
  `empty`, `drop_zone`), two components compose the studio floor:
  `program_card/1` (a program's card) and `status_strip/1` (the passive
  figures, read in passing).

  Names avoid `WebWeb.CoreComponents`' (`header`, `table`, `button`, …): both
  are imported into admin LiveViews. Buttons are plain `<button>`s with an
  `adm-btn` class rather than a component, since each carries its own
  `phx-*` bindings.
  """

  use Phoenix.Component
  use WebWeb, :verified_routes

  import WebWeb.CoreComponents, only: [icon: 1, wordmark: 1]

  alias Phoenix.LiveView.JS

  # --- The rail -------------------------------------------------------------

  @doc """
  The admin's left rail: wordmark, the programs as groups (each with its own
  colour as a small mark), waiting counts as small pills, and the way out.
  Settings sits at the foot. At ≤900px it folds to a bar with a Menu button,
  which opens the navigation in place without a round trip to the server.
  """
  attr :path, :string, default: nil, doc: "the current request path, to mark the page you're on"
  attr :counts, :map, default: %{}

  def rail(assigns) do
    sections = WebWeb.AdminNav.sections()

    # The page is marked on the link nearest it: /admin/darkroom/taste is
    # Taste, not also Prints at /admin/darkroom.
    nearest =
      for(
        group <- sections,
        link <- group.links,
        under?(assigns[:path], link.path),
        do: link.path
      )
      |> Enum.max_by(&String.length/1, fn -> nil end)

    assigns = assign(assigns, sections: sections, nearest: nearest)

    ~H"""
    <aside id="adm-rail" class="adm-rail">
      <div class="adm-rail-bar">
        <.link navigate={~p"/admin/dashboard"} class="adm-brand" aria-label="streetscissors admin">
          <span class="adm-brand-mark" aria-hidden="true"><.wordmark /></span>
          <span class="adm-brand-slug">Admin</span>
        </.link>
        <button
          type="button"
          class="adm-menu-btn"
          aria-controls="adm-rail-body"
          phx-click={JS.toggle_class("is-open", to: "#adm-rail")}
        >
          <.icon name="hero-bars-3" class="size-5" />
          <span>Menu</span>
        </button>
      </div>

      <div id="adm-rail-body" class="adm-rail-body">
        <nav class="adm-nav" aria-label="Admin">
          <div
            :for={group <- @sections}
            id={"adm-nav-#{group.id}"}
            class={[
              "adm-nav-group",
              "st-program--#{group.program}",
              group.id == :settings && "adm-nav-group--foot"
            ]}
          >
            <p :if={group.heading} class="adm-nav-heading">
              <span class="adm-nav-mark" aria-hidden="true"></span>{group.heading}
            </p>
            <.link
              :for={link <- group.links}
              navigate={link.path}
              class="adm-nav-link"
              aria-current={link.path == @nearest && "page"}
            >
              <.icon name={link.icon} class="size-4" />
              <span class="adm-nav-label">{link.label}</span>
              <span
                :if={link[:count] && Map.get(@counts, link.count, 0) > 0}
                class={["adm-badge", link.count == :logs && "adm-badge--fail"]}
                aria-label={"#{Map.get(@counts, link.count)} waiting"}
              >
                {Map.get(@counts, link.count)}
              </span>
            </.link>
          </div>
        </nav>

        <div class="adm-rail-foot">
          <.link href={~p"/"} class="adm-nav-link adm-nav-link--quiet" target="_blank" rel="noopener">
            <.icon name="hero-arrow-top-right-on-square" class="size-4" />
            <span class="adm-nav-label">View site</span>
          </.link>
          <.link href={~p"/admin/logout"} method="delete" class="adm-nav-link adm-nav-link--quiet">
            <.icon name="hero-arrow-right-on-rectangle" class="size-4" />
            <span class="adm-nav-label">Log out</span>
          </.link>
        </div>
      </div>
    </aside>
    """
  end

  defp under?(nil, _link), do: false
  defp under?(path, link), do: path == link or String.starts_with?(path, link <> "/")

  # --- Page furniture -------------------------------------------------------

  @doc """
  The head of every admin page: a small eyebrow (the slug, sentence case) over
  the title in Fraunces, one line of lede, and the page's own actions at the
  right (under the title on a phone).
  """
  attr :slug, :string, default: nil, doc: "the eyebrow, e.g. \"Writing / Blog\""
  attr :title, :string, required: true
  slot :lede
  slot :actions

  def page_head(assigns) do
    ~H"""
    <header class="adm-head">
      <div class="adm-head-text">
        <p :if={@slug} class="adm-slug">{@slug}</p>
        <h1 class="adm-title">{@title}</h1>
        <p :if={@lede != []} class="adm-lede">{render_slot(@lede)}</p>
      </div>
      <div :if={@actions != []} class="adm-head-actions">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  A titled section of a page: a card (surface, hairline, 10px radius) with its
  title and actions in a head row. Pass `class="adm-panel--bare"` for the same
  head without the card, where the content brings its own surface.
  """
  attr :title, :string, default: nil
  attr :count, :any, default: nil
  attr :id, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :global
  slot :actions
  slot :inner_block, required: true

  def panel(assigns) do
    ~H"""
    <section id={@id} class={["adm-panel", @class]} {@rest}>
      <div :if={@title || @actions != []} class="adm-panel-head">
        <h2 :if={@title} class="adm-panel-title">
          {@title}<span :if={@count != nil} class="adm-count">{@count}</span>
        </h2>
        <div :if={@actions != []} class="adm-panel-actions">{render_slot(@actions)}</div>
      </div>
      {render_slot(@inner_block)}
    </section>
    """
  end

  @doc """
  One figure with its label: a small mono number over a muted label, no box. A
  row of them (`.adm-stats`) is a quiet line, not a wall of tiles; for the
  studio floor's passive figures prefer `status_strip/1`.
  """
  attr :value, :any, required: true
  attr :label, :string, required: true
  attr :note, :string, default: nil
  attr :href, :string, default: nil
  attr :tone, :string, default: nil

  def stat(assigns) do
    ~H"""
    <.link :if={@href} navigate={@href} class={["adm-stat", "adm-stat--link", tone(@tone)]}>
      <.stat_body value={@value} label={@label} note={@note} />
    </.link>
    <div :if={!@href} class={["adm-stat", tone(@tone)]}>
      <.stat_body value={@value} label={@label} note={@note} />
    </div>
    """
  end

  defp stat_body(assigns) do
    ~H"""
    <span class="adm-stat-value">{@value}</span>
    <span class="adm-stat-label">{@label}</span>
    <span :if={@note} class="adm-stat-note">{@note}</span>
    """
  end

  # --- The studio floor -------------------------------------------------------

  @programs [:darkroom, :cuts, :writing, :training, :mail]

  @doc """
  A program's card on the studio floor: its name (the link to where it lives),
  an optional picture on the dark `--st-bay` surround, a few lines of its
  state (what is in progress, what was done last) and its main actions. The
  card wears its program's colour (`--st-accent`), so a `adm-btn--primary`
  inside it is filled with it.

  The card is **not** one big link: only the title is a link, stretched over
  the card so the whole of it is a target, and anything pressable in the
  `:state` and `:actions` slots (links, buttons, forms) sits above it and keeps
  its own click. Lay several out in a `<div class="st-cards">` (a responsive
  grid; one column on a phone).

      <.program_card program={:darkroom} title="Darkroom" href={~p"/admin/darkroom"}>
        <:picture><img src={@last_print} alt="" /></:picture>
        <:state>Roll 065: 3 frames printed</:state>
        <:state tone={:warn}>2 rolls wait to be published</:state>
        <:actions>
          <.link navigate={~p"/admin/scanner"} class="adm-btn adm-btn--primary">Scan a roll</.link>
        </:actions>
      </.program_card>
  """
  attr :program, :atom, required: true, values: @programs, doc: "which program's colour it wears"
  attr :title, :string, required: true
  attr :href, :string, required: true, doc: "the program's own page; the title links to it"
  attr :id, :string, default: nil
  attr :class, :any, default: nil
  attr :rest, :global

  slot :picture, doc: "optional: an image or video, shown on the --st-bay surround"

  slot :state,
    doc: "one entry per line of state; an entry's `tone` (ok, warn, fail) colours its dot" do
    attr :tone, :atom
  end

  slot :actions, doc: "the main action(s): buttons or links, always clickable"

  def program_card(assigns) do
    ~H"""
    <article id={@id} class={["st-card", "st-program--#{@program}", @class]} {@rest}>
      <div :if={@picture != []} class="st-card-picture">{render_slot(@picture)}</div>
      <div class="st-card-body">
        <h3 class="st-card-title">
          <span class="st-card-mark" aria-hidden="true"></span>
          <.link navigate={@href} class="st-card-link">{@title}</.link>
        </h3>
        <ul :if={@state != []} class="st-card-state">
          <li
            :for={line <- @state}
            class={["st-card-line", line[:tone] && "st-card-line--#{line[:tone]}"]}
          >
            {render_slot(line)}
          </li>
        </ul>
        <div :if={@actions != []} class="st-card-actions">{render_slot(@actions)}</div>
      </div>
    </article>
    """
  end

  @doc """
  The passive figures, read in passing: one quiet line of small, muted figures
  in Plex Mono that wraps on a phone. Nothing in it is a tile or a button; an
  item with an `href` is a plain link, an item with `spark` carries a tiny
  line of its recent values, and only an item that fails (or, more softly,
  warns) shows its tone, so nothing else draws the eye.

  Each item is a map: `:label`, `:value`, and optionally `:tone` (`:ok`,
  `:warn`, `:fail`), `:href` (a path, or a `#anchor`) and `:spark` (a list of
  numbers, at least two).

      <.status_strip items={[
        %{label: "Visitors today", value: 12, spark: [3, 5, 4, 9, 12]},
        %{label: "Posts", value: 4, href: ~p"/admin/blog"},
        %{label: "Mirror drive", value: "absent", tone: :fail, href: "#system"}
      ]} />
  """
  attr :items, :list, required: true, doc: "maps with :label, :value, :tone, :href, :spark"
  attr :label, :string, default: "Figures", doc: "what the strip is called, for a screen reader"
  attr :class, :any, default: nil
  attr :rest, :global

  def status_strip(assigns) do
    ~H"""
    <ul class={["st-strip", @class]} aria-label={@label} {@rest}>
      <li
        :for={item <- @items}
        class={["st-strip-item", item[:tone] && "st-strip-item--#{item[:tone]}"]}
      >
        <.link
          :if={item[:href] && String.starts_with?(item[:href], "/")}
          navigate={item[:href]}
          class="st-strip-link"
        >
          <.strip_figure item={item} />
        </.link>
        <.link
          :if={item[:href] && !String.starts_with?(item[:href], "/")}
          href={item[:href]}
          class="st-strip-link"
        >
          <.strip_figure item={item} />
        </.link>
        <span :if={!item[:href]} class="st-strip-link">
          <.strip_figure item={item} />
        </span>
      </li>
    </ul>
    """
  end

  defp strip_figure(assigns) do
    assigns = assign(assigns, :points, spark_points(assigns.item[:spark]))

    ~H"""
    <span class="st-strip-label">{@item.label}</span>
    <span class="st-strip-value">{@item.value}</span>
    <span :if={@item[:tone] in [:warn, :fail]} class="adm-sr">
      ({if @item.tone == :fail, do: "failing", else: "needs a look"})
    </span>
    <svg
      :if={@points}
      class="st-strip-spark"
      viewBox="0 0 48 14"
      width="48"
      height="14"
      aria-hidden="true"
    >
      <polyline
        points={@points}
        fill="none"
        stroke="currentColor"
        stroke-width="1.25"
        stroke-linecap="round"
        stroke-linejoin="round"
      />
    </svg>
    """
  end

  # The points of a 48x14 sparkline for a list of numbers; nil when there is
  # nothing to draw (fewer than two values). A flat series is a flat line.
  defp spark_points(values) when is_list(values) and length(values) >= 2 do
    {low, high} = Enum.min_max(values)
    span = if high == low, do: 1, else: high - low
    step = 46 / (length(values) - 1)

    values
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {value, index} ->
      x = Float.round(1 + index * step, 1)
      y = if high == low, do: 7.0, else: Float.round(13 - (value - low) / span * 12, 1)
      "#{x},#{y}"
    end)
  end

  defp spark_points(_values), do: nil

  @doc """
  A status mark. Tones: `live` (published, approved, healthy), `held`
  (waiting on you), `attention`, `failed`, `draft`, `quiet`.
  """
  attr :tone, :string, default: "quiet"
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def pill(assigns) do
    ~H"""
    <span class={["adm-pill", "adm-pill--#{@tone}", @class]}>{render_slot(@inner_block)}</span>
    """
  end

  defp tone(nil), do: nil
  defp tone(tone), do: "adm-tone--#{tone}"

  @doc """
  View switches that are links: each tab is a `patch`, so the choice lives in
  the URL and the browser's Back button walks it.
  """
  attr :label, :string, default: "Views"

  slot :tab, required: true do
    attr :patch, :string, required: true
    attr :active, :boolean
    attr :count, :integer
  end

  def tabs(assigns) do
    ~H"""
    <nav class="adm-tabs" aria-label={@label}>
      <.link
        :for={tab <- @tab}
        patch={tab.patch}
        class="adm-tab"
        aria-current={tab[:active] && "page"}
      >
        {render_slot(tab)}<span :if={tab[:count]} class="adm-tab-count">{tab.count}</span>
      </.link>
    </nav>
    """
  end

  @doc """
  A ruled table with an empty state of its own. On a phone each row stacks
  into a block, its cells led by their column's label (`data-label`).
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil
  attr :class, :any, default: nil

  slot :col, required: true do
    attr :label, :string
    attr :class, :string
  end

  slot :action
  slot :empty

  def rows(assigns) do
    ~H"""
    <div class={["adm-table-wrap", @class]}>
      <table id={@id} class="adm-table">
        <thead>
          <tr>
            <th :for={col <- @col} class={col[:class]}>{col[:label]}</th>
            <th :if={@action != []}><span class="adm-sr">Actions</span></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
            <td :for={col <- @col} class={col[:class]} data-label={col[:label]}>
              {render_slot(col, row)}
            </td>
            <td :if={@action != []} class="adm-table-actions">
              <div class="adm-actions">
                <%= for action <- @action do %>
                  {render_slot(action, row)}
                <% end %>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
      <.empty :if={@rows == [] and @empty != []}>{render_slot(@empty)}</.empty>
    </div>
    """
  end

  @doc """
  What a list says when there is nothing in it: one sentence of what to do
  next, with the button to do it inside the slot where there is one.
  """
  attr :class, :any, default: nil
  slot :inner_block, required: true

  def empty(assigns) do
    ~H"""
    <p class={["adm-empty", @class]}>{render_slot(@inner_block)}</p>
    """
  end

  @doc "A post's or log's keywords, as the chips the public filters use."
  attr :keywords, :list, required: true

  def keyword_chips(assigns) do
    ~H"""
    <span :if={@keywords != []} class="adm-chips">
      <span :for={keyword <- @keywords} class="adm-chip">{keyword}</span>
    </span>
    """
  end

  # --- Uploads --------------------------------------------------------------

  @doc """
  A drop target around a live file input. The input sits inside the zone, so
  a caller that needs it inside its own form (the logs booth does) can put the
  whole zone there.
  """
  attr :upload, :any, required: true
  attr :title, :string, required: true
  attr :hint, :string, default: nil
  attr :browse, :string, default: "Browse files"
  attr :error_message, :any, required: true, doc: "fn error_atom -> message"
  attr :class, :any, default: nil

  def drop_zone(assigns) do
    ~H"""
    <div class={["adm-drop", @class]} phx-drop-target={@upload.ref}>
      <.icon name="hero-cloud-arrow-up" class="size-6 adm-drop-icon" />
      <p class="adm-drop-title">{@title}</p>
      <p :if={@hint} class="adm-help">{@hint}</p>
      <label class="adm-btn adm-btn--quiet adm-btn--small">
        {@browse} <.live_file_input upload={@upload} class="adm-file-input" />
      </label>

      <div :for={entry <- @upload.entries} class="adm-upload">
        <span class="adm-upload-name">{entry.client_name}</span>
        <div class="adm-progress">
          <div class="adm-progress-bar" style={"width: #{entry.progress}%"}></div>
        </div>
        <p :for={err <- upload_errors(@upload, entry)} class="adm-error">{@error_message.(err)}</p>
      </div>
      <p :for={err <- upload_errors(@upload)} class="adm-error">{@error_message.(err)}</p>
    </div>
    """
  end

  @doc """
  A read-only value with a Copy button — markdown for an uploaded image, say.
  The copy happens in the browser; nothing goes to the server.
  """
  attr :id, :string, required: true
  attr :value, :string, required: true
  attr :label, :string, default: "Copy"
  attr :names, :string, default: "Markdown", doc: "what the value is, for a screen reader"

  def copy_field(assigns) do
    ~H"""
    <div id={@id} class="adm-copy" phx-hook=".CopyText">
      <input type="text" value={@value} readonly class="adm-copy-input" aria-label={@names} />
      <button type="button" class="adm-link" data-copy>
        <.icon name="hero-clipboard" class="size-4" /><span data-copy-label>{@label}</span>
      </button>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".CopyText">
      // Copies the field's value and says so for a moment. Falls back to
      // selecting the text where the clipboard API is refused (plain http).
      export default {
        mounted() {
          const input = this.el.querySelector("input")
          const button = this.el.querySelector("[data-copy]")
          const label = this.el.querySelector("[data-copy-label]")
          const original = label.textContent

          input.addEventListener("focus", () => input.select())
          button.addEventListener("click", async () => {
            try {
              await navigator.clipboard.writeText(input.value)
              label.textContent = "Copied"
            } catch (_error) {
              input.select()
              label.textContent = "Press ⌘C"
            }
            clearTimeout(this.timer)
            this.timer = setTimeout(() => (label.textContent = original), 1600)
          })
        },
        destroyed() {
          clearTimeout(this.timer)
        }
      }
    </script>
    """
  end

  # --- Small formatting helpers shared by the admin pages -----------------

  @doc "A timestamp in the admin's one format: `2026-09-29 14:07`."
  def stamp(nil), do: "—"
  def stamp(%NaiveDateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M")
  def stamp(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M")
  def stamp(%Date{} = on), do: Calendar.strftime(on, "%Y-%m-%d")

  @doc "How long ago, coarsely: `just now`, `4 min ago`, `3 h ago`, `2 days ago`."
  def ago(nil), do: "never"

  def ago(%NaiveDateTime{} = at), do: at |> DateTime.from_naive!("Etc/UTC") |> ago()

  def ago(%DateTime{} = at) do
    seconds = DateTime.diff(DateTime.utc_now(), at, :second)

    cond do
      seconds < 60 -> "just now"
      seconds < 3600 -> "#{div(seconds, 60)} min ago"
      seconds < 86_400 -> "#{div(seconds, 3600)} h ago"
      seconds < 172_800 -> "yesterday"
      true -> "#{div(seconds, 86_400)} days ago"
    end
  end
end
