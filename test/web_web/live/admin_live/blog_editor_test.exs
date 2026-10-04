defmodule WebWeb.AdminLive.BlogEditorTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Web.Blog

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  # A whole throwaway vault, since a forced save writes to the .trash beside
  # the blog folder.
  setup do
    vault = Path.join(System.tmp_dir!(), "vault-editor-#{System.unique_integer([:positive])}")
    blog = Path.join(vault, "blog")
    File.mkdir_p!(blog)
    original = Application.get_env(:web, :blog_path)
    Application.put_env(:web, :blog_path, blog)

    path = Path.join(blog, "essay.md")

    File.write!(path, """
    ---
    title: "An Essay"
    description: "What it is about."
    date: 2030-03-02
    keywords: film, ferry
    draft: true
    ---

    The first paragraph, as it was opened.
    """)

    on_exit(fn ->
      File.rm_rf!(vault)
      Application.put_env(:web, :blog_path, original)
    end)

    {:ok, vault: vault, path: path}
  end

  test "anonymous visitors are redirected away", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/blog/essay/edit")
  end

  test "a post that is not there sends you back to the blog", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/admin/blog"}}} =
             live(admin_conn(conn), "/admin/blog/no-such-post/edit")
  end

  test "opens the whole file, with the page it makes beside it", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/blog/essay/edit")

    source = view |> element("#post-source") |> render()
    assert source =~ "title: &quot;An Essay&quot;"
    assert source =~ "draft: true"

    assert has_element?(view, ".adm-title", "An Essay")

    assert has_element?(
             view,
             "#post-preview .adm-prose p",
             "The first paragraph, as it was opened."
           )

    assert has_element?(view, "#post-preview .adm-pill--draft", "draft")
    assert has_element?(view, "#post-preview .adm-chip", "ferry")
    assert has_element?(view, "#post-preview", "What it is about.")
  end

  test "the preview follows the text as it is typed, frontmatter included", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/blog/essay/edit")

    view
    |> form("#post-editor", content: "---\ntitle: Retitled\n---\n\nA **new** opening.\n")
    |> render_change()

    assert has_element?(view, ".adm-title", "Retitled")
    assert has_element?(view, "#post-preview .adm-prose strong", "new")
    assert has_element?(view, "#post-preview .adm-pill--live", "published")
    # Nothing in the frontmatter now: the preview says what is missing.
    assert has_element?(view, "#post-preview .adm-pill--held", "none")
    assert has_element?(view, "#post-editor[data-dirty=true]")
  end

  test "saving writes the file back", %{conn: conn, path: path} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/blog/essay/edit")

    view
    |> form("#post-editor", content: "---\ntitle: Saved\ndraft: true\n---\n\nSaved body.\n")
    |> render_submit()

    assert File.read!(path) == "---\ntitle: Saved\ndraft: true\n---\n\nSaved body.\n"
    assert has_element?(view, "#flash-info", "Saved essay.md.")
    assert has_element?(view, "#post-editor[data-dirty=false]")
  end

  test "save and publish takes the draft line out as it saves", %{conn: conn, path: path} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/blog/essay/edit")
    assert {:error, :not_found} = Blog.get_post("essay")

    view
    |> form("#post-editor", content: File.read!(path))
    |> render_submit(%{"then" => "publish"})

    refute File.read!(path) =~ "draft"
    assert {:ok, %{title: "An Essay", keywords: ["film", "ferry"]}} = Blog.get_post("essay")
    assert has_element?(view, "#post-preview .adm-pill--live", "published")
  end

  describe "when the file changed on disk while the page was open" do
    setup %{conn: conn, path: path} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/blog/essay/edit")
      File.write!(path, "Edited in Obsidian.\n")

      view |> form("#post-editor", content: "Edited in the admin.\n") |> render_submit()
      {:ok, view: view}
    end

    test "the save is refused and both versions are put on the table", %{view: view, path: path} do
      assert File.read!(path) == "Edited in Obsidian.\n"

      assert has_element?(view, "#post-conflict", "changed on disk while you had it open")
      assert has_element?(view, "#post-conflict pre", "Edited in Obsidian.")
      # The author's own text is still in the editor.
      assert view |> element("#post-source") |> render() =~ "Edited in the admin."
    end

    test "taking the disk version replaces the editor's text", %{view: view, path: path} do
      view |> element("#post-conflict button", "Take the version on disk") |> render_click()

      refute has_element?(view, "#post-conflict")
      assert view |> element("#post-source") |> render() =~ "Edited in Obsidian."
      assert File.read!(path) == "Edited in Obsidian.\n"
      assert has_element?(view, "#post-editor[data-dirty=false]")
    end

    test "saving over it keeps the replaced version in the vault's trash",
         %{view: view, path: path, vault: vault} do
      view |> element("#post-conflict button", "Save mine over it") |> render_click()

      refute has_element?(view, "#post-conflict")
      assert File.read!(path) == "Edited in the admin.\n"

      assert [kept] = File.ls!(Path.join(vault, ".trash"))
      assert File.read!(Path.join([vault, ".trash", kept])) == "Edited in Obsidian.\n"
    end

    test "after either choice the next save goes through", %{view: view, path: path} do
      view |> element("#post-conflict button", "Take the version on disk") |> render_click()
      view |> form("#post-editor", content: "Third version.\n") |> render_submit()

      assert File.read!(path) == "Third version.\n"
      refute has_element?(view, "#post-conflict")
    end
  end
end
