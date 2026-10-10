defmodule Web.GuestbookContactTest do
  @moduledoc """
  The optional email address or phone number left with a signature
  (`Web.General.Contact`). Each test is one plank of the fence around it.
  """
  use WebWeb.ConnCase

  import Ecto.Query
  import Phoenix.LiveViewTest
  use Oban.Testing, repo: Web.Repo
  import Web.DataCase, only: [errors_on: 1]

  alias Web.General
  alias Web.General.{Contact, GuestbookEntry}

  @email "hunter@example.com"
  @phone "+1 (530) 555-0142"

  defp sign(attrs \\ %{}) do
    General.create_guestbook_entry(Map.merge(%{name: "Hunter", message: "hey :)"}, attrs))
  end

  defp stored(id) do
    Web.Repo.one(from g in "guestbook_entries", where: g.id == ^id, select: g.contact_sealed)
  end

  describe "leaving one is optional" do
    test "a signature without a contact is a signature" do
      assert {:ok, entry} = sign()
      refute entry.has_contact
      assert stored(entry.id) == nil
      assert General.guestbook_contact(entry.id) == :none

      assert {:ok, blank} = sign(%{contact: "   "})
      assert stored(blank.id) == nil
    end

    test "an email address or a phone number is taken; a sentence is not" do
      for contact <- [@email, @phone, "530.555.0142", "07700 900123", "555-0142 x12"] do
        assert {:ok, %{has_contact: true}} = sign(%{contact: contact}), contact
      end

      for contact <- ["call me maybe", "hunter at example", "12345", String.duplicate("9", 40)] do
        assert {:error, changeset} = sign(%{contact: contact})
        assert %{contact: [_ | _]} = errors_on(changeset)
      end

      long = String.duplicate("a", 120) <> "@example.com"
      assert {:error, changeset} = sign(%{contact: long})
      assert %{contact: [_ | _]} = errors_on(changeset)
    end
  end

  describe "kept away" do
    test "the database holds ciphertext, never the address" do
      {:ok, entry} = sign(%{contact: @email})
      sealed = stored(entry.id)

      assert is_binary(sealed)
      refute sealed =~ "hunter"
      refute sealed =~ "example.com"

      # Nowhere in the row, in any column.
      row = Web.Repo.query!("select * from guestbook_entries where id = ?", [entry.id]).rows
      refute inspect(row) =~ "hunter@example"

      # The same address sealed twice is not the same bytes.
      {:ok, again} = sign(%{contact: @email})
      refute stored(again.id) == sealed
    end

    test "what creating a signature hands back carries no contact, open or sealed" do
      General.subscribe_guestbook_admin()
      {:ok, entry} = sign(%{contact: @phone})

      assert entry.has_contact
      assert entry.contact == nil
      assert entry.contact_sealed == nil

      # Nor does what the admin's queue is sent.
      assert_receive {:guestbook_entry_held, held}
      assert held.contact == nil and held.contact_sealed == nil
      refute inspect(held, limit: :infinity) =~ "555"
    end

    test "no ordinary read loads it: not one entry, not the public list, not the admin's" do
      {:ok, entry} = sign(%{contact: @email})

      {:ok, _} =
        entry |> then(&General.get_guestbook_entry!(&1.id)) |> General.approve_guestbook_entry()

      for loaded <-
            [General.get_guestbook_entry!(entry.id)] ++
              General.list_approved_guestbook_entries() ++
              General.list_all_guestbook_entries() ++ General.list_guestbook_entries() do
        assert loaded.contact_sealed == nil
        assert loaded.contact == nil
      end

      # The admin's list knows that there is one, and nothing more.
      assert [%{has_contact: true}] = General.list_all_guestbook_entries()
    end

    test "approving, unpublishing and editing a signature leave its contact as it was" do
      {:ok, entry} = sign(%{contact: @email})
      sealed = stored(entry.id)

      {:ok, approved} =
        entry.id |> General.get_guestbook_entry!() |> General.approve_guestbook_entry()

      {:ok, _} = General.unapprove_guestbook_entry(approved)

      assert stored(entry.id) == sealed
      assert General.guestbook_contact(entry.id) == {:ok, @email}
    end

    test "an inspected entry or changeset shows it redacted" do
      changeset =
        GuestbookEntry.changeset(%GuestbookEntry{}, %{name: "a", message: "b", contact: @email})

      refute inspect(changeset, limit: :infinity) =~ "hunter@"
      refute inspect(Ecto.Changeset.apply_changes(changeset), limit: :infinity) =~ "hunter@"
      refute inspect(GuestbookEntry.seal(changeset), limit: :infinity) =~ "hunter@"
    end

    test "the form's field is filtered out of logged parameters" do
      assert Phoenix.Logger.filter_values(%{
               "guestbook_entry" => %{"name" => "Hunter", "contact" => @email}
             }) == %{"guestbook_entry" => %{"name" => "Hunter", "contact" => "[FILTERED]"}}
    end

    test "the letter about a new signature says one was left and not what it is" do
      Application.put_env(:web, :notify_email, "author@example.com")
      on_exit(fn -> Application.delete_env(:web, :notify_email) end)
      {:ok, _} = sign(%{contact: @email})

      # The letter waits in the job queue, which is a table like any other:
      # one more place the address must not be written.
      assert [%{args: args}] = all_enqueued(worker: Web.Workers.OwnerMail)
      assert args["body"] =~ "They left a way to reach them"
      refute inspect(args) =~ "hunter@"
    end
  end

  describe "the key" do
    test "what is sealed opens again, and nothing else does" do
      sealed = Contact.seal(@phone)

      assert Contact.open(sealed) == {:ok, @phone}
      assert Contact.open(sealed <> "x") == :error
      assert Contact.open("not a token") == :error
      assert Contact.open(nil) == :error
    end

    test "a contact sealed under another secret cannot be opened" do
      {:ok, entry} = sign(%{contact: @email})
      config = Application.get_env(:web, WebWeb.Endpoint)
      on_exit(fn -> Application.put_env(:web, WebWeb.Endpoint, config) end)

      Application.put_env(
        :web,
        WebWeb.Endpoint,
        Keyword.put(config, :secret_key_base, String.duplicate("z", 64))
      )

      assert General.guestbook_contact(entry.id) == :error
    end
  end

  describe "the public page" do
    test "offers the field, says what becomes of it, and never prints one", %{conn: conn} do
      {:ok, entry} = sign(%{contact: @email})
      {:ok, _} = entry.id |> General.get_guestbook_entry!() |> General.approve_guestbook_entry()

      {:ok, view, html} = live(conn, ~p"/guestbook")

      assert has_element?(view, ~s(#guestbook-form input[name="guestbook_entry[contact]"]))
      assert html =~ "Email or phone (optional)"
      assert html =~ "stored encrypted"
      assert html =~ "hey :)"
      refute html =~ "hunter@"
      refute render(view) =~ "hunter@"
    end

    test "a signature with a mistyped contact is not lost, and says why", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/guestbook")

      html =
        view
        |> form("#guestbook-form", guestbook_entry: %{name: "A", message: "B", contact: "nope"})
        |> render_change()

      assert html =~ "should be an email address or a phone number"
    end
  end

  describe "the admin" do
    setup %{conn: conn} do
      {:ok, conn: Plug.Test.init_test_session(conn, admin_user: true)}
    end

    test "sees that one was left, and the contact only on asking", %{conn: conn} do
      {:ok, entry} = sign(%{contact: @email})
      {:ok, plain} = sign(%{name: "No contact"})

      {:ok, view, html} = live(conn, ~p"/admin/guestbook")

      assert html =~ "Left a way to reach them"
      refute html =~ "hunter@"
      assert has_element?(view, "#contact-#{entry.id}")
      refute has_element?(view, "#contact-#{plain.id}")

      html = view |> element("#contact-#{entry.id} button", "Show") |> render_click()
      assert html =~ ~s(href="mailto:#{@email}")

      html = view |> element("#contact-#{entry.id} button", "Hide") |> render_click()
      refute html =~ "hunter@"
    end

    test "a phone number becomes something to dial", %{conn: conn} do
      {:ok, entry} = sign(%{contact: @phone})
      {:ok, view, _html} = live(conn, ~p"/admin/guestbook")

      html = view |> element("#contact-#{entry.id} button", "Show") |> render_click()
      assert html =~ ~s(href="tel:+15305550142")
    end

    test "can forget a contact and keep the signature", %{conn: conn} do
      {:ok, entry} = sign(%{contact: @email})
      {:ok, view, _html} = live(conn, ~p"/admin/guestbook")

      view |> element("#contact-#{entry.id} button", "Show") |> render_click()
      html = view |> element("#contact-#{entry.id} button", "Forget it") |> render_click()

      refute html =~ "hunter@"
      refute has_element?(view, "#contact-#{entry.id}")
      assert stored(entry.id) == nil
      assert General.get_guestbook_entry!(entry.id).message == "hey :)"
    end

    test "deleting the signature deletes the contact with it", %{conn: conn} do
      {:ok, entry} = sign(%{contact: @email})
      {:ok, view, _html} = live(conn, ~p"/admin/guestbook")

      view |> element("#signature-#{entry.id} button", "Delete") |> render_click()
      assert Web.Repo.aggregate(GuestbookEntry, :count) == 0
    end
  end

  test "nobody but the admin can ask", %{conn: conn} do
    assert {:error, {:redirect, _}} = live(conn, ~p"/admin/guestbook")
  end
end
