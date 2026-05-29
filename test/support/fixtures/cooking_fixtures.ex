defmodule Web.CookingFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Web.Cooking` context.
  """

  @doc """
  Generate a grocery_item.
  """
  def grocery_item_fixture(attrs \\ %{}) do
    {:ok, grocery_item} =
      attrs
      |> Enum.into(%{
        category: "some category",
        description: "some description",
        name: "some name"
      })
      |> Web.Cooking.create_grocery_item()

    grocery_item
  end
end
