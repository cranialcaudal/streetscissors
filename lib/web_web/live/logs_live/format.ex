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
      [{"sort", if(sort == "witnessed", do: "witnessed")}, {"keyword", keyword}]
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

  @doc "Nil for blank strings, so `:if` checks read cleanly in templates."
  def presence(nil), do: nil

  def presence(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: value)
end
