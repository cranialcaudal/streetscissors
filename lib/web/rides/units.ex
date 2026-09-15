defmodule Web.Rides.Units do
  @moduledoc """
  Pure display formatting for activities, in Komoot's own vocabulary, usable
  from both the ride LiveViews and lib-layer code like the blog's ride embeds.

  Dates are Pacific-local (via `Web.Clock`): an evening ride saved after
  midnight UTC still belongs to the day it was ridden.
  """

  # Komoot's sport keys → the names Komoot itself shows for them.
  @sports %{
    "racebike" => "Road cycling",
    "touringbicycle" => "Bike touring",
    "mtb" => "Mountain biking",
    "mtb_easy" => "Gravel riding",
    "mtb_advanced" => "Enduro mountain biking",
    "downhillbike" => "Downhill mountain biking",
    "jogging" => "Running",
    "hike" => "Hiking"
  }

  @bikes ~w(racebike touringbicycle mtb mtb_easy mtb_advanced downhillbike)

  def sport(nil), do: "Activity"
  def sport("e_" <> base), do: "E-" <> String.downcase(sport(base))

  def sport(key) do
    Map.get_lazy(@sports, key, fn -> key |> String.replace("_", " ") |> String.capitalize() end)
  end

  @doc "The family a sport is colored by — the same split The Week uses on /fitness."
  def sport_kind("e_" <> base), do: sport_kind(base)
  def sport_kind(key) when key in @bikes, do: "bike"
  def sport_kind("jogging"), do: "run"
  def sport_kind("hike"), do: "hike"
  def sport_kind(_), do: "other"

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

  @doc "`11 Sep 2026` — the Pacific day."
  def date(nil), do: "—"
  def date(%DateTime{} = dt), do: dt |> Web.Clock.local_today() |> Calendar.strftime("%-d %b %Y")

  @doc "`Fri 11 Sep 2026` — the Pacific day, with its weekday."
  def day(nil), do: "—"

  def day(%DateTime{} = dt),
    do: dt |> Web.Clock.local_today() |> Calendar.strftime("%a %-d %b %Y")
end
