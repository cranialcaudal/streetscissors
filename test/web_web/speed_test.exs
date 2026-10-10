defmodule WebWeb.SpeedTest do
  @moduledoc """
  What keeps the site quick, pinned: type served from here and preloaded for
  the header, the next page fetched ahead without being counted as read, and
  pictures that say how long they may be kept.
  """
  use WebWeb.ConnCase

  import Ecto.Query

  alias Web.Analytics.Hit
  alias WebWeb.Plugs.Analytics

  @visitor "203.0.113.9"

  defp hits(path), do: Web.Repo.aggregate(from(h in Hit, where: h.path == ^path), :count)
  defp visitor(conn), do: put_req_header(conn, "x-forwarded-for", @visitor)

  describe "type" do
    test "no page asks another site for its fonts", %{conn: conn} do
      html = conn |> get(~p"/about") |> html_response(200)

      refute html =~ "fonts.googleapis.com"
      refute html =~ "fonts.gstatic.com"
    end

    test "the two faces the header draws with are preloaded, from the files fonts.css names",
         %{conn: conn} do
      html = conn |> get(~p"/about") |> html_response(200)
      css = File.read!("assets/css/fonts.css")

      for file <- ~w(sorts-mill-goudy-400-latin.woff2 ibm-plex-mono-600-latin.woff2) do
        # crossorigin, or the browser fetches a preloaded font a second time.
        assert html =~
                 ~r{<link rel="preload" as="font" type="font/woff2" href="/fonts/#{Regex.escape(Path.rootname(file))}[^"]*" crossorigin>}

        assert css =~ "url('/fonts/#{file}')"
      end
    end

    test "every file fonts.css names is on disk, and every family the styles use is declared" do
      css = File.read!("assets/css/fonts.css")

      for [_, file] <- Regex.scan(~r{url\('/fonts/([^']+)'\)}, css) do
        assert File.exists?(Path.join("priv/static/fonts", file)), "#{file} is missing"
      end

      for family <- [
            "Sorts Mill Goudy",
            "IBM Plex Mono",
            "Bebas Neue",
            "League Spartan",
            "Saira Condensed"
          ] do
        assert css =~ "font-family: '#{family}'"
      end

      assert File.read!("assets/css/app.css") =~ ~s(@import "./fonts.css";)
    end
  end

  describe "the next page, fetched ahead" do
    test "the layout carries speculation rules that prefetch and never prerender",
         %{conn: conn} do
      html = conn |> get(~p"/about") |> html_response(200)
      [_, json] = Regex.run(~r{<script type="speculationrules">(.*?)</script>}s, html)
      rules = Jason.decode!(json)

      refute Map.has_key?(rules, "prerender")
      assert [%{"eagerness" => "moderate", "where" => %{"and" => conditions}}] = rules["prefetch"]
      assert %{"href_matches" => "/*"} in conditions

      for kept_out <- ["/admin/*", "/uploads/*", "/search\\?*", "/feed*"] do
        assert %{"not" => %{"href_matches" => kept_out}} in conditions
      end
    end

    test "a prefetch is told apart from a visit" do
      assert Analytics.prefetch?(put_req_header(build_conn(), "sec-purpose", "prefetch"))

      assert Analytics.prefetch?(
               put_req_header(build_conn(), "sec-purpose", "prefetch;anonymous-client-ip")
             )

      refute Analytics.prefetch?(build_conn())
    end

    test "a visit is counted and a prefetch is not", %{conn: conn} do
      conn |> visitor() |> put_req_header("sec-purpose", "prefetch") |> get(~p"/about")
      conn |> visitor() |> get(~p"/how-to")

      # The plug records in a task of its own.
      assert Enum.any?(1..40, fn _ ->
               hits("/how-to") == 1 or (Process.sleep(25) && false)
             end)

      assert hits("/about") == 0
    end

    test "a prefetched page reports itself seen, once it is shown", %{conn: conn} do
      conn =
        conn
        |> visitor()
        |> put_req_header("origin", "http://www.example.com")
        |> post("/seen?p=/about")

      assert response(conn, 204) == ""
      assert hits("/about") == 1
    end

    test "nothing is counted for another site's beacon, a page that is not one, or the admin",
         %{conn: conn} do
      seen = fn conn, origin, path ->
        conn = visitor(conn)
        conn = if origin, do: put_req_header(conn, "origin", origin), else: conn
        conn |> post("/seen?p=" <> URI.encode_www_form(path)) |> response(204)
      end

      seen.(conn, "https://elsewhere.example", "/about")
      seen.(conn, nil, "/about")
      assert hits("/about") == 0

      for path <- ["about", "/about?x=1", "/../etc", "https://elsewhere.example/about"] do
        seen.(conn, "http://www.example.com", path)
      end

      assert Web.Repo.aggregate(Hit, :count) == 0

      # The admin's own reading is never a hit, by this door or the other.
      admin = Plug.Test.init_test_session(conn, admin_user: true)
      seen.(admin, "http://www.example.com", "/about")
      # Nor is the admin's own side of the site.
      seen.(conn, "http://www.example.com", "/admin/dashboard")
      assert Web.Repo.aggregate(Hit, :count) == 0

      assert conn |> post("/seen") |> response(204)
    end
  end

  describe "the manual" do
    test "is rendered once and again only when the file changes" do
      path = Path.join(System.tmp_dir!(), "docs-#{System.unique_integer([:positive])}.md")
      on_exit(fn -> File.rm(path) end)

      File.write!(path, "## One\n\nBody.\n")
      assert {:ok, {html, [%{text: "One"}]}} = Web.Docs.render_file(path)
      assert html =~ "Body."
      assert {:ok, {^html, _}} = Web.Docs.render_file(path)

      File.write!(path, "## Two\n")
      File.touch!(path, {{2031, 1, 1}, {0, 0, 0}})
      assert {:ok, {_, [%{text: "Two"}]}} = Web.Docs.render_file(path)

      assert {:error, :enoent} = Web.Docs.render_file(path <> ".missing")
    end

    test "warming at boot reads everything and cannot raise" do
      assert Web.Warm.run() == :ok
    end
  end
end
