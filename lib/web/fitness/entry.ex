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

  @doc """
  An entry's sets one by one, `[%{"w" => lbs | nil, "r" => reps, "rpe" => n | nil}]`:
  the list the day page's set chips keep under `set_list`, else the summary
  read back as that many equal sets (the hardest RPE on the last).
  """
  def set_list(%{"set_list" => list}) when is_list(list), do: list

  def set_list(metrics) when is_map(metrics) do
    case Web.Fitness.Progression.parse_log_metrics(metrics) do
      %{sets: sets, reps: reps} = parsed when is_integer(sets) and is_integer(reps) ->
        for i <- 1..sets,
            do: %{"w" => parsed.weight, "r" => reps, "rpe" => if(i == sets, do: parsed.rpe)}

      _ ->
        []
    end
  end

  def set_list(_metrics), do: []

  @doc """
  Sets as an entry's `metrics`: the list whole under `set_list`, beside the
  summary the export, `Progression` and the entry's line read. The summary
  is the heaviest weight, the number of sets, the fewest reps (so "every set
  reached the top of the range" is true only when every set did) and the
  hardest RPE.
  """
  def sets_metrics(sets) do
    weights = for %{"w" => w} <- sets, is_number(w) and w > 0, do: w
    reps = for %{"r" => r} <- sets, is_integer(r), do: r
    rpes = for %{"rpe" => rpe} <- sets, is_number(rpe), do: rpe

    %{"set_list" => sets, "sets" => Integer.to_string(length(sets))}
    |> put_summary("weight", weights != [] && "#{number(Enum.max(weights))} lbs")
    |> put_summary("reps", reps != [] && Integer.to_string(Enum.min(reps)))
    |> put_summary("rpe", rpes != [] && number(Enum.max(rpes)))
  end

  @doc "`135.0` as `\"135\"`, `47.5` as `\"47.5\"`."
  def number(n) when is_float(n) and n == trunc(n), do: Integer.to_string(trunc(n))
  def number(n), do: to_string(n)

  defp put_summary(map, _key, false), do: map
  defp put_summary(map, key, value), do: Map.put(map, key, value)

  defp suffix(nil, _unit), do: nil
  defp suffix(value, unit), do: value <> unit

  defp put(map, _key, nil), do: map
  defp put(map, _key, ""), do: map
  defp put(map, key, value), do: Map.put(map, key, String.trim(value))

  defp blank(nil), do: nil
  defp blank(""), do: nil
  defp blank(value), do: value
end
