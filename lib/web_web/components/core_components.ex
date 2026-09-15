defmodule WebWeb.CoreComponents do
  @moduledoc """
  Provides core UI components.

  At first glance, this module may seem daunting, but its goal is to provide
  core building blocks for your application, such as tables, forms, and
  inputs. The components consist mostly of markup and are well-documented
  with doc strings and declarative assigns. You may customize and style
  them in any way you want, based on your application growth and needs.

  The foundation for styling is Tailwind CSS, a utility-first CSS framework,
  augmented with daisyUI, a Tailwind CSS plugin that provides UI components
  and themes. Here are useful references:

    * [daisyUI](https://daisyui.com/docs/intro/) - a good place to get
      started and see the available components.

    * [Tailwind CSS](https://tailwindcss.com) - the foundational framework
      we build on. You will use it for layout, sizing, flexbox, grid, and
      spacing.

    * [Heroicons](https://heroicons.com) - see `icon/1` for usage.

    * [Phoenix.Component](https://hexdocs.pm/phoenix_live_view/Phoenix.Component.html) -
      the component system used by Phoenix. Some components, such as `<.link>`
      and `<.form>`, are defined there.

  """
  use Phoenix.Component

  use Phoenix.VerifiedRoutes,
    endpoint: WebWeb.Endpoint,
    router: WebWeb.Router,
    statics: WebWeb.static_paths()

  use Gettext, backend: WebWeb.Gettext

  alias Phoenix.LiveView.JS

  @doc """
  Renders flash notices.

  ## Examples

      <.flash kind={:info} flash={@flash} />
      <.flash kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"

  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class="toast toast-top toast-end z-50"
      {@rest}
    >
      <div class={[
        "alert w-80 sm:w-96 max-w-80 sm:max-w-96 text-wrap",
        @kind == :info && "alert-info",
        @kind == :error && "alert-error"
      ]}>
        <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
        <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
        <div>
          <p :if={@title} class="font-semibold">{@title}</p>
          <p>{msg}</p>
        </div>
        <div class="flex-1" />
        <button type="button" class="group self-start cursor-pointer" aria-label={gettext("close")}>
          <.icon name="hero-x-mark" class="size-5 opacity-40 group-hover:opacity-70" />
        </button>
      </div>
    </div>
    """
  end

  @doc """
  Renders a simple form.

  ## Examples

      <.simple_form for={@form} phx-change="validate" phx-submit="save">
        <.input field={@form[:email]} label="Email"/>
        <.input field={@form[:username]} label="Username" />
        <:actions>
          <.button>Save</.button>
        </:actions>
      </.simple_form>
  """
  attr :for, :any, required: true, doc: "the datastructure for the form"
  attr :as, :any, default: nil, doc: "the server side parameter to collect all input under"

  attr :rest, :global,
    include: ~w(autocomplete name rel action enctype method novalidate target multipart),
    doc: "the arbitrary HTML attributes to apply to the form tag"

  slot :inner_block, required: true
  slot :actions, doc: "the slot for form actions, such as a save button"

  def simple_form(assigns) do
    ~H"""
    <.form :let={f} for={@for} as={@as} {@rest}>
      <div class="space-y-8 bg-white mt-10">
        {render_slot(@inner_block, f)}
        <div :if={@actions != []} class="flex items-center justify-between gap-6">
          {render_slot(@actions, f)}
        </div>
      </div>
    </.form>
    """
  end

  @doc """
  Renders a modal.
  """
  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, :any, default: %{}
  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div id={"#{@id}-bg"} class="fixed inset-0 bg-zinc-50/90 transition-opacity" aria-hidden="true" />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center p-4 text-center sm:p-0">
          <div class="w-full max-w-3xl overflow-hidden rounded-2xl bg-white p-6 text-left align-middle shadow-xl transition-all">
            <.focus_wrap id={"#{@id}-container"} class="p-1">
              {render_slot(@inner_block)}
            </.focus_wrap>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> show("##{id}-container")
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-container")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all transform ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> hide("##{id}-container")
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  @doc """
  Renders a button with navigation support.

  ## Examples

      <.button>Send!</.button>
      <.button phx-click="go" variant="primary">Send!</.button>
      <.button navigate={~p"/"}>Home</.button>
  """
  attr :rest, :global, include: ~w(href navigate patch method download name value disabled)
  attr :class, :any
  attr :variant, :string, values: ~w(primary)
  slot :inner_block, required: true

  def button(%{rest: rest} = assigns) do
    variants = %{"primary" => "btn-primary", nil => "btn-primary btn-soft"}

    assigns =
      assign_new(assigns, :class, fn ->
        ["btn", Map.fetch!(variants, assigns[:variant])]
      end)

    if rest[:href] || rest[:navigate] || rest[:patch] do
      ~H"""
      <.link class={@class} {@rest}>
        {render_slot(@inner_block)}
      </.link>
      """
    else
      ~H"""
      <button class={@class} {@rest}>
        {render_slot(@inner_block)}
      </button>
      """
    end
  end

  @doc """
  Renders an input with label and error messages.

  A `Phoenix.HTML.FormField` may be passed as argument,
  which is used to retrieve the input name, id, and values.
  Otherwise all attributes may be passed explicitly.

  ## Types

  This function accepts all HTML input types, considering that:

    * You may also set `type="select"` to render a `<select>` tag

    * `type="checkbox"` is used exclusively to render boolean values

    * For live file uploads, see `Phoenix.Component.live_file_input/1`

  See https://developer.mozilla.org/en-US/docs/Web/HTML/Element/input
  for more information. Unsupported types, such as radio, are best
  written directly in your templates.

  ## Examples

  ```heex
  <.input field={@form[:email]} type="email" />
  <.input name="my-input" errors={["oh no!"]} />
  ```

  ## Select type

  When using `type="select"`, you must pass the `options` and optionally
  a `value` to mark which option should be preselected.

  ```heex
  <.input field={@form[:user_type]} type="select" options={["Admin": "admin", "User": "user"]} />
  ```

  For more information on what kind of data can be passed to `options` see
  [`options_for_select`](https://hexdocs.pm/phoenix_html/Phoenix.HTML.Form.html#options_for_select/2).
  """
  attr :id, :any, default: nil
  attr :name, :any
  attr :label, :string, default: nil
  attr :value, :any

  attr :type, :string,
    default: "text",
    values: ~w(checkbox color date datetime-local email file month number password
               search select tel text textarea time url week hidden)

  attr :field, Phoenix.HTML.FormField,
    doc: "a form field struct retrieved from the form, for example: @form[:email]"

  attr :errors, :list, default: []
  attr :checked, :boolean, doc: "the checked flag for checkbox inputs"
  attr :prompt, :string, default: nil, doc: "the prompt for select inputs"
  attr :options, :list, doc: "the options to pass to Phoenix.HTML.Form.options_for_select/2"
  attr :multiple, :boolean, default: false, doc: "the multiple flag for select inputs"
  attr :class, :any, default: nil, doc: "the input class to use over defaults"
  attr :error_class, :any, default: nil, doc: "the input error class to use over defaults"

  attr :rest, :global,
    include: ~w(accept autocomplete capture cols disabled form list max maxlength min minlength
                multiple pattern placeholder readonly required rows size step)

  def input(%{field: %Phoenix.HTML.FormField{} = field} = assigns) do
    errors = if Phoenix.Component.used_input?(field), do: field.errors, else: []

    assigns
    |> assign(field: nil, id: assigns.id || field.id)
    |> assign(:errors, Enum.map(errors, &translate_error(&1)))
    |> assign_new(:name, fn -> if assigns.multiple, do: field.name <> "[]", else: field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> input()
  end

  def input(%{type: "hidden"} = assigns) do
    ~H"""
    <input type="hidden" id={@id} name={@name} value={@value} {@rest} />
    """
  end

  def input(%{type: "checkbox"} = assigns) do
    assigns =
      assign_new(assigns, :checked, fn ->
        Phoenix.HTML.Form.normalize_value("checkbox", assigns[:value])
      end)

    ~H"""
    <div class="fieldset mb-2">
      <label>
        <input
          type="hidden"
          name={@name}
          value="false"
          disabled={@rest[:disabled]}
          form={@rest[:form]}
        />
        <span class="label">
          <input
            type="checkbox"
            id={@id}
            name={@name}
            value="true"
            checked={@checked}
            class={@class || "checkbox checkbox-sm"}
            {@rest}
          />{@label}
        </span>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "select"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <select
          id={@id}
          name={@name}
          class={[@class || "w-full select", @errors != [] && (@error_class || "select-error")]}
          multiple={@multiple}
          {@rest}
        >
          <option :if={@prompt} value="">{@prompt}</option>
          {Phoenix.HTML.Form.options_for_select(@options, @value)}
        </select>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  def input(%{type: "textarea"} = assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <textarea
          id={@id}
          name={@name}
          class={[
            @class || "w-full textarea",
            @errors != [] && (@error_class || "textarea-error")
          ]}
          {@rest}
        >{Phoenix.HTML.Form.normalize_value("textarea", @value)}</textarea>
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # All other inputs text, datetime-local, url, password, etc. are handled here...
  def input(assigns) do
    ~H"""
    <div class="fieldset mb-2">
      <label>
        <span :if={@label} class="label mb-1">{@label}</span>
        <input
          type={@type}
          name={@name}
          id={@id}
          value={Phoenix.HTML.Form.normalize_value(@type, @value)}
          class={[
            @class || "w-full input",
            @errors != [] && (@error_class || "input-error")
          ]}
          {@rest}
        />
      </label>
      <.error :for={msg <- @errors}>{msg}</.error>
    </div>
    """
  end

  # Helper used by inputs to generate form errors
  defp error(assigns) do
    ~H"""
    <p class="mt-1.5 flex gap-2 items-center text-sm text-error">
      <.icon name="hero-exclamation-circle" class="size-5" />
      {render_slot(@inner_block)}
    </p>
    """
  end

  @doc """
  Renders a header with title.
  """
  slot :inner_block, required: true
  slot :subtitle
  slot :actions

  def header(assigns) do
    ~H"""
    <header class={[@actions != [] && "flex items-center justify-between gap-6", "pb-4"]}>
      <div>
        <h1 class="text-lg font-semibold leading-8">
          {render_slot(@inner_block)}
        </h1>
        <p :if={@subtitle != []} class="text-sm text-base-content/70">
          {render_slot(@subtitle)}
        </p>
      </div>
      <div class="flex-none">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id">{user.id}</:col>
        <:col :let={user} label="username">{user.username}</:col>
      </.table>
  """
  attr :id, :string, required: true
  attr :rows, :list, required: true
  attr :row_id, :any, default: nil, doc: "the function for generating the row id"
  attr :row_click, :any, default: nil, doc: "the function for handling phx-click on each row"

  attr :row_item, :any,
    default: &Function.identity/1,
    doc: "the function for mapping each row before calling the :col and :action slots"

  slot :col, required: true do
    attr :label, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    assigns =
      with %{rows: %Phoenix.LiveView.LiveStream{}} <- assigns do
        assign(assigns, row_id: assigns.row_id || fn {id, _item} -> id end)
      end

    ~H"""
    <table class="table table-zebra">
      <thead>
        <tr>
          <th :for={col <- @col}>{col[:label]}</th>
          <th :if={@action != []}>
            <span class="sr-only">{gettext("Actions")}</span>
          </th>
        </tr>
      </thead>
      <tbody id={@id} phx-update={is_struct(@rows, Phoenix.LiveView.LiveStream) && "stream"}>
        <tr :for={row <- @rows} id={@row_id && @row_id.(row)}>
          <td
            :for={col <- @col}
            phx-click={@row_click && @row_click.(row)}
            class={@row_click && "hover:cursor-pointer"}
          >
            {render_slot(col, @row_item.(row))}
          </td>
          <td :if={@action != []} class="w-0 font-semibold">
            <div class="flex gap-4">
              <%= for action <- @action do %>
                {render_slot(action, @row_item.(row))}
              <% end %>
            </div>
          </td>
        </tr>
      </tbody>
    </table>
    """
  end

  @doc """
  Renders a data list.

  ## Examples

      <.list>
        <:item title="Title">{@post.title}</:item>
        <:item title="Views">{@post.views}</:item>
      </.list>
  """
  slot :item, required: true do
    attr :title, :string, required: true
  end

  def list(assigns) do
    ~H"""
    <ul class="list">
      <li :for={item <- @item} class="list-row">
        <div class="list-col-grow">
          <div class="font-bold">{item.title}</div>
          <div>{render_slot(item)}</div>
        </div>
      </li>
    </ul>
    """
  end

  @doc """
  Renders a [Heroicon](https://heroicons.com).

  Heroicons come in three styles – outline, solid, and mini.
  By default, the outline style is used, but solid and mini may
  be applied by using the `-solid` and `-mini` suffix.

  You can customize the size and colors of the icons by setting
  width, height, and background color classes.

  Icons are extracted from the `deps/heroicons` directory and bundled within
  your compiled app.css by the plugin in `assets/vendor/heroicons.js`.

  ## Examples

      <.icon name="hero-x-mark" />
      <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
  """
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  ## JS Commands

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
  end

  @doc """
  Translates an error message using gettext.
  """
  def translate_error({msg, opts}) do
    # When using gettext, we typically pass the strings we want
    # to translate as a static argument:
    #
    #     # Translate the number of files with plural rules
    #     dngettext("errors", "1 file", "%{count} files", count)
    #
    # However the error messages in our forms and APIs are generated
    # dynamically, so we need to translate them by calling Gettext
    # with our gettext backend as first argument. Translations are
    # available in the errors.po file (as we use the "errors" domain).
    if count = opts[:count] do
      Gettext.dngettext(WebWeb.Gettext, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(WebWeb.Gettext, "errors", msg, opts)
    end
  end

  @doc """
  Renders a grammar check report panel.
  """
  attr :matches, :list, required: true
  attr :dismiss_event, :string, default: "dismiss_grammar"

  # Styled by the .grammar-panel rules in assets/css/guestbook.css — a sheet of
  # paper from the right edge, shared with the newsletter overlay.
  def grammar_panel(assigns) do
    ~H"""
    <aside :if={@matches} class="grammar-panel" aria-label="Grammar report">
      <div class="grammar-panel-head">
        <h3 class="grammar-panel-title">Grammar report</h3>
        <button
          type="button"
          phx-click={@dismiss_event}
          class="grammar-panel-close"
          aria-label="Close the grammar report"
        >
          &times;
        </button>
      </div>

      <p :if={@matches == []} class="grammar-panel-summary">No issues found.</p>

      <p :if={@matches != []} class="grammar-panel-summary">
        {length(@matches)} {if length(@matches) == 1, do: "issue", else: "issues"} found
      </p>

      <div :for={match <- @matches} class="grammar-match">
        <p class="grammar-match-message">{match["message"]}</p>

        <p class="grammar-match-context">
          …<mark>{String.slice(match["context"]["text"], match["context"]["offset"], match["context"]["length"])}</mark>…
        </p>

        <p :if={match["replacements"] not in [nil, []]} class="grammar-match-suggestions">
          <span class="grammar-match-label">Suggestions</span>
          <span :for={rep <- Enum.take(match["replacements"], 3)} class="grammar-suggestion">
            {rep["value"]}
          </span>
        </p>
      </div>
    </aside>
    """
  end

  @doc """
  Renders a consistent 'Check Grammar' button.
  """
  attr :click_event, :string, default: "check_spelling"
  attr :class, :string, default: nil
  attr :rest, :global

  # A poppy outline at rest (assets/css/guestbook.css): pressable, but not
  # the action the form is for.
  def grammar_button(assigns) do
    ~H"""
    <button type="button" phx-click={@click_event} class={["grammar-button", @class]} {@rest}>
      Check grammar
    </button>
    """
  end

  @doc """
  Translates the errors for a field from a keyword list of errors.
  """
  def translate_errors(errors, field) when is_list(errors) do
    for {^field, {msg, opts}} <- errors, do: translate_error({msg, opts})
  end

  # The wordmark, set by hand rather than by machine: each letter carries its
  # own rotation, baseline shift and kerning nudge. The values are fixed, not
  # random — the logo has to be the same object on every render, in every
  # LiveView diff, on every page — and they are in `em`, so the one table
  # serves the homepage at 5.5rem and the sticky header at 1.4rem without
  # retuning. {letter, rotation, baseline shift, kerning nudge}
  @wordmark [
    {"s", -2.4, 0.014, -0.004},
    {"t", 1.6, -0.012, 0.006},
    {"r", -1.1, 0.020, -0.002},
    {"e", 2.8, -0.006, 0.004},
    {"e", -3.2, 0.016, -0.005},
    {"t", 0.9, -0.014, 0.003},
    {"s", 3.1, 0.008, -0.003},
    {"c", -2.0, -0.010, 0.005},
    {"i", 2.2, 0.018, -0.002},
    {"s", -3.4, -0.008, 0.004},
    {"s", 1.3, 0.012, -0.004},
    {"o", -1.8, -0.016, 0.006},
    {"r", 2.6, 0.010, -0.003},
    {"s", -2.9, -0.004, 0.0}
  ]

  @doc """
  The "streetscissors" wordmark as individually placed letters.

  Renders only the letters — the caller supplies its own heading element and
  sizing, so the homepage overlay and the sticky header stay a single logo.
  Pair with `aria-label="streetscissors"` on that wrapper: split across spans,
  the name is no longer one string for screen readers (or for tests).
  """
  def wordmark(assigns) do
    assigns = assign(assigns, :letters, @wordmark)

    ~H"""
    <span
      :for={{letter, rotation, shift, kern} <- @letters}
      class="wm-l"
      aria-hidden="true"
      style={"--wm-r: #{rotation}deg; --wm-y: #{shift}em; --wm-x: #{kern}em"}
    >
      {letter}
    </span>
    """
  end

  @doc """
  A heavy display line stretched wall to wall and cropped top and bottom —
  the Baker-logo treatment used by the contact-sheet hero and the negatives
  page.

  SVG rather than CSS because `textLength` fills a box exactly at any width,
  where a `scaleX()` factor has to be re-guessed per breakpoint. All geometry
  is passed in because it is **measured** off the rendered font, never guessed:
  each line's `x`/`length` are chosen so its *ink* (not its advance width)
  spans 0..1000, and `viewbox` trims 3.5% off each end of the ink band so the
  letters are cut by 7% and touch all four edges. See the measurement pages in
  the scratchpad, or re-measure with canvas `actualBoundingBox*` metrics —
  `getBBox()` reports the layout box and is useless for this.
  """
  attr :viewbox, :string, required: true
  attr :label, :string, required: true
  attr :class, :string, default: nil
  attr :lines, :list, required: true, doc: "[%{text:, x:, y:, length:}]"

  def baker_wordmark(assigns) do
    ~H"""
    <svg
      class={["baker-wordmark", @class]}
      viewBox={@viewbox}
      preserveAspectRatio="none"
      role="img"
      aria-label={@label}
    >
      <text
        :for={line <- @lines}
        x={line.x}
        y={line.y}
        textLength={line.length}
        lengthAdjust="spacingAndGlyphs"
      >
        {line.text}
      </text>
    </svg>
    """
  end

  @doc """
  Universal header for blog portals and manuscript pages.

  The back link lives here and only here. Blog posts used to carry a second
  one in their own header (`back_link/1`), which read "back to return to
  streetscissors" and duplicated this; that one is gone.
  """
  attr :return_to, :string, default: "/"
  attr :return_label, :string, default: "return to homepage"

  def blog_header(assigns) do
    assigns = assign(assigns, :destination, back_destination(assigns.return_label))

    ~H"""
    <header class="blog-universal-header">
      <div class="header-left">
        <a
          href={@return_to}
          class="header-action header-action--back"
          aria-label={"Back to #{@destination}"}
        >
          <.icon name="hero-arrow-left" class="header-action-icon size-4" />
          <span class="header-action-label">{@destination}</span>
        </a>
      </div>

      <div class="header-center">
        <a href={~p"/"} class="header-logo-container">
          <h1 class="site-title-overlay header-logo" aria-label="streetscissors">
            <.wordmark />
          </h1>
        </a>
      </div>

      <div class="header-right">
        <button
          type="button"
          onclick="window.dispatchEvent(new CustomEvent('trigger-dispatch'))"
          class="header-action header-action--contact"
        >
          <span class="header-action-label">Newsletter &amp; Contact</span>
          <.icon name="hero-envelope" class="header-action-icon size-4" />
        </button>
      </div>
    </header>
    """
  end

  # The arrow already says "back", so the label only has to say where to:
  # "return to captain's logs" reads as "Captain's logs".
  defp back_destination(label) do
    String.replace(label, ~r/^(return|back) to /i, "")
  end
end
