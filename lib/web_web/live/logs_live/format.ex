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

  @doc "Nil for blank strings, so `:if` checks read cleanly in templates."
  def presence(nil), do: nil

  def presence(value) when is_binary(value),
    do: if(String.trim(value) == "", do: nil, else: value)
end
