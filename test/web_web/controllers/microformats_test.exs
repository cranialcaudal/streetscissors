defmodule WebWeb.MicroformatsTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest
  import Web.AudioFixtures

  test "a post is an h-entry with a name, a date, content and an author", %{conn: conn} do
    html = conn |> get("/blog/keyworded-post") |> html_response(200)

    assert html =~ ~s(class="blog-post-panel h-entry")
    assert html =~ "p-name"
    assert html =~ ~s(class="dt-published" datetime="2026-07-15")
    assert html =~ "e-content"
    assert html =~ "p-category"
    assert html =~ ~s(class="u-url" href="http://localhost:4000/blog/keyworded-post")
    assert html =~ ~s(class="p-author h-card")
  end

  test "a log is an h-entry too", %{conn: conn} do
    log = log_fixture(%{recorded_on: ~D[2026-07-20]})
    {:ok, _view, html} = live(conn, "/logs/#{log.slug}")

    assert html =~ "console-frame h-entry"
    assert html =~ ~s(class="dt-published" datetime="2026-07-20")
  end

  test "the homepage carries the site's representative h-card", %{conn: conn} do
    assert conn |> get("/") |> html_response(200) =~ "h-card p-name u-url u-uid"
  end

  describe "rel=me" do
    setup do
      original = Application.get_env(:web, :rel_me)
      on_exit(fn -> Application.put_env(:web, :rel_me, original) end)
    end

    test "links no profile by default", %{conn: conn} do
      Application.put_env(:web, :rel_me, [])
      refute conn |> get("/about") |> html_response(200) =~ ~s(rel="me")
    end

    test "links the profiles its owner lists", %{conn: conn} do
      Application.put_env(:web, :rel_me, ["https://social.example/@someone"])

      assert conn |> get("/about") |> html_response(200) =~
               ~s(<link rel="me" href="https://social.example/@someone">)
    end
  end
end
