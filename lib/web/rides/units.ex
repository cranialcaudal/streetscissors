defmodule Web.Rides.Units do
  @moduledoc """
  Pure display formatting for ride stats, usable from both the web layer
  (via `WebWeb.RidesLive.Format` delegates) and lib-layer code like the
  blog's ride embeds.
  """

  def distance(nil), do: "—"

  def distance(meters) do
    miles = meters / 1609.344
    "#{:erlang.float_to_binary(miles, decimals: 1)} mi"
  end

  def duration(nil), do: "—"

  def duration(seconds) do
    hours = div(seconds, 3600)
    minutes = div(rem(seconds, 3600), 60)

    if hours > 0,
      do: "#{hours}h #{String.pad_leading(to_string(minutes), 2, "0")}m",
      else: "#{minutes}m"
  end

  def speed(nil), do: "—"

  def speed(mps) do
    mph = mps * 2.236936
    "#{:erlang.float_to_binary(mph, decimals: 1)} mph"
  end

  def elevation(nil), do: "—"

  def elevation(meters) do
    feet = round(meters * 3.28084)

    feet
    |> to_string()
    |> String.reverse()
    |> String.replace(~r/(\d{3})(?=\d)/, "\\1,")
    |> String.reverse()
    |> Kernel.<>(" ft")
  end

  def date(nil), do: "—"
  def date(%DateTime{} = dt), do: Calendar.strftime(dt, "%-d %b %Y")

  def time(nil), do: "—"
  def time(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M")
end
