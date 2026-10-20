defmodule Web.Fitness.Entry do
  @moduledoc """
  A log form's fields as an entry: the rules both places that log share, the
  day page (`WebWeb.FitnessLive.Index`) and the quick add
  (`WebWeb.AdminLive.QuickAdd`), so an entry reads the same whichever wrote it.
  """

  @doc """
  The form's fields as the `metrics` map the CSV export reads: strings like
  "35 lbs", "3", "45 sec", "40 m", "20 in". A typed weight wins over the
  stepped one; a field left at its blank is no value.
  """
  def metrics(params) do
    weight =
      case {blank(params["weight_other"]), blank(params["weight"])} do
        {typed, _} when is_binary(typed) -> String.trim(typed)
        {nil, "0"} -> nil
        {nil, picked} when is_binary(picked) -> "#{picked} lbs"
        _ -> nil
      end

    %{}
    |> put("weight", weight)
    |> put("sets", params["sets"])
    |> put("reps", params["reps"])
    |> put("rpe", params["rpe"])
    |> put("time", params["seconds"] |> blank() |> suffix(" sec") || params["time"])
    |> put("distance", params["metres"] |> blank() |> suffix(" m") || params["distance"])
    |> put("result", params["height"] |> blank() |> suffix(" in") || params["result"])
  end

  @doc """
  The day an entry is filed under: the day it is here, not in Greenwich (an
  evening session was being filed under tomorrow), unless the form names an
  earlier one. A later or unreadable date is today.
  """
  def date(value) do
    today = Web.Clock.local_today()

    with "" <> text <- value,
         {:ok, date} <- Date.from_iso8601(text),
         true <- Date.compare(date, today) != :gt do
      date
    else
      _ -> today
    end
  end

  defp suffix(nil, _unit), do: nil
  defp suffix(value, unit), do: value <> unit

  defp put(map, _key, nil), do: map
  defp put(map, _key, ""), do: map
  defp put(map, key, value), do: Map.put(map, key, String.trim(value))

  defp blank(nil), do: nil
  defp blank(""), do: nil
  defp blank(value), do: value
end
