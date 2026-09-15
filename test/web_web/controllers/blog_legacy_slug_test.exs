defmodule WebWeb.BlogLegacySlugTest do
  use WebWeb.ConnCase

  # A post filed under its title ("Tide's Out.md") used to be served at that
  # title. These run against a throwaway blog directory so each test can
  # decide whether the vault file has been renamed to its clean slug yet.
  setup do
    dir = Path.join(System.tmp_dir!(), "blog_slug_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    prev = Application.get_env(:web, :blog_path)
    Application.put_env(:web, :blog_path, dir)

    on_exit(fn ->
      Application.put_env(:web, :blog_path, prev)
      File.rm_rf!(dir)
    end)

    %{dir: dir}
  end

  test "a title-shaped address moves permanently to the clean slug once that file exists",
       %{conn: conn, dir: dir} do
    write_post(dir, "tides-out.md")

    conn = get(conn, "/blog/Tide%27s%20Out")
    assert redirected_to(conn, 301) == "/blog/tides-out"

    html = build_conn() |> get(~p"/blog/tides-out") |> html_response(200)
    assert html =~ "A post about the tide going out."
  end

  # Prod reads the vault in place, so the code can ship before the file is
  # renamed. Until then the old address must keep working, not 301 to a 404.
  test "until the vault file is renamed, the old address still serves the post",
       %{conn: conn, dir: dir} do
    write_post(dir, "Tide's Out.md")

    html = conn |> get("/blog/Tide%27s%20Out") |> html_response(200)
    assert html =~ "A post about the tide going out."
  end

  test "an address that is already clean is served, not redirected", %{conn: conn, dir: dir} do
    write_post(dir, "tides-out.md")

    assert conn |> get(~p"/blog/tides-out") |> html_response(200)
  end

  test "views at the old address count toward the clean one", %{conn: conn, dir: dir} do
    write_post(dir, "tides-out.md")

    Web.Analytics.record_hit("/blog/Tide%27s%20Out", "Firefox", "visitor-a")
    Web.Analytics.record_hit("/blog/tides-out", "Firefox", "visitor-b")

    html = conn |> get(~p"/blog") |> html_response(200)
    assert html =~ "2 views"
  end

  defp write_post(dir, filename) do
    File.write!(Path.join(dir, filename), """
    ---
    title: Tide's Out
    date: 2026-09-01
    ---

    A post about the tide going out.
    """)
  end
end
