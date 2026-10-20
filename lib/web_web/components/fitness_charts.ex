defmodule WebWeb.FitnessCharts do
  @moduledoc """
  The training block's charts, as inline SVG with no script, in the manner
  of `Web.Blog.Embeds`' figures: round tick values, a line per series with
  a dot per value, and a gap where a week has no value. Colour comes from
  the stylesheet (`.fc-series-N`), never from here, so the same chart reads
  under the admin's tokens and the fitness pages' steel.

  A chart with nothing to draw says so in a sentence instead of drawing an
  empty frame.
  """
  use Phoenix.Component

  @width 640
  @height 220
  @left 52
  @right 624
  @top 16
  @bottom 180

  @doc """
  A line chart over a row of x labels. Each series is
  `%{name: "Hexbar RDL", values: %{x => value}}`, keyed by the same x's as
  `xs` (`[{x, label}]`); a missing x is a gap in the line. `bands` shades
  y ranges (`[{from, to}]`) and `rules` draws y lines (`[value]`).
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :xs, :list, required: true
  attr :series, :list, required: true
  attr :unit, :string, default: ""
  attr :bands, :list, default: []
  attr :rules, :list, default: []
  attr :empty, :string, default: "Nothing logged yet."

  def line_chart(assigns) do
    values = for s <- assigns.series, {_x, v} <- s.values, is_number(v), do: v

    floor =
      Enum.max(
        Enum.map(assigns.rules, &(&1 * 1.0)) ++ Enum.map(assigns.bands, &elem(&1, 1)) ++ [0]
      )

    max = Enum.max(values ++ [floor], fn -> 0 end)
    ticks = nice_ticks(max)
    top = List.last(ticks)
    xs = assigns.xs
    step = if length(xs) > 1, do: (@right - @left) / (length(xs) - 1), else: 0
    x_at = Map.new(Enum.with_index(xs), fn {{x, _label}, i} -> {x, @left + i * step} end)
    y = fn v -> @bottom - if(top > 0, do: v / top, else: 0) * (@bottom - @top) end

    assigns =
      assign(assigns,
        drawable?: values != [],
        ticks: Enum.map(ticks, &{&1, y.(&1)}),
        labels: Enum.map(xs, fn {x, label} -> {label, x_at[x]} end),
        bands: Enum.map(assigns.bands, fn {a, b} -> {y.(b), y.(a) - y.(b)} end),
        rules: Enum.map(assigns.rules, &y.(&1)),
        lines:
          assigns.series
          |> Enum.with_index()
          |> Enum.map(fn {s, i} ->
            points =
              for {x, _} <- xs, v = s.values[x], is_number(v), do: {x_at[x], y.(v)}

            %{name: s.name, index: rem(i, 6), runs: runs(xs, s.values, x_at, y), points: points}
          end),
        w: @width,
        h: @height,
        l: @left,
        r: @right
      )

    ~H"""
    <figure class="fc-chart" id={@id}>
      <figcaption class="fc-title">{@title}</figcaption>
      <%= if @drawable? do %>
        <svg viewBox={"0 0 #{@w} #{@h}"} role="img" aria-label={@title} class="fc-svg">
          <rect
            :for={{y, h} <- @bands}
            x={@l}
            y={num(y)}
            width={@r - @l}
            height={num(h)}
            class="fc-band"
          />
          <g :for={{v, y} <- @ticks}>
            <line x1={@l} x2={@r} y1={num(y)} y2={num(y)} class="fc-grid" />
            <text x={@l - 8} y={num(y + 4)} text-anchor="end" class="fc-tick">{tick(v, @unit)}</text>
          </g>
          <line :for={y <- @rules} x1={@l} x2={@r} y1={num(y)} y2={num(y)} class="fc-rule" />
          <text
            :for={{label, x} <- @labels}
            x={num(x)}
            y={@h - 22}
            text-anchor="middle"
            class="fc-tick"
          >
            {label}
          </text>
          <g :for={line <- @lines} class={"fc-series fc-series-#{line.index}"}>
            <polyline :for={run <- line.runs} points={run} class="fc-line" />
            <circle :for={{x, y} <- line.points} cx={num(x)} cy={num(y)} r="3.5" class="fc-dot" />
          </g>
        </svg>
        <ul :if={length(@lines) > 1} class="fc-legend">
          <li :for={line <- @lines} class={"fc-series fc-series-#{line.index}"}>
            <span class="fc-swatch"></span>{line.name}
          </li>
        </ul>
      <% else %>
        <p class="fc-empty">{@empty}</p>
      <% end %>
    </figure>
    """
  end

  @doc """
  A row of horizontal bars: `[%{label, value, note}]`, the longest bar the
  largest value. `note` is printed after the bar (`"2 of 3"`).
  """
  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :rows, :list, required: true
  attr :max, :any, default: nil
  attr :empty, :string, default: "Nothing logged yet."

  def bar_chart(assigns) do
    max = assigns.max || Enum.max(Enum.map(assigns.rows, & &1.value) ++ [0])
    assigns = assign(assigns, scale: if(max > 0, do: 100 / max, else: 0))

    ~H"""
    <figure class="fc-chart" id={@id}>
      <figcaption class="fc-title">{@title}</figcaption>
      <%= if @rows == [] do %>
        <p class="fc-empty">{@empty}</p>
      <% else %>
        <dl class="fc-bars">
          <div :for={row <- @rows} class="fc-bar-row">
            <dt>{row.label}</dt>
            <dd>
              <span class="fc-bar" style={"width: #{num(max(row.value * @scale, 0.5))}%"}></span>
              <span class="fc-bar-note">{row.note}</span>
            </dd>
          </div>
        </dl>
      <% end %>
    </figure>
    """
  end

  @doc """
  The block's charts from its entries (`Web.Fitness.Training.entries/2`):
  e1RM per lift, volume load per pattern, the prescribed sets done, session
  stress (RPE × minutes) and its acute:chronic ratio, and the ratio per
  pattern, each ratio against its 0.8–1.3 band and 1.5 line.
  `weeks` are the block weeks to draw (`Training.weeks_so_far/2`).
  """
  attr :block, :map, required: true
  attr :entries, :list, required: true
  attr :weeks, :list, required: true
  attr :plan, :map, default: nil

  def block_charts(assigns) do
    alias Web.Fitness.Training

    %{block: block, entries: entries, weeks: weeks} = assigns
    xs = Enum.map(weeks, &{&1, "W#{&1}"})

    lifts =
      for {slug, rule} <- Enum.sort_by(block.lifts, &elem(&1, 0)),
          values = Training.e1rm_by_week(entries, block, slug),
          values != %{},
          do: %{name: lift_name(entries, slug), values: values, pattern: rule.pattern}

    volume = Training.weekly_volume(entries, block)

    volume_series =
      for p <- Training.patterns(),
          Map.has_key?(volume, p),
          do: %{name: pattern_name(p), values: volume[p]}

    acwr = Training.acwr_by_week(entries, block, weeks)

    acwr_series =
      for p <- Training.patterns(),
          Enum.any?(acwr[p], fn {_w, v} -> is_number(v) end),
          do: %{name: pattern_name(p), values: acwr[p]}

    plan = assigns.plan || Training.plan(block)

    compliance =
      for {week, c} <- Enum.sort(Training.compliance(entries, block, weeks, plan)),
          do: %{
            label: "W#{week}",
            value: if(c.sets_planned > 0, do: c.sets_done / c.sets_planned, else: 0),
            note:
              "#{c.sets_done} of #{c.sets_planned} sets · #{c.days_done} of #{c.days_planned} days"
          }

    {stress, stress_ratio} = Training.stress_by_week(entries, block, weeks, plan)

    assigns =
      assign(assigns,
        xs: xs,
        lifts: lifts,
        volume: volume_series,
        acwr: acwr_series,
        compliance: compliance,
        stress: [%{name: "Stress", values: Map.reject(stress, fn {_, v} -> v == 0 end)}],
        stress_ratio: [%{name: "Stress ratio", values: stress_ratio}]
      )

    ~H"""
    <div class="fc-grid-charts">
      <.line_chart
        id="chart-e1rm"
        title="Estimated one-rep max, best each week"
        xs={@xs}
        series={@lifts}
        unit="lb"
      />
      <.line_chart
        id="chart-volume"
        title="Volume load by pattern (sets × reps × weight)"
        xs={@xs}
        series={@volume}
        unit="lb"
      />
      <.bar_chart id="chart-compliance" title="Prescribed sets done" rows={@compliance} max={1} />
      <.line_chart
        id="chart-stress"
        title="Session stress (RPE × minutes), each week"
        xs={@xs}
        series={@stress}
      />
      <.line_chart
        id="chart-stress-ratio"
        title="Stress, acute:chronic (when to deload)"
        xs={@xs}
        series={@stress_ratio}
        bands={[{0.8, 1.3}]}
        rules={[1.5]}
        empty="Needs four weeks of sessions."
      />
      <.line_chart
        id="chart-acwr"
        title="Acute:chronic load (7 days over the 28-day weekly average)"
        xs={@xs}
        series={@acwr}
        bands={[{0.8, 1.3}]}
        rules={[1.5]}
        empty="Needs four weeks of entries for a pattern."
      />
    </div>
    """
  end

  defp lift_name(entries, slug) do
    case Enum.find(entries, &(&1.slug == slug)) do
      %{name: name} -> name
      nil -> slug
    end
  end

  @doc "A movement pattern as words."
  def pattern_name("plyo_locomotion"), do: "Plyo & locomotion"
  def pattern_name(pattern), do: String.capitalize(pattern)

  # A line breaks where a week has no value, so a missed week reads as a
  # gap rather than as a slope between its neighbours.
  defp runs(xs, values, x_at, y) do
    xs
    |> Enum.chunk_by(fn {x, _} -> is_number(values[x]) end)
    |> Enum.filter(fn [{x, _} | _] -> is_number(values[x]) end)
    |> Enum.filter(&(length(&1) > 1))
    |> Enum.map(fn run ->
      Enum.map_join(run, " ", fn {x, _} -> "#{num(x_at[x])},#{num(y.(values[x]))}" end)
    end)
  end

  # Round tick values (multiples of 1, 2 or 5 times a power of ten), as
  # `Web.Blog.Embeds` does for its figures.
  @doc false
  def nice_ticks(max) when max <= 0, do: [0, 1]

  def nice_ticks(max) do
    raw = max / 4
    magnitude = :math.pow(10, Float.floor(:math.log10(raw)))

    step =
      magnitude *
        cond do
          raw / magnitude <= 1 -> 1
          raw / magnitude <= 2 -> 2
          raw / magnitude <= 5 -> 5
          true -> 10
        end

    for i <- 0..trunc(Float.ceil(max / step)), do: clean(i * step)
  end

  defp clean(v) when is_float(v) and v == trunc(v), do: trunc(v)
  defp clean(v) when is_float(v), do: Float.round(v, 2)
  defp clean(v), do: v

  defp tick(v, ""), do: format(v)
  defp tick(v, unit), do: "#{format(v)} #{unit}"

  defp format(v) when is_integer(v) and v >= 1000,
    do:
      v
      |> Integer.to_string()
      |> String.reverse()
      |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
      |> String.reverse()

  defp format(v), do: to_string(v)

  defp num(n), do: :erlang.float_to_binary(n / 1, decimals: 1)
end
