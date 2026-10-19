defmodule WebWeb.AdminLive.Taste do
  @moduledoc """
  Two grades of one print, side by side, and a choice (`/admin/darkroom/taste`):
  the quickest way to teach `Web.Darkroom.Taste`, as the research for it
  found (twenty to forty choices calibrate it, where saving as many edits by
  hand takes far longer).

  A print is drawn at random from the archive. One grade is what the film
  and the taste learned so far suggest (`Prior`, `Taste.predict/4`); the
  other is that grade moved one step along one slider, chosen at random
  (colour only on a colour print). Which is which, and on which side, is not
  shown. The choice is kept (`Taste.choose/4`) as half an edit of that print.
  ← and → choose, ↓ passes.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Darkroom
  alias Web.Darkroom.{Archive, Prior, Session, Taste}

  # The step each slider is moved by for the second grade.
  # The step each slider is moved by for the second grade: large enough to
  # see at a glance, since a choice between near twins teaches little.
  @steps [
    {"light.exposure", 0.5},
    {"light.contrast", 25.0},
    {"light.highlights", 40.0},
    {"light.shadows", 40.0},
    {"light.blacks", 20.0},
    {"effects.clarity", 25.0},
    {"color.vibrance", 25.0},
    {"color.saturation", 15.0},
    {"wb.temp", 900.0},
    {"wb.tint", 12.0}
  ]
  @colour ~w(color.vibrance color.saturation wb.temp wb.tint)

  def mount(_params, session, socket) do
    if session["admin_user"] do
      socket =
        assign(socket,
          page_title: "Taste | Admin",
          pair: nil,
          session: nil,
          left: nil,
          right: nil,
          error: nil,
          token: nil,
          count: length(Taste.choices())
        )

      {:ok, if(connected?(socket), do: next(socket), else: socket)}
    else
      {:ok, push_navigate(socket, to: "/")}
    end
  end

  defp next(socket) do
    if socket.assigns.session, do: Session.stop(socket.assigns.session)

    socket
    |> assign(pair: nil, session: nil, left: nil, right: nil)
    |> start_async(:pair, &draw_pair/0)
  end

  # A print and its two grades, worked out off the page.
  defp draw_pair do
    prints = Archive.prints()

    case prints do
      [] ->
        {:error, "the archive has no prints to show"}

      _ ->
        print = Enum.random(prints)
        groups = Archive.groups(prints)
        model = Taste.fit(prints, groups)
        source = Darkroom.source_path(print.dir, print.frame)
        grey? = print.group == "BW" or print.stats.chroma < 0.004
        taste = Taste.taste_for(model, print.group)

        prior =
          Prior.compute(print.stats, print.group, print.stock, nil, groups[print.group], taste)

        predicted = Taste.predict(model, print.stats, print.group, Taste.condition(print.dir))

        base =
          predicted
          |> Map.merge(round_colour(prior.sliders))
          |> Map.new(fn {k, v} -> {k, v * 1.0} end)

        {:ok, %{print: print, source: source, base: base, grey: grey?}}
    end
  end

  defp round_colour(%{"wb.temp" => temp, "wb.tint" => tint}),
    do: %{"wb.temp" => Float.round(temp / 50) * 50, "wb.tint" => Float.round(tint * 1.0)}

  defp round_colour(_), do: %{}

  def handle_async(:pair, {:ok, {:ok, pair}}, socket) do
    case Session.start(pair.source) do
      {:ok, pid, info} ->
        pair = pair |> Map.put(:schema, info.schema) |> Map.put(:sides, sides(pair, info.schema))
        [{_, left}, _] = pair.sides
        Session.preview(pid, recipe(left, info.schema), 1)
        {:noreply, assign(socket, pair: pair, session: pid, token: info.token, error: nil)}

      {:error, reason} ->
        {:noreply, assign(socket, error: reason)}
    end
  end

  def handle_async(:pair, {:ok, {:error, reason}}, socket),
    do: {:noreply, assign(socket, error: reason)}

  def handle_async(:pair, {:exit, reason}, socket),
    do: {:noreply, assign(socket, error: inspect(reason))}

  # The suggested grade, and the same moved one step along one of the sliders
  # LightCraft has (colour only on a colour print), in a random order.
  defp sides(%{base: base, grey: grey?}, schema) do
    known = MapSet.new(schema, & &1["id"])

    candidates =
      Enum.filter(@steps, fn {id, _} -> id in known and not (grey? and id in @colour) end)

    {id, step} = Enum.random(candidates)
    default = Enum.find_value(schema, 0.0, &(&1["id"] == id && &1["default"]))
    other = Map.put(base, id, Map.get(base, id, default * 1.0) + Enum.random([-1, 1]) * step)
    Enum.shuffle([{:suggested, base}, {:moved, other}])
  end

  defp recipe(controls, schema) do
    %{controls: Darkroom.clean_controls(controls, schema), crop: nil, spots: []}
  end

  # The left grade arrives first, then the right is asked for: the session
  # draws only the newest of what it is asked, so the two go one at a time.
  def handle_info({:darkroom_preview, 1, file}, socket) do
    [_, {_, right}] = socket.assigns.pair.sides
    Session.preview(socket.assigns.session, recipe(right, socket.assigns.pair.schema), 2)
    {:noreply, assign(socket, left: picture(socket, file))}
  end

  def handle_info({:darkroom_preview, 2, file}, socket),
    do: {:noreply, assign(socket, right: picture(socket, file))}

  def handle_info({:darkroom_error, _n, reason}, socket),
    do: {:noreply, assign(socket, error: reason)}

  def handle_info(_message, socket), do: {:noreply, socket}

  defp picture(socket, file), do: ~p"/admin/darkroom/picture/#{socket.assigns.token}/#{file}"

  def handle_event(
        "pick",
        %{"side" => side},
        %{assigns: %{pair: %{} = pair, right: right}} = socket
      )
      when is_binary(right) do
    [{_, left_grade}, {_, right_grade}] = pair.sides

    {chosen, other} =
      if side == "left", do: {left_grade, right_grade}, else: {right_grade, left_grade}

    schema = pair.schema

    Taste.choose(
      pair.print.roll,
      pair.print.frame,
      Darkroom.clean_controls(chosen, schema),
      Darkroom.clean_controls(other, schema)
    )

    {:noreply, socket |> assign(count: socket.assigns.count + 1) |> next()}
  end

  def handle_event("pick", _params, socket), do: {:noreply, socket}
  def handle_event("pass", _params, socket), do: {:noreply, next(socket)}

  def handle_event("key", %{"key" => "ArrowLeft"}, socket),
    do: handle_event("pick", %{"side" => "left"}, socket)

  def handle_event("key", %{"key" => "ArrowRight"}, socket),
    do: handle_event("pick", %{"side" => "right"}, socket)

  def handle_event("key", %{"key" => "ArrowDown"}, socket), do: handle_event("pass", %{}, socket)
  def handle_event("key", _params, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <.page_head slug="Darkroom / Taste" title="Which do you prefer?">
      <:lede>
        Two grades of one print. Choose the one you like better; each choice teaches the
        suggestion in the print editor. Twenty to forty choices set it.
      </:lede>
      <:actions>
        <span class="adm-taste-count" role="status">
          {@count} {if @count == 1, do: "choice", else: "choices"} so far
        </span>
      </:actions>
    </.page_head>

    <div class="adm-taste" phx-window-keydown="key" phx-throttle="300">
      <div :if={@error} class="adm-taste-note" role="alert">
        <p class="adm-dr-error">{@error}</p>
        <button type="button" phx-click="pass" class="adm-btn adm-btn--small">Try again</button>
      </div>
      <p :if={!@error and is_nil(@pair)} class="adm-taste-note adm-dr-hint" role="status">
        Choosing a print…
      </p>

      <div :if={@pair} class="adm-taste-pair">
        <button
          type="button"
          phx-click="pick"
          phx-value-side="left"
          class="adm-taste-side"
          disabled={is_nil(@right)}
          aria-label="This one (left arrow)"
        >
          <span class="adm-taste-picture">
            <img :if={@left} src={@left} alt="The first grade" />
            <span :if={!@left} class="adm-dr-hint">Drawing…</span>
          </span>
          <span class="adm-taste-choose">
            <kbd class="adm-taste-key" aria-hidden="true">←</kbd> This one
          </span>
        </button>
        <button
          type="button"
          phx-click="pick"
          phx-value-side="right"
          class="adm-taste-side"
          disabled={is_nil(@right)}
          aria-label="This one (right arrow)"
        >
          <span class="adm-taste-picture">
            <img :if={@right} src={@right} alt="The second grade" />
            <span :if={!@right} class="adm-dr-hint">Drawing…</span>
          </span>
          <span class="adm-taste-choose">
            This one <kbd class="adm-taste-key" aria-hidden="true">→</kbd>
          </span>
        </button>
      </div>

      <div :if={@pair} class="adm-taste-foot">
        <span class="adm-taste-print">
          Roll <span class="adm-dr-fig">{@pair.print.roll}</span>, frame
          <span class="adm-dr-fig">{@pair.print.frame}</span>
        </span>
        <span class="adm-taste-keys" aria-hidden="true">
          <kbd class="adm-taste-key">←</kbd> <kbd class="adm-taste-key">→</kbd> choose
        </span>
        <button type="button" phx-click="pass" class="adm-btn adm-btn--small">
          Neither <kbd class="adm-taste-key" aria-hidden="true">↓</kbd>
        </button>
      </div>
    </div>
    """
  end
end
