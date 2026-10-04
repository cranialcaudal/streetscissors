defmodule WebWeb.AdminComponents do
  @moduledoc """
  The admin's vocabulary — "the composing room", the back office of the print
  shop. Every `/admin/*` page is built from these, and every rule they lean on
  lives in `assets/css/admin.css` under `.admin-layout`, so a page carries no
  `<style>` block and no inline colour of its own.

  The type splits the way the rest of the site does: IBM Plex Mono is the
  instrument voice (navigation, labels, buttons, figures), and Sorts Mill Goudy
  is kept for page titles and for words people wrote — a post's title, a log's
  caption, a guestbook signature, a message in the inbox.

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
  The admin's left rail: wordmark, grouped navigation with waiting counts,
  and the way out. At ≤900px it folds to a bar with a Menu button, which
  opens the navigation in place without a round trip to the server.
  """
  attr :path, :string, default: nil, doc: "the current request path, to mark the page you're on"
  attr :counts, :map, default: %{}

  def rail(assigns) do
    assigns = assign(assigns, :sections, WebWeb.AdminNav.sections())

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
          <div :for={{group, links} <- @sections} class="adm-nav-group">
            <p :if={group} class="adm-nav-heading">{group}</p>
            <.link
              :for={link <- links}
              navigate={link.path}
              class="adm-nav-link"
              aria-current={current?(@path, link.path) && "page"}
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

  defp current?(nil, _link), do: false
  defp current?(path, link), do: path == link or String.starts_with?(path, link <> "/")

  # --- Page furniture -------------------------------------------------------

  @doc """
  The head of every admin page: a mono slug line over a Goudy title, like the
  slug on a galley proof, with the page's own actions to the right.
  """
  attr :slug, :string, default: nil, doc: "e.g. \"Write / Blog\""
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

  @doc "A titled section of a page, ruled off from the next."
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

  @doc "One figure with its label, for the overview's rows of numbers."
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

  @doc "A ruled table in the data voice, with an empty state of its own."
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
            <td :for={col <- @col} class={col[:class]}>{render_slot(col, row)}</td>
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

  @doc "What a list says when there is nothing in it."
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

  def copy_field(assigns) do
    ~H"""
    <div id={@id} class="adm-copy" phx-hook=".CopyText">
      <input type="text" value={@value} readonly class="adm-copy-input" aria-label="Markdown" />
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
