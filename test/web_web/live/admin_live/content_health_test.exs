defmodule WebWeb.AdminLive.ContentHealthTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  setup do
    vault = Path.join(System.tmp_dir!(), "health-admin-#{System.unique_integer([:positive])}")
    blog = Path.join(vault, "blog")
    File.mkdir_p!(blog)
    original = Application.get_env(:web, :blog_path)
    Application.put_env(:web, :blog_path, blog)

    on_exit(fn ->
      File.rm_rf!(vault)
      Application.put_env(:web, :blog_path, original)
    end)

    {:ok, blog: blog}
  end

  test "anonymous visitors are redirected away", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/health")
  end

  test "says it is reading, then shows the report", %{conn: conn, blog: blog} do
    File.write!(Path.join(blog, "linker.md"), """
    ---
    title: Linker
    ---

    [Gone](/blog/renamed-away) and ![[roll999]].
    """)

    {:ok, view, html} = live(admin_conn(conn), "/admin/health")
    assert html =~ "Reading the vault"

    html = render_async(view)

    assert html =~ "things to look at"
    assert has_element?(view, "#broken code", "/blog/renamed-away")
    assert has_element?(view, ~s(#broken a[href="/admin/blog/linker/edit"]), "Linker")
    assert has_element?(view, "#embeds code", "![[roll999]]")
    assert has_element?(view, "#undescribed", "no description, no keywords")
    assert has_element?(view, "#archive code", "negatives --analyze 001")
  end

  test "a clean vault says so in each section", %{conn: conn, blog: blog} do
    File.write!(Path.join(blog, "fine.md"), """
    ---
    title: Fine
    description: "Nothing wrong here."
    keywords: film
    ---

    [The manual](/how-to).
    """)

    {:ok, view, _html} = live(admin_conn(conn), "/admin/health")
    render_async(view)

    assert has_element?(view, "#health-broken", "Every link on the site leads somewhere.")
    assert has_element?(view, "#health-embeds", "Every embed found what it names.")
    assert has_element?(view, "#health-posts", "Every published post has a description")
  end

  test "check again reads the vault as it is now", %{conn: conn, blog: blog} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/health")
    render_async(view)
    refute has_element?(view, "#broken code", "/blog/renamed-away")

    File.write!(Path.join(blog, "linker.md"), "[Gone](/blog/renamed-away)\n")
    view |> element("button", "Check again") |> render_click()
    render_async(view)

    assert has_element?(view, "#broken code", "/blog/renamed-away")
  end
end
