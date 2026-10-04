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

    test "?filter=missing lists only the posts without keywords", %{conn: conn, tmp: tmp} do
      File.write!(
        Path.join(tmp, "filed.md"),
        "---\ntitle: Filed\nkeywords: ferry\n---\n\nBody.\n"
      )

      File.write!(Path.join(tmp, "unfiled.md"), "---\ntitle: Unfiled\n---\n\nBody.\n")

      {:ok, _view, html} = live(admin_conn(conn), "/admin/blog?filter=missing")
      assert html =~ "Unfiled"
      refute html =~ "post-filed"
    end

    test "a post can be deleted", %{conn: conn, tmp: tmp} do
      File.write!(Path.join(tmp, "doomed.md"), "---\ntitle: Doomed\n---\n\nBody.\n")

      {:ok, view, _html} = live(admin_conn(conn), "/admin/blog")
      view |> element("button[phx-click=delete_post][phx-value-slug=doomed]") |> render_click()

      refute File.exists?(Path.join(tmp, "doomed.md"))
    end
  end

  describe "drafts" do
    setup :with_tmp_blog

    setup %{tmp: tmp} do
      File.write!(
        Path.join(tmp, "out.md"),
        "---\ntitle: Out\nkeywords: film\n---\n\nPublished.\n"
      )

      File.write!(
        Path.join(tmp, "wip.md"),
        "---\ntitle: Work In Progress\ndraft: true\n---\n\nNot yet.\n"
      )

      :ok
    end

    test "are listed with the posts, marked, and have a tab of their own", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/blog")

      assert has_element?(view, "#post-wip .adm-pill--draft", "draft")
      refute has_element?(view, "#post-out .adm-pill--draft")

      {:ok, view, _html} = live(admin_conn(conn), "/admin/blog?filter=drafts")
      assert has_element?(view, "#post-wip")
      refute has_element?(view, "#post-out")
    end

    # A draft cannot be reached through the public filters either way, so it
    # is not nagged about keywords until it is published.
    test "are not counted as missing keywords", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/blog?filter=missing")
      refute has_element?(view, "#post-wip")
      assert render(view) =~ "Every published post has keywords."
    end

    test "publish puts a draft on the site, and unpublish takes it off", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/blog")

      view |> element("#post-wip button", "Publish") |> render_click()
      assert {:ok, %{draft: false}} = Blog.get_post("wip")
      assert has_element?(view, "#flash-info", "Published /blog/wip.")

      view |> element("#post-wip button", "Unpublish") |> render_click()
      assert {:error, :not_found} = Blog.get_post("wip")
    end

    test "every post links to the editor", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/blog")
      assert has_element?(view, ~s(#post-out a[href="/admin/blog/out/edit"]), "Edit")
    end
  end

  describe "starting a post" do
    setup :with_tmp_blog

    test "makes a dated draft and opens it in the editor", %{conn: conn, tmp: tmp} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/blog")

      assert {:error, {:live_redirect, %{to: "/admin/blog/tides-out/edit"}}} =
               view |> form("#new-post-form", title: "Tide's Out") |> render_submit()

      text = File.read!(Path.join(tmp, "tides-out.md"))
      assert text =~ ~s(title: "Tide's Out")
      assert text =~ "draft: true"
      assert {:error, :not_found} = Blog.get_post("tides-out")
    end

    test "refuses a title that is already a file", %{conn: conn, tmp: tmp} do
      File.write!(Path.join(tmp, "taken.md"), "Already here.\n")
      {:ok, view, _html} = live(admin_conn(conn), "/admin/blog")

      view |> form("#new-post-form", title: "Taken") |> render_submit()

      assert has_element?(view, "#flash-error", "There is already a taken.md.")
      assert File.read!(Path.join(tmp, "taken.md")) == "Already here.\n"
    end
  end
end
