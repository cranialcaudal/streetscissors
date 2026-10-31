defmodule Web.Fitness.Fueling do
  @moduledoc """
  The daily fueling plan, read from `content/fitness/fueling.json`.

  The plan is the author's own (calories, meals, supplements, body figures),
  so it lives in the vault and never in code; a fresh clone has no file and
  the admin page says so. Keys are kept as strings, since the file is input:

      {
        "lede": "…", "totals_note": "…",
        "morning_title": "…", "evening_title": "…",
        "days": {"sunday": {"short", "name", "sessions", "kcal", "protein",
                 "carbs", "fat", "fiber", "water", "sodium", "ph_tabs",
                 "slots": [{"slot", "window", "food", "kcal", …}],
                 "totals": {"kcal", "protein", "carbs", "fat", "fiber"}}, …},
        "morning_supplements": [{"name", "dose", "how", "url"}],
        "evening_supplements": [...],
        "staples": [{"item", "serving", "kcal", "protein", "carbs", "fat", "fiber"}]
      }
  """

  alias Web.Fitness.Vault

  @day_order ~w(sunday monday tuesday wednesday thursday friday saturday)

  @doc "The week's days in the order the page shows them."
  def day_order, do: @day_order

  def path, do: Path.join(Vault.base_path(), "fueling.json")

  @doc """
  The plan, or `:none` when there is no file or it cannot be read. Only the
  days the file has are kept, in week order, in `"day_order"`.
  """
  def load do
    with {:ok, text} <- File.read(path()),
         {:ok, %{"days" => %{} = days} = plan} <- Jason.decode(text) do
      order = Enum.filter(@day_order, &is_map(days[&1]))

      if order == [] do
        :none
      else
        {:ok,
         plan
         |> Map.put("day_order", order)
         |> Map.update("morning_supplements", [], &List.wrap/1)
         |> Map.update("evening_supplements", [], &List.wrap/1)
         |> Map.update("staples", [], &List.wrap/1)}
      end
    else
      _ -> :none
    end
  end
end
