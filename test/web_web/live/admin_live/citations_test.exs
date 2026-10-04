defmodule WebWeb.AdminLive.CitationsTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Web.Repo
  alias Web.Webmentions.Webmention

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  defp held(attrs \\ %{}) do
    %Webmention{
      source: "https://example.org/notes/#{System.unique_integer([:positive])}",
      target: "http://localhost:4000/blog/keyworded-post",
      piece: "post:keyworded-post",
      status: "held",
      title: "Notes on the ferry",
      source_host: "example.org"
    }
    |> struct(attrs)
    |> Repo.insert!()
  end

  test "anonymous visitors are redirected away", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/citations")
  end

  test "an approved citation shows under its piece as Cited by", %{conn: conn} do
    mention = held()

    {:ok, view, _html} = live(admin_conn(conn), "/admin/citations")
    assert has_element?(view, ~s(#adm-rail a[href="/admin/citations"] .adm-badge), "1")

    view |> element("#citation-#{mention.id} button[phx-click=approve]") |> render_click()
    assert Repo.reload(mention).status == "approved"
    refute has_element?(view, ~s(#adm-rail a[href="/admin/citations"] .adm-badge))

    {:ok, _letters, html} =
      live_isolated(conn, WebWeb.LettersLive,
        session: %{"piece" => "post:keyworded-post", "remote_ip" => "192.0.2.1"}
      )

    assert html =~ "Cited by"
    assert html =~ "Notes on the ferry"
    assert html =~ ~s(rel="nofollow ugc noopener")
  end

  test "held and rejected citations never show under the piece", %{conn: conn} do
    held(%{title: "Waiting one"})
    held(%{title: "Rejected one", status: "rejected"})

    {:ok, _letters, html} =
      live_isolated(conn, WebWeb.LettersLive,
        session: %{"piece" => "post:keyworded-post", "remote_ip" => "192.0.2.2"}
      )

    refute html =~ "Waiting one"
    refute html =~ "Rejected one"
  end
end
