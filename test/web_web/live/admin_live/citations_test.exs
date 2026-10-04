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

  describe "the sent tab" do
    use Oban.Testing, repo: Web.Repo

    alias Web.Webmentions.Sent

    defp sent(attrs) do
      %Sent{}
      |> Sent.changeset(
        Map.merge(%{source: "/blog/essay", target: "https://example.org/a"}, attrs)
      )
      |> Web.Repo.insert!()
    end

    test "lists what this site has told others, and what they said", %{conn: conn} do
      told = sent(%{status: "sent", detail: "answered 202"})
      none = sent(%{target: "https://example.net/b", status: "no_endpoint"})

      {:ok, view, _html} = live(admin_conn(conn), "/admin/citations?show=sent")

      assert has_element?(view, "#sent-#{told.id}", "https://example.org/a")
      assert has_element?(view, "#sent-#{told.id} .adm-pill--live", "Told")
      assert has_element?(view, "#sent-#{told.id}", "answered 202")
      assert has_element?(view, "#sent-#{none.id} .adm-pill", "Takes none")
      # Only a failure, or a site that took none, is worth asking again.
      refute has_element?(view, "#sent-#{told.id} button", "Try again")
    end

    test "try again queues the mention once more", %{conn: conn} do
      failed = sent(%{status: "failed", detail: "could not connect: timeout"})
      {:ok, view, _html} = live(admin_conn(conn), "/admin/citations?show=sent")

      view |> element("#sent-#{failed.id} button", "Try again") |> render_click()

      assert_enqueued(worker: Web.Workers.WebmentionSender, args: %{"id" => failed.id})
      assert has_element?(view, "#sent-#{failed.id} .adm-pill", "Sending")
    end

    test "says so when no post has linked anywhere yet", %{conn: conn} do
      {:ok, _view, html} = live(admin_conn(conn), "/admin/citations?show=sent")
      assert html =~ "No post has linked to another site yet."
    end
  end
end
