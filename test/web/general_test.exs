defmodule Web.GeneralTest do
  use Web.DataCase

  alias Web.General

  describe "guestbook_entries" do
    alias Web.General.GuestbookEntry

    import Web.GeneralFixtures

    @invalid_attrs %{message: nil, name: nil, approved: nil}

    test "list_guestbook_entries/0 returns all guestbook_entries" do
      guestbook_entry = guestbook_entry_fixture()
      assert General.list_guestbook_entries() == [guestbook_entry]
    end

    test "get_guestbook_entry!/1 returns the guestbook_entry with given id" do
      guestbook_entry = guestbook_entry_fixture()
      assert General.get_guestbook_entry!(guestbook_entry.id) == guestbook_entry
    end

    test "create_guestbook_entry/1 with valid data creates a guestbook_entry" do
      valid_attrs = %{message: "some message", name: "some name", approved: true}

      assert {:ok, %GuestbookEntry{} = guestbook_entry} =
               General.create_guestbook_entry(valid_attrs)

      assert guestbook_entry.message == "some message"
      assert guestbook_entry.name == "some name"
      assert guestbook_entry.approved == true
    end

    test "create_guestbook_entry/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = General.create_guestbook_entry(@invalid_attrs)
    end

    test "update_guestbook_entry/2 with valid data updates the guestbook_entry" do
      guestbook_entry = guestbook_entry_fixture()

      update_attrs = %{
        message: "some updated message",
        name: "some updated name",
        approved: false
      }

      assert {:ok, %GuestbookEntry{} = guestbook_entry} =
               General.update_guestbook_entry(guestbook_entry, update_attrs)

      assert guestbook_entry.message == "some updated message"
      assert guestbook_entry.name == "some updated name"
      assert guestbook_entry.approved == false
    end

    test "update_guestbook_entry/2 with invalid data returns error changeset" do
      guestbook_entry = guestbook_entry_fixture()

      assert {:error, %Ecto.Changeset{}} =
               General.update_guestbook_entry(guestbook_entry, @invalid_attrs)

      assert guestbook_entry == General.get_guestbook_entry!(guestbook_entry.id)
    end

    test "delete_guestbook_entry/1 deletes the guestbook_entry" do
      guestbook_entry = guestbook_entry_fixture()
      assert {:ok, %GuestbookEntry{}} = General.delete_guestbook_entry(guestbook_entry)
      assert_raise Ecto.NoResultsError, fn -> General.get_guestbook_entry!(guestbook_entry.id) end
    end

    test "change_guestbook_entry/1 returns a guestbook_entry changeset" do
      guestbook_entry = guestbook_entry_fixture()
      assert %Ecto.Changeset{} = General.change_guestbook_entry(guestbook_entry)
    end
  end
end
