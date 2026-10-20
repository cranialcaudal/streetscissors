defmodule Web.GeneralFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Web.Guestbook` context.
  """

  @doc """
  Generate a guestbook_entry.
  """
  def guestbook_entry_fixture(attrs \\ %{}) do
    attrs =
      Enum.into(attrs, %{
        approved: true,
        message: "some message",
        name: "some name"
      })

    {:ok, entry} = Web.Guestbook.create_guestbook_entry(attrs)

    # create_guestbook_entry/1 deliberately holds every submission, ignoring an
    # `approved` in the params, so go through the real approval path to get a
    # published fixture.
    if attrs[:approved] do
      {:ok, approved} = Web.Guestbook.approve_guestbook_entry(entry)
      approved
    else
      entry
    end
  end
end
