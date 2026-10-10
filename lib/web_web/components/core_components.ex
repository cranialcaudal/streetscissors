defmodule WebWeb.CoreComponents do
  @moduledoc """
  The components any page may use: flash notices, form inputs, icons, the
  grammar report, the wordmarks and the header every public page carries.

  This began as the Phoenix generator's file. What the site never called
  (`button`, `modal`, `simple_form`, `table`, `list`, `header`) is gone, and so
  is daisyUI, whose class names those leaned on.

  Styling is hand-written CSS in `assets/css/`. Tailwind is imported with
  `source(none)`, so a utility class exists only when `assets/css/app.css`
  names it in a `@source inline(...)` line. That is also true of icons: a new
  `hero-*` name has to be added there or it draws nothing.

    * `input/1` keeps the generator's class names (`fieldset`, `label`,
      `input`, `select`); each page that has a form styles them in its own
      sheet (`admin.css`, `letters.css`).

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

  Styled by hand in `assets/css/flash.css`: Tailwind runs with `source(none)`,
  so the generator's daisyUI `toast`/`alert` classes never existed here and a
  notice printed as bare text. An error is an alert; anything else a status.

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
      role={if @kind == :error, do: "alert", else: "status"}
      class={["flash-notice", "flash-notice--#{@kind}"]}
      {@rest}
    >
      <div class="flash-notice-body">
        <div class="flash-notice-text">
          <p :if={@title} class="flash-notice-title">{@title}</p>
          <p class="flash-notice-message">{msg}</p>
        </div>
        <%!-- Only the button dismisses, so the message itself can be selected. --%>
        <button
          type="button"
          class="flash-notice-close"
          aria-label={gettext("close")}
          phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
        >
          <.icon name="hero-x-mark" class="flash-notice-close-icon" />
        </button>
      </div>
    </div>
    """
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
          data-back
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
        <%!-- A square at every width: the two worded controls are a matched
              pair, and a third word would push the wordmark off its line. --%>
        <a href={~p"/search"} class="header-action header-action--search" aria-label="Search">
          <.icon name="hero-magnifying-glass" class="header-action-icon size-4" />
        </a>
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
