defmodule WebWeb.FitnessWeek do
  @moduledoc """
  "The Week" on /fitness — the big picture above the day-by-day regimen.

  Two renderings, chosen server-side by `timed`:

    * visitors get each day's blocks as chips, in order, with no clock times
      anywhere in the markup. /fitness is public, and it must not say when
      anyone is out of the house — the same rule `Web.Fitness.VaultTest` holds
      the regimen to;
    * the admin gets the timed view: an hour axis, the sleep band, and blocks
      laid out along the day.

  Rows carry `data-week-day`, never `data-day`: the GymRoutine hook keys saved
  checkbox ticks on `data-day` inside #weekly-routine.
  """
  use Phoenix.Component

  alias Web.Fitness.Week

  @legend [
    work: "Work",
    swim: "Swim",
    bike: "Bike",
    run: "Run",
    strength: "Strength",
    play: "Play",
    stretch: "Stretch"
  ]

  attr :week, :map, required: true
  attr :today_slug, :string, default: nil
  attr :timed, :boolean, default: false

  def week(assigns) do
    assigns =
      assigns
      |> assign(:legend, @legend)
      |> assign(:ticks, ticks(assigns.week.window))
      |> assign(:sleep, sleep_segments(assigns.week))

    ~H"""
    <section id="the-week" class={["blog-bento-card", "week", @timed && "week--timed"]}>
      <h2 class="week-title">The Week</h2>

      <div :if={@timed} class="week-axis" aria-hidden="true">
        <span :for={{label, left} <- @ticks} class="week-tick" style={"left: #{left}%"}>{label}</span>
      </div>

      <ol class="week-rows">
        <li
          :for={day <- @week.days}
          data-week-day={day.slug}
          class={["week-row", day.slug == @today_slug && "is-today"]}
        >
          <span class="week-day">{String.slice(day.name, 0, 3)}</span>

          <div :if={@timed} class="week-track">
            <span
              :for={{left, width} <- @sleep}
              class="week-sleep"
              style={"left: #{left}%; width: #{width}%"}
            >
            </span>
            <span
              :for={block <- day.blocks}
              class={"week-block week-block--#{block.kind}"}
              style={position(@week.window, block)}
              title={"#{block.label} #{Week.span(block)}"}
            >
              <span class="week-block-label">{block.label}</span>
            </span>
          </div>

          <ul class="week-chips">
            <li
              :for={block <- day.blocks}
              class={"week-chip week-chip--#{block.kind}"}
              title={block.label}
            >
              {block.label}<span :if={@timed} class="week-chip-time">{Week.span(block)}</span>
            </li>
          </ul>
        </li>
      </ol>

      <ul class="week-legend">
        <li :for={{kind, label} <- @legend} class={"week-chip week-chip--#{kind}"}>{label}</li>
        <li :if={@timed} class="week-chip week-chip--sleep">Sleep {sleep_span(@week)}</li>
      </ul>
    </section>
    """
  end

  # Hour marks every three hours inside the window: 6a, 9a, 12p, 3p, 6p, 9p.
  defp ticks({from, to}) do
    (div(from + 179, 180) * 180)
    |> Stream.iterate(&(&1 + 180))
    |> Enum.take_while(&(&1 < to))
    |> Enum.map(&{tick_label(&1), pct(&1 - from, to - from)})
  end

  defp tick_label(minutes) do
    hour = div(minutes, 60)
    "#{rem(hour + 11, 12) + 1}#{if hour < 12, do: "a", else: "p"}"
  end

  defp position({from, to}, %{start: start, stop: stop}) do
    s = start |> max(from) |> min(to)
    e = stop |> max(from) |> min(to)
    "left: #{pct(s - from, to - from)}%; width: #{pct(e - s, to - from)}%"
  end

  # The sleep band clipped to the window. Sleep usually wraps midnight
  # (21:00-05:30), which leaves a sliver at each end of the drawn day.
  defp sleep_segments(%{sleep: {bed, wake}, window: {from, to}}) do
    spans = if bed > wake, do: [{0, wake}, {bed, 24 * 60}], else: [{bed, wake}]

    spans
    |> Enum.map(fn {s, e} -> {max(s, from), min(e, to)} end)
    |> Enum.filter(fn {s, e} -> e > s end)
    |> Enum.map(fn {s, e} -> {pct(s - from, to - from), pct(e - s, to - from)} end)
  end

  defp sleep_span(%{sleep: {bed, wake}}), do: Week.span(%{start: bed, stop: wake})

  defp pct(part, whole), do: :erlang.float_to_binary(part * 100 / whole, decimals: 3)
end
