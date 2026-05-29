defmodule Web.GeneralFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Web.General` context.
  """

  @doc """
  Generate a guestbook_entry.
  """
  def guestbook_entry_fixture(attrs \\ %{}) do
    {:ok, guestbook_entry} =
      attrs
      |> Enum.into(%{
        approved: true,
        message: "some message",
        name: "some name"
      })
      |> Web.General.create_guestbook_entry()

    guestbook_entry
  end
end
