defmodule WebWeb.AdminLive.KeywordsTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest
  import Web.AudioFixtures

  alias Web.Blog

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  setup do
    tmp = Path.join(System.tmp_dir!(), "keywords-admin-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    original = Application.get_env(:web, :blog_path)
    Application.put_env(:web, :blog_path, tmp)

    File.write!(Path.join(tmp, "ferry.md"), "---\ntitle: Ferry\nkeywords: nyc, film\n---\n\nA.\n")

    File.write!(
      Path.join(tmp, "bridge.md"),
      "---\ntitle: Bridge\nkeywords: new-york, film\n---\n\nB.\n"
    )

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.put_env(:web, :blog_path, original)
    end)

    :ok
  end

  test "anonymous visitors are redirected away", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/keywords")
  end

  test "lists every keyword with what carries it, across both sections", %{conn: conn} do
    log_fixture(keywords: "film", recorded_on: ~D[2030-03-02])
    {:ok, view, _html} = live(admin_conn(conn), "/admin/keywords")

    assert has_element?(view, "#keyword-film", "2 posts")
    assert has_element?(view, "#keyword-film", "1 log")
    assert has_element?(view, ~s(#keyword-film a[href="/admin/blog/ferry/edit"]), "Ferry")
    assert has_element?(view, "#keyword-film", "Log, Saturday, 2 March 2030")
    assert has_element?(view, "#keyword-nyc .adm-pill", "used once")
    refute has_element?(view, "#keyword-film .adm-pill", "used once")
  end

  test "the used-once tab narrows to keywords one piece carries", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/keywords?show=once")

    assert has_element?(view, "#keyword-nyc")
    assert has_element?(view, "#keyword-new-york")
    refute has_element?(view, "#keyword-film")
  end

  test "renaming rewrites the files and says how many", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/keywords")

    view |> element("#keyword-film button", "Rename or merge") |> render_click()
    view |> form("#rename-film", to: "Analog") |> render_submit()

    assert has_element?(view, "#flash-info", "Renamed film to analog: 2 posts, 0 logs.")
    assert has_element?(view, "#keyword-analog", "2 posts")
    refute has_element?(view, "#keyword-film")
    assert {:ok, %{keywords: ["nyc", "analog"]}} = Blog.get_post("ferry")
  end

  test "renaming to an existing keyword says it merged them", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/keywords")

    view |> element("#keyword-nyc button", "Rename or merge") |> render_click()
    view |> form("#rename-nyc", to: "new york") |> render_submit()

    assert has_element?(view, "#flash-info", "Merged nyc into new-york: 1 post, 0 logs.")
    assert has_element?(view, "#keyword-new-york", "2 posts")
    refute has_element?(view, "#keyword-nyc")
  end

  test "a name that is nothing is refused and nothing is written", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/keywords")

    view |> element("#keyword-film button", "Rename or merge") |> render_click()
    view |> form("#rename-film", to: "?!") |> render_submit()

    assert has_element?(view, "#flash-error", "at least one letter or number")
    assert {:ok, %{keywords: ["nyc", "film"]}} = Blog.get_post("ferry")
  end
end
