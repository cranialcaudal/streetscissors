defmodule Web.Blog.Embeds do
  @moduledoc """
  Expands Obsidian-style `![[...]]` photo embeds in rendered blog HTML.

  Runs after Earmark — the syntax passes through markdown untouched:

    * `![[roll012]]` / `![[12]]` / `![[roll012_2026-07-31_120_bw]]` —
      whole contact sheet: preview image linked to the full-size scan
    * `![[roll012/3]]` — individual frame scan from the roll folder
    * `![[roll012/3|Caption]]` — same, with a caption
    * `![[ride:123]]` — a Komoot ride card (name, stats, thumbnail)
      linking to the ride page
    * `![[figure:emissions]]` / `![[figure:emissions-cumulative]]` — an
      inline SVG chart rendered from a JSON data file committed under
      `priv/static/figures/`. No JS chart library; the JSON is read and
      the chart built server-side, same as every other embed here. The
      initial render is this static SVG; `![[figure:emissions-controls]]`
      (below) makes it interactive.
    * `![[figure:emissions-controls]]` — a control panel (trip-distance
      frame, food-energy + diet, e-bike grid intensity) plus the same JSON
      inlined as `<script type="application/json">`, so
      `assets/js/emissions_controls.js` can redraw the two figures above
      client-side without a fetch. Vanilla JS, no framework, matching
      `assets/js/biometric_charts.js`.
    * `![[figure:emissions-code]]` — `scripts/emissions.R` (the script that
      generates the JSON above), rendered as a collapsed, syntax-highlighted
      `<details>`. Read at compile time via `@external_resource`, not pasted
      into the post by hand, so it can never drift from the real script. A
      hand-rolled highlighter, not a vendored one — see `highlight_r/1`.

  Unresolvable targets (unknown roll/frame/ride/figure, negatives dir
  missing, or ordinary `![[wikilinks]]`) are left as literal text, so
  posts never render broken images. The pattern also matches inside code
  blocks — avoid the syntax there.
  """

  alias Web.Negatives
  alias Web.Rides
  alias Web.Rides.Units

  @embed_re ~r/!\[\[([^\]\|\n]+?)(?:\|([^\]\n]*))?\]\]/
  @ride_re ~r/\Aride:(\d+)\z/
  @frame_re ~r/\A(?:roll)?0*(\d{1,4})\s*\/\s*0*(\d{1,4})\z/
  @sheet_re ~r/\A(?:roll)?0*(\d{1,4})(?:_[\w-]+)?\z/
  @figure_re ~r/\Afigure:([\w-]+)\z/

  # Figure 1 (bar chart) geometry.
  @bar_chart_width 640
  @bar_row_height 44
  @bar_track_x 150
  @bar_max_track 380

  # Figure 2 (line chart) geometry. Left margin is wide enough for
  # thousands-separated y-axis labels ("82,000 lb"); top margin holds the
  # axis title. Height includes room for a wrapped 2-row legend below the
  # plot (7 modes, 4 per row) — ticks sit right under the axis, the
  # legend below that.
  @line_chart_width 640
  # Ten modes wrap to three legend rows; the third needs room below the plot.
  @line_chart_height 375
  @line_plot_left 72
  @line_plot_right 600
  @line_plot_top 46
  @line_plot_bottom 260
  @legend_top_offset 42
  @legend_row_height 22
  @legend_col_width 140
  @legend_per_row 4

  # One design token per mode, reused for the line, its dots, and its
  # legend swatch via the `--mode-color` custom property set on each
  # series' wrapping `<g>` — see `line_series_svg/3` and `line_legend_svg/1`.
  @mode_color %{
    "walk" => "var(--ink-4)",
    "bicycle" => "var(--color-jade)",
    "e-bike" => "var(--color-dodger)",
    "train" => "var(--ink-2)",
    "bus" => "var(--ink-3)",
    "car" => "var(--color-orange)",
    "pickup" => "var(--color-red)",
    "plane" => "var(--ink)",
    # The three grid modes share the electric blue, lightened by draw so the
    # family reads as one thing on the legend without ten unrelated hues.
    "tesla" => "color-mix(in srgb, var(--color-dodger) 62%, var(--paper))",
    "rivian" => "color-mix(in srgb, var(--color-dodger) 78%, var(--ink))"
  }

  # `scripts/emissions.R` is the single source of truth for the R shown in
  # the post — read once at compile time, not hand-pasted into the
  # markdown, so the two can never drift out of sync (they already have,
  # three times, before this). @external_resource makes Mix recompile this
  # module whenever the script changes.
  #
  # The script belongs to the post, so like the rest of the writing it is not
  # in the public repository. Without it the module still compiles, and the
  # code embed is left as literal text like any other unresolvable target.
  @emissions_r_path Path.join([__DIR__, "..", "..", "..", "scripts", "emissions.R"])
  @external_resource @emissions_r_path
  @emissions_r_source (case File.read(@emissions_r_path) do
                         {:ok, source} -> source
                         {:error, _} -> nil
                       end)

  # Token order matters: strings and comments are matched whole (including
  # any newlines or digits inside them) before the number/keyword
  # alternatives ever get a chance to look inside them.
  @r_token_re ~r/("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|#[^\n]*|\b\d+\.?\d*\b|\b(?:function|library|for|if|in)\b)/
  @r_keywords ~w(function library for if in)

  def transform(html) do
    Regex.replace(@embed_re, html, fn full, target, caption ->
      target = String.trim(target)

      cond do
        Regex.match?(@ride_re, target) -> ride_html(target, caption, full)
        Regex.match?(@frame_re, target) -> frame_html(target, caption, full)
        Regex.match?(@figure_re, target) -> figure_data_html(target, caption, full)
        Regex.match?(@sheet_re, target) -> sheet_html(target, caption, full)
        true -> full
      end
    end)
  end

  defp ride_html(target, caption, full) do
    [_, id] = Regex.run(@ride_re, target)

    case Rides.get_ride(id) do
      nil ->
        full

      ride ->
        thumb =
          if Rides.Thumbs.exists?(ride) do
            ~s(<img src="/fitness/rides/#{ride.id}/thumb" alt="" loading="lazy" />)
          else
            ""
          end

        meta =
          [
            Units.date(ride.started_at),
            Units.distance(ride.distance_m),
            Units.duration(ride.time_in_motion_s || ride.duration_s),
            Units.elevation(ride.ascent_m) <> " ↑"
          ]
          |> Enum.join(" · ")

        inner =
          ~s(<a href="/fitness/rides/#{ride.id}">) <>
            thumb <>
            ~s(<span class="blog-embed-ride-body">) <>
            ~s(<span class="blog-embed-ride-name">#{escape(ride.name || "Untitled ride")}</span>) <>
            ~s(<span class="blog-embed-ride-meta">#{escape(meta)}</span>) <>
            ~s(</span></a>)

        figure(inner, caption, "blog-embed-ride")
    end
  end

  defp frame_html(target, caption, full) do
    [_, roll, frame] = Regex.run(@frame_re, target)

    case Negatives.frame_path(roll, frame) do
      {:ok, _path} ->
        src = "/negatives/frame/roll#{String.pad_leading(roll, 3, "0")}/#{frame}"

        figure(
          ~s(<img src="#{src}" alt="#{alt(caption)}" loading="lazy" />),
          caption,
          "blog-embed-frame"
        )

      :error ->
        full
    end
  end

  defp sheet_html(target, caption, full) do
    case Negatives.sheet_for_roll(target) do
      {:ok, filename} ->
        inner =
          ~s(<a href="/negatives/image/#{filename}">) <>
            ~s(<img src="/negatives/preview/#{filename}" alt="#{alt(caption)}" loading="lazy" /></a>)

        figure(inner, caption, "blog-embed-sheet")

      :error ->
        full
    end
  end

  @known_figures ~w(emissions emissions-cumulative emissions-controls emissions-code)

  defp figure_data_html(target, caption, full) do
    [_, name] = Regex.run(@figure_re, target)

    cond do
      name != "emissions-code" -> figure_data_from_json(name, caption, full)
      # The script lives beside the post, outside the public repository.
      is_nil(@emissions_r_source) -> full
      true -> code_html()
    end
  end

  defp figure_data_from_json(name, caption, full) do
    path = Path.join([:code.priv_dir(:web), "static", "figures", "emissions.json"])

    with true <- name in @known_figures,
         {:ok, json} <- File.read(path),
         {:ok, data} <- Jason.decode(json) do
      case name do
        "emissions-controls" -> controls_html(data)
        _ -> figure(emissions_svg(name, data), caption, "blog-embed-figure")
      end
    else
      _ -> full
    end
  end

  # --- Code: the R script itself, syntax-highlighted -----------------------

  defp code_html do
    ~s(<details class="blog-embed-code">) <>
      ~s[<summary>emissions.R: simple arithmetic on assumed inputs (click to expand)</summary>] <>
      ~s(<pre><code class="language-r">#{highlight_r(@emissions_r_source)}</code></pre>) <>
      ~s(</details>)
  end

  defp highlight_r(source) do
    @r_token_re
    |> Regex.split(source, include_captures: true)
    |> Enum.map_join(&highlight_r_token/1)
  end

  defp highlight_r_token(""), do: ""
  defp highlight_r_token("#" <> _ = token), do: span("r-comment", token)
  defp highlight_r_token(<<?", _::binary>> = token), do: span("r-string", token)
  defp highlight_r_token(<<?', _::binary>> = token), do: span("r-string", token)

  defp highlight_r_token(token) do
    cond do
      Regex.match?(~r/\A\d/, token) -> span("r-number", token)
      token in @r_keywords -> span("r-keyword", token)
      true -> escape(token)
    end
  end

  defp span(class, text), do: ~s(<span class="#{class}">#{escape(text)}</span>)

  # --- Controls: frame/food/grid inputs + the data JS redraws both
  # figures from -----------------------------------------------------------

  defp controls_html(data) do
    # `</` can't appear inside a `<script>` block without prematurely
    # closing it; escaping the slash is valid JSON and defuses that.
    json = data |> Jason.encode!() |> String.replace("</", "<\\/")

    grid_options =
      data["grids"]
      |> Enum.map(fn g ->
        selected = if g["default"], do: " selected", else: ""
        ~s(<option value="#{g["g_per_kwh"]}"#{selected}>#{escape(g["name"])}</option>)
      end)
      |> Enum.join()

    ~s(<div class="blog-embed blog-embed-controls">) <>
      ~s(<div class="emissions-controls" id="emissions-controls">) <>
      ~s(<fieldset class="emissions-control-group">) <>
      ~s(<legend>Trip distance</legend>) <>
      ~s(<label><input type="radio" name="emissions-frame" value="a" checked /> ) <>
      ~s[Same trip (#{data["frame_a_one_way_mi"]} mi)</label>] <>
      ~s(<label><input type="radio" name="emissions-frame" value="b" /> As observed</label>) <>
      ~s(</fieldset>) <>
      ~s(<fieldset class="emissions-control-group">) <>
      ~s(<legend>Food energy</legend>) <>
      ~s(<label><input type="checkbox" id="emissions-food" /> Include food energy</label>) <>
      ~s(<label class="emissions-diet">Diet ) <>
      ~s(<select id="emissions-diet" disabled>) <>
      ~s(<option value="vegetarian">Vegetarian</option>) <>
      ~s(<option value="us_average" selected>US average</option>) <>
      ~s(<option value="beef_heavy">Beef-heavy</option>) <>
      ~s(</select></label>) <>
      ~s(</fieldset>) <>
      ~s(<fieldset class="emissions-control-group">) <>
      ~s(<legend>E-bike grid</legend>) <>
      ~s(<label>Grid <select id="emissions-grid">#{grid_options}</select></label>) <>
      ~s(</fieldset>) <>
      ~s(</div>) <>
      ~s(<script type="application/json" id="emissions-data">#{json}</script>) <>
      ~s(</div>)
  end

  # --- Figure 1: monthly CO2e by mode, 8 mi one-way commute (bar chart) -----

  defp emissions_svg("emissions", data) do
    one_way = data["frame_a_one_way_mi"]
    work_days_month = get_in(data, ["work_days", "month"]) || 20.8333
    kg_to_lb = data["kg_to_lb"]

    rows =
      data["modes"]
      |> Enum.map(fn m ->
        monthly_lb = m["base"] * one_way * 2 * work_days_month / 1000 * kg_to_lb
        %{name: m["name"], sub: m["sub"], type: m["type"], monthly_lb: monthly_lb}
      end)

    max_lb = rows |> Enum.map(& &1.monthly_lb) |> Enum.max()
    height = length(rows) * @bar_row_height + 16

    bars =
      rows
      |> Enum.with_index()
      |> Enum.map(fn {row, i} -> bar_row_svg(row, i, max_lb) end)
      |> Enum.join()

    ~s(<svg class="fig-emissions-bar" viewBox="0 0 #{@bar_chart_width} #{height}" ) <>
      ~s(role="img" aria-label="Pounds of CO2e per month by commute mode, 8-mile one-way trip">) <>
      bars <>
      ~s(</svg>)
  end

  defp emissions_svg("emissions-cumulative", data) do
    cum = data["cumulative"]
    years = cum["years"]
    series = cum["series"]
    n = length(years)
    max_lb = series |> Enum.flat_map(& &1["lb"]) |> Enum.max()
    y_ticks = nice_ticks(max_lb)
    axis_max = List.last(y_ticks)

    xs =
      for i <- 0..(n - 1),
          do: @line_plot_left + i / (n - 1) * (@line_plot_right - @line_plot_left)

    lines = series |> Enum.map(&line_series_svg(&1, xs, axis_max)) |> Enum.join()

    ticks =
      Enum.zip(xs, years)
      |> Enum.map(fn {x, yr} ->
        label = if yr == 1, do: "1 yr", else: "#{yr} yrs"

        ~s(<text x="#{num(x)}" y="#{@line_plot_bottom + 24}" class="fig-line-tick" ) <>
          ~s(text-anchor="middle">#{label}</text>)
      end)
      |> Enum.join()

    # "Higher is worse" spelled out in the title, not left to be inferred --
    # the target reader doesn't need to read a chart to know that.
    ~s(<svg class="fig-emissions-line" viewBox="0 0 #{@line_chart_width} #{@line_chart_height}" ) <>
      ~s(role="img" aria-label="Cumulative pounds of CO2e over #{List.last(years)} years, by mode, ) <>
      ~s(#{data["frame_a_one_way_mi"]}-mile one-way commute, higher is worse">) <>
      ~s[<text x="#{@line_plot_left}" y="20" class="fig-line-axis-title">] <>
      ~s[Cumulative pounds of CO2e (higher is worse)</text>] <>
      y_axis_svg(y_ticks, axis_max) <>
      lines <>
      ticks <>
      line_legend_svg(series) <>
      ~s(</svg>)
  end

  defp y_axis_svg(ticks, axis_max) do
    ticks
    |> Enum.map(fn v ->
      y = line_y(v, axis_max)

      ~s(<line x1="#{@line_plot_left}" y1="#{num(y)}" x2="#{@line_plot_right}" y2="#{num(y)}" ) <>
        ~s(class="fig-line-gridline" />) <>
        ~s(<text x="#{@line_plot_left - 8}" y="#{num(y + 4)}" class="fig-line-ytick" ) <>
        ~s(text-anchor="end">#{format_lb(v)}</text>)
    end)
    |> Enum.join()
  end

  # "Nice" round tick values (0, then multiples of 1/2/5 x a power of ten)
  # instead of dividing the raw max into equal thirds -- round numbers read
  # faster for someone not used to reading charts.
  defp nice_ticks(max_value) when max_value <= 0, do: [0, 1]

  defp nice_ticks(max_value) do
    raw_step = max_value / 4
    magnitude = :math.pow(10, Float.floor(:math.log10(raw_step)))
    normalized = raw_step / magnitude

    nice =
      cond do
        normalized <= 1 -> 1
        normalized <= 2 -> 2
        normalized <= 5 -> 5
        true -> 10
      end

    step = nice * magnitude
    count = Float.ceil(max_value / step) |> trunc()
    for i <- 0..count, do: i * step
  end

  defp format_lb(0), do: "0"

  defp format_lb(v) do
    v
    |> round()
    |> Integer.to_string()
    |> add_thousands_separators()
    |> Kernel.<>(" lb")
  end

  defp add_thousands_separators(digits) do
    digits
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
  end

  defp line_series_svg(s, xs, axis_max) do
    color = mode_color(s["name"])
    points = Enum.zip(xs, s["lb"]) |> Enum.map(fn {x, v} -> {x, line_y(v, axis_max)} end)

    ~s(<g class="fig-line-series" style="--mode-color: #{color}">) <>
      ~s(<polyline points="#{points_to_polyline(points)}" class="fig-line" />) <>
      points_markers(points) <>
      ~s(</g>)
  end

  defp line_legend_svg(series) do
    series
    |> Enum.with_index()
    |> Enum.map(fn {s, i} ->
      col = rem(i, @legend_per_row)
      row = div(i, @legend_per_row)
      x = @line_plot_left + col * @legend_col_width
      y = @line_plot_bottom + @legend_top_offset + row * @legend_row_height
      color = mode_color(s["name"])

      ~s(<g class="fig-legend-item" style="--mode-color: #{color}">) <>
        ~s(<rect x="#{num(x)}" y="#{num(y - 9)}" width="10" height="10" class="fig-legend-swatch" />) <>
        ~s(<text x="#{num(x + 15)}" y="#{num(y)}" class="fig-legend-label">#{escape(s["name"])}</text>) <>
        ~s(</g>)
    end)
    |> Enum.join()
  end

  defp mode_slug(name), do: name |> String.downcase() |> String.replace(" ", "-")
  defp mode_color(name), do: Map.get(@mode_color, mode_slug(name), "var(--ink-3)")

  defp bar_row_svg(row, index, max_lb) do
    y = index * @bar_row_height
    track_w = if max_lb > 0, do: row.monthly_lb / max_lb * @bar_max_track, else: 0
    bar_w = max(track_w, 2)
    bar_y = y + 6
    value = num1(row.monthly_lb)

    # Spelled out, not "kg/mo" -- an abbreviated unit here read as unclear.
    ~s(<g class="fig-bar-row">) <>
      ~s(<text x="0" y="#{y + 18}" class="fig-bar-label">#{escape(row.name)}</text>) <>
      ~s(<text x="0" y="#{y + 32}" class="fig-bar-sub">#{escape(row.sub)}</text>) <>
      ~s(<rect x="#{@bar_track_x}" y="#{bar_y}" width="#{num(bar_w)}" height="20" ) <>
      ~s(class="fig-bar fig-bar-#{row.type}" />) <>
      ~s(<text x="#{num(@bar_track_x + track_w + 8)}" y="#{bar_y + 15}" class="fig-bar-value">) <>
      ~s(#{value} lb/month</text>) <>
      ~s(</g>)
  end

  # --- Figure 2: cumulative CO2e, car vs. bicycle, over years (line chart) --

  defp line_y(value, axis_max) do
    ratio = if axis_max > 0, do: value / axis_max, else: 0
    @line_plot_bottom - ratio * (@line_plot_bottom - @line_plot_top)
  end

  defp points_to_polyline(points) do
    points |> Enum.map(fn {x, y} -> "#{num(x)},#{num(y)}" end) |> Enum.join(" ")
  end

  defp points_markers(points) do
    points
    |> Enum.map(fn {x, y} ->
      ~s(<circle cx="#{num(x)}" cy="#{num(y)}" r="3.5" class="fig-line-dot" />)
    end)
    |> Enum.join()
  end

  defp num(n), do: :erlang.float_to_binary(n / 1, decimals: 2)
  defp num1(n), do: :erlang.float_to_binary(n / 1, decimals: 1)

  defp figure(inner, caption, class) do
    caption_html =
      case String.trim(caption) do
        "" -> ""
        text -> "<figcaption>#{escape(text)}</figcaption>"
      end

    ~s(<figure class="blog-embed #{class}">#{inner}#{caption_html}</figure>)
  end

  defp alt(caption) do
    case String.trim(caption) do
      "" -> "photograph"
      text -> escape(text)
    end
  end

  defp escape(text), do: Plug.HTML.html_escape(text)
end
