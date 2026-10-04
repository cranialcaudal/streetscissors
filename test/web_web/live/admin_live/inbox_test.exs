defmodule WebWeb.AdminLive.InboxTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Web.Contact

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  defp message(attrs) do
    {:ok, msg} =
      attrs
      |> Enum.into(%{name: "Ada", email: "ada@example.com", message: "Hello there"})
      |> Contact.create_message()

    msg
  end

  test "anonymous visitors are redirected away", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/inbox")
  end

  test "opens on the inbox, and each box is its own address", %{conn: conn} do
    message(%{name: "New sender"})
    message(%{name: "Old sender", status: "archive"})

    {:ok, view, html} = live(admin_conn(conn), "/admin/inbox")
    assert html =~ "New sender"
    refute html =~ "Old sender"

    html = view |> element(~s(.adm-tabs a[href="/admin/inbox?box=archive"])) |> render_click()
    assert_patch(view, "/admin/inbox?box=archive")
    assert html =~ "Old sender"
    refute html =~ "New sender"
  end

  test "opens on flagged messages when there are any", %{conn: conn} do
    message(%{name: "Flagged sender", status: "attention"})

    {:ok, _view, html} = live(admin_conn(conn), "/admin/inbox")
    assert html =~ "Flagged sender"
  end

  test "archiving moves a message and updates the rail's count", %{conn: conn} do
    msg = message(%{})

    {:ok, view, _html} = live(admin_conn(conn), "/admin/inbox?box=inbox")
    assert has_element?(view, ~s(#adm-rail a[href="/admin/inbox"] .adm-badge), "1")

    view
    |> element(~s(#message-#{msg.id} button[phx-value-status="archive"]))
    |> render_click()

    refute has_element?(view, "#message-#{msg.id}")
    refute has_element?(view, ~s(#adm-rail a[href="/admin/inbox"] .adm-badge))
    assert Contact.list_messages("archive") |> Enum.map(& &1.id) == [msg.id]
  end

  test "only an archived message can be deleted", %{conn: conn} do
    msg = message(%{status: "archive"})

    {:ok, view, _html} = live(admin_conn(conn), "/admin/inbox?box=archive")
    view |> element("#message-#{msg.id} button[phx-click=delete_message]") |> render_click()

    assert Contact.list_messages() == []
  end

  test "a message offers a reply by email", %{conn: conn} do
    msg = message(%{email: "reply@example.com"})

    {:ok, view, _html} = live(admin_conn(conn), "/admin/inbox")
    assert has_element?(view, ~s(#message-#{msg.id} a[href="mailto:reply@example.com"]))
  end

  describe "letters" do
    defp letter(attrs) do
      {:ok, letter} =
        Web.Letters.create(
          "post:keyworded-post",
          Map.merge(
            %{"name" => "Ada", "email" => "ada@example.com", "message" => "About the ferry."},
            attrs
          )
        )

      letter
    end

    test "a letter names the piece it is about", %{conn: conn} do
      msg = letter(%{})

      {:ok, view, _html} = live(admin_conn(conn), "/admin/inbox")

      assert has_element?(
               view,
               ~s(#message-#{msg.id} a[href="/blog/keyworded-post"]),
               "Fixture Post With Keywords"
             )
    end

    test "only a letter its writer allowed can be published, and taken down", %{conn: conn} do
      private = letter(%{})
      open = letter(%{"may_publish" => "true", "name" => "Grace"})

      {:ok, view, _html} = live(admin_conn(conn), "/admin/inbox")
      refute has_element?(view, "#message-#{private.id} button[phx-click=publish_letter]")

      view |> element("#message-#{open.id} button[phx-click=publish_letter]") |> render_click()
      assert Web.Repo.reload(open).published_at
      assert [%{id: id}] = Web.Letters.list_published("post:keyworded-post")
      assert id == open.id

      view |> element("#message-#{open.id} button[phx-click=unpublish_letter]") |> render_click()
      refute Web.Repo.reload(open).published_at
    end
  end
end
