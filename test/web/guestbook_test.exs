defmodule Web.GuestbookTest do
  use Web.DataCase

  alias Web.Guestbook

  describe "guestbook_entries" do
    alias Web.Guestbook.GuestbookEntry

    import Web.GeneralFixtures

    @invalid_attrs %{message: nil, name: nil, approved: nil}

    test "list_guestbook_entries/0 returns all guestbook_entries" do
      guestbook_entry = guestbook_entry_fixture()
      assert Guestbook.list_guestbook_entries() == [guestbook_entry]
    end

    test "get_guestbook_entry!/1 returns the guestbook_entry with given id" do
      guestbook_entry = guestbook_entry_fixture()
      assert Guestbook.get_guestbook_entry!(guestbook_entry.id) == guestbook_entry
    end

    test "create_guestbook_entry/1 with valid data creates a guestbook_entry" do
      valid_attrs = %{message: "some message", name: "some name"}

      assert {:ok, %GuestbookEntry{} = guestbook_entry} =
               Guestbook.create_guestbook_entry(valid_attrs)

      assert guestbook_entry.message == "some message"
      assert guestbook_entry.name == "some name"
    end

    test "create_guestbook_entry/2 keeps a hash of the sender's address, never the address" do
      ip = "203.0.113.5"
      assert {:ok, entry} = Guestbook.create_guestbook_entry(%{message: "hi", name: "a"}, ip)

      assert entry.ip_hash == Web.Analytics.hash_ip(ip)
      refute Map.has_key?(Map.from_struct(entry), :ip_address)
      refute inspect(Repo.reload!(entry)) =~ ip
    end

    test "create_guestbook_entry/1 holds the entry for approval" do
      # Submissions used to publish instantly — anything past the captcha was
      # live before a human saw it, with delete-after-the-fact as the only fix.
      assert {:ok, entry} = Guestbook.create_guestbook_entry(%{message: "hi", name: "spammer"})
      refute entry.approved
      assert Guestbook.list_approved_guestbook_entries() == []
    end

    test "create_guestbook_entry/1 cannot self-approve via the submitted params" do
      assert {:ok, entry} =
               Guestbook.create_guestbook_entry(%{
                 message: "hi",
                 name: "spammer",
                 approved: true
               })

      refute entry.approved
    end

    test "approve_guestbook_entry/1 publishes and broadcasts" do
      Guestbook.subscribe_guestbook()
      {:ok, entry} = Guestbook.create_guestbook_entry(%{message: "hello", name: "friend"})

      assert {:ok, approved} = Guestbook.approve_guestbook_entry(entry)
      assert approved.approved
      assert_receive {:guestbook_entry_created, %GuestbookEntry{id: id}}
      assert id == entry.id
      assert [%GuestbookEntry{}] = Guestbook.list_approved_guestbook_entries()
    end

    # The page went empty when its last signature turned 61 days old.
    test "an approved signature stays on the page however old it is" do
      old =
        Web.Repo.insert!(%GuestbookEntry{
          name: "sean",
          message: "Your Hired!",
          approved: true,
          inserted_at: ~U[2026-01-12 17:50:02Z],
          updated_at: ~U[2026-01-12 17:50:02Z]
        })

      {:ok, recent} = Guestbook.create_guestbook_entry(%{message: "hello", name: "friend"})
      {:ok, recent} = Guestbook.approve_guestbook_entry(recent)

      # Newest first.
      assert Enum.map(Guestbook.list_approved_guestbook_entries(), & &1.id) == [recent.id, old.id]
    end

    test "unapprove_guestbook_entry/1 pulls it back off the public page" do
      {:ok, entry} = Guestbook.create_guestbook_entry(%{message: "hello", name: "friend"})
      {:ok, entry} = Guestbook.approve_guestbook_entry(entry)

      assert {:ok, entry} = Guestbook.unapprove_guestbook_entry(entry)
      refute entry.approved
      assert Guestbook.list_approved_guestbook_entries() == []
    end

    test "create_guestbook_entry/1 with invalid data returns error changeset" do
      assert {:error, %Ecto.Changeset{}} = Guestbook.create_guestbook_entry(@invalid_attrs)
    end

    test "create_guestbook_entry/1 bounds the field lengths" do
      assert {:error, changeset} =
               Guestbook.create_guestbook_entry(%{
                 name: "ok",
                 message: String.duplicate("x", 2_001)
               })

      assert %{message: [_ | _]} = errors_on(changeset)

      assert {:error, changeset} =
               Guestbook.create_guestbook_entry(%{name: String.duplicate("x", 81), message: "ok"})

      assert %{name: [_ | _]} = errors_on(changeset)
    end

    test "create_guestbook_entry/1 rejects whitespace-only input" do
      assert {:error, changeset} = Guestbook.create_guestbook_entry(%{name: "   ", message: "  "})
      assert errors_on(changeset)[:name]
    end

    test "update_guestbook_entry/2 with valid data updates the guestbook_entry" do
      guestbook_entry = guestbook_entry_fixture()

      update_attrs = %{
        message: "some updated message",
        name: "some updated name",
        approved: false
      }

      assert {:ok, %GuestbookEntry{} = guestbook_entry} =
               Guestbook.update_guestbook_entry(guestbook_entry, update_attrs)

      assert guestbook_entry.message == "some updated message"
      assert guestbook_entry.name == "some updated name"
      assert guestbook_entry.approved == false
    end

    test "update_guestbook_entry/2 with invalid data returns error changeset" do
      guestbook_entry = guestbook_entry_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Guestbook.update_guestbook_entry(guestbook_entry, @invalid_attrs)

      assert guestbook_entry == Guestbook.get_guestbook_entry!(guestbook_entry.id)
    end

    test "delete_guestbook_entry/1 deletes the guestbook_entry" do
      guestbook_entry = guestbook_entry_fixture()
      assert {:ok, %GuestbookEntry{}} = Guestbook.delete_guestbook_entry(guestbook_entry)

      assert_raise Ecto.NoResultsError, fn ->
        Guestbook.get_guestbook_entry!(guestbook_entry.id)
      end
    end

    test "change_guestbook_entry/1 returns a guestbook_entry changeset" do
      guestbook_entry = guestbook_entry_fixture()
      assert %Ecto.Changeset{} = Guestbook.change_guestbook_entry(guestbook_entry)
    end
  end
end
