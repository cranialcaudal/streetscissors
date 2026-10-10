defmodule WebWeb.LogsLive.Format do
  @moduledoc """
  Display helpers shared by the captain's log index and show views.
  """

  use WebWeb, :verified_routes

  @doc """
  Builds a `/logs` path that preserves the other control's state, so changing
  the sort does not drop an active keyword filter and vice versa. Defaults
  (newest first, no filter) stay out of the query string.
  """
  def logs_path(sort, keyword) do
    params =
      [{"sort", if(sort == "viewed", do: "viewed")}, {"keyword", keyword}]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    if params == [], do: ~p"/logs", else: ~p"/logs?#{params}"
  end

  @doc """
  Renders a duration in seconds as `m:ss`. Returns `nil` for a missing or
  zero duration so callers can skip the field entirely.

      iex> WebWeb.LogsLive.Format.format_duration(252)
      "4:12"
  """
  def format_duration(seconds) when is_integer(seconds) and seconds > 0 do
    "#{div(seconds, 60)}:#{seconds |> rem(60) |> to_string() |> String.pad_leading(2, "0")}"
  end

  def format_duration(_), do: nil

  @doc """
  A span of seconds written the way a runtime is read: `6h 12m`, or `4m` when
  there are no hours to report.

      iex> WebWeb.LogsLive.Format.format_runtime(22_320)
      "6h 12m"
      iex> WebWeb.LogsLive.Format.format_runtime(252)
      "4m"
  """
  def format_runtime(seconds) when is_integer(seconds) and seconds > 0 do
    hours = div(seconds, 3600)
    minutes = seconds |> rem(3600) |> div(60)

    if hours > 0, do: "#{hours}h #{minutes}m", else: "#{minutes}m"
  end

  def format_runtime(_), do: "—"

  @doc """
  One year's line in the footnote: `2026 · 34 entries · 6h 12m`.

  Pluralised by hand for the one case that matters, in the manner of the
  rides archive's mileage footnote.
  """
  def totals_line(year) do
    count = if year.entries == 1, do: "1 entry", else: "#{year.entries} entries"

    Enum.join([year.year, count, format_runtime(year.seconds)], " · ")
  end

  @doc """
  A count the way a video site prints one: exact below a thousand, then
  `1.2K`, `34K`, `1.2M`, cut short rather than rounded up.

      iex> WebWeb.LogsLive.Format.format_count(999)
      "999"
      iex> WebWeb.LogsLive.Format.format_count(1_250)
      "1.2K"
      iex> WebWeb.LogsLive.Format.format_count(34_900)
      "34K"
      iex> WebWeb.LogsLive.Format.format_count(1_000_000)
      "1M"
  """
  def format_count(n) when is_integer(n) and n >= 1_000_000, do: short(n, 1_000_000, "M")
  def format_count(n) when is_integer(n) and n >= 1_000, do: short(n, 1_000, "K")
  def format_count(n) when is_integer(n), do: Integer.to_string(n)

  defp short(n, unit, suffix) do
    whole = div(n, unit)
    tenth = n |> rem(unit) |> div(div(unit, 10))

    if whole < 10 and tenth > 0, do: "#{whole}.#{tenth}#{suffix}", else: "#{whole}#{suffix}"
  end

  @doc """
  A view count with its word: `1 view`, `12 views`, `1.2K views`.

      iex> WebWeb.LogsLive.Format.views_label(1)
      "1 view"
      iex> WebWeb.LogsLive.Format.views_label(0)
      "0 views"
  """
  def views_label(1), do: "1 view"
  def views_label(n), do: "#{format_count(n)} views"

  @doc "Nil for blank strings, so `:if` checks read cleanly in templates."
  def presence(nil), do: nil

  def presence(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: value)
end
