defmodule WebWeb.AdminLive.BlogManagerTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Web.Blog

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  # The suite's fixture posts are committed, so tests that write use their own
  # throwaway blog dir.
  defp with_tmp_blog(_context) do
    tmp = Path.join(System.tmp_dir!(), "blog-admin-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    original = Application.get_env(:web, :blog_path)
    Application.put_env(:web, :blog_path, tmp)

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.put_env(:web, :blog_path, original)
    end)

    {:ok, tmp: tmp}
  end

  test "anonymous visitors are redirected away", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/blog")
  end

  test "/admin/content permanently redirects to the blog manager", %{conn: conn} do
    conn = get(admin_conn(conn), "/admin/content")
    assert redirected_to(conn, 301) == "/admin/blog"
  end

  test "the archive lists posts and links to the logs manager", %{conn: conn} do
    {:ok, _view, html} = live(admin_conn(conn), "/admin/blog")

    assert html =~ "Fixture Post With Frontmatter"
    assert html =~ "/admin/logs"
  end

  describe "with a throwaway blog dir" do
    setup :with_tmp_blog

    test "dropping markdown files posts them", %{conn: conn, tmp: tmp} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/blog")

      view
      |> file_input("#markdown-upload-form", :markdown, [
        %{
          name: "Ferry Notes.md",
          content: "---\ntitle: Ferry Notes\nkeywords: ferry\n---\n\nBody.\n",
          type: "text/markdown"
        }
      ])
      |> render_upload("Ferry Notes.md")

      assert File.exists?(Path.join(tmp, "ferry-notes.md"))
      assert {:ok, post} = Blog.get_post("ferry-notes")
      assert post.keywords == ["ferry"]
    end

    test "a post with no keywords is flagged as unfilterable", %{conn: conn, tmp: tmp} do
      File.write!(Path.join(tmp, "unfiled.md"), "Body with no frontmatter.")

      {:ok, _view, html} = live(admin_conn(conn), "/admin/blog")
      assert html =~ "no keywords"
    end

    test "keywords typed in the admin are written into the vault file", %{conn: conn, tmp: tmp} do
      File.write!(Path.join(tmp, "unfiled.md"), "---\ntitle: Unfiled\n---\n\nBody.\n")

      {:ok, view, _html} = live(admin_conn(conn), "/admin/blog")

      view |> element("button[phx-click=edit_keywords][phx-value-slug=unfiled]") |> render_click()

      view
      |> form("form[phx-submit=save_keywords]", %{
        "slug" => "unfiled",
        "keywords" => "Ferry, Bowling Green"
      })
      |> render_submit()

      # The file itself is the source of truth, so the line has to land there
      raw = File.read!(Path.join(tmp, "unfiled.md"))
      assert raw =~ "keywords: ferry, bowling-green"
      assert raw =~ "title: Unfiled"

      assert {:ok, post} = Blog.get_post("unfiled")
      assert post.keywords == ["ferry", "bowling-green"]
    end

    test "a post can be deleted", %{conn: conn, tmp: tmp} do
      File.write!(Path.join(tmp, "doomed.md"), "---\ntitle: Doomed\n---\n\nBody.\n")

      {:ok, view, _html} = live(admin_conn(conn), "/admin/blog")
      view |> element("button[phx-click=delete_post][phx-value-slug=doomed]") |> render_click()

      refute File.exists?(Path.join(tmp, "doomed.md"))
    end
  end
end
