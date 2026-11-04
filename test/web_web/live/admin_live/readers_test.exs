defmodule WebWeb.AdminLive.ReadersTest do
  use WebWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Web.Analytics
  alias Web.Analytics.{Hit, Owner}
  alias Web.Repo

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  setup do
    cache_path = Application.get_env(:web, :reader_geo_cache_path)
    if is_binary(cache_path), do: File.rm(cache_path)

    # The sandbox rolls the row back; :persistent_term is not in the sandbox,
    # so it is erased on its own and before anything that might raise.
    on_exit(fn -> :persistent_term.erase({Owner, :hashes}) end)
    on_exit(fn -> if is_binary(cache_path), do: File.rm(cache_path) end)

    Owner.reload()
    :ok
  end

  test "anonymous visitors are redirected away", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/readers")
  end

  test "renders GeoIP-resolved and behavior-guessed locations and removes a visitor on request",
       %{conn: conn} do
    # 1. A reader matched in the GeoIP cache
    geo_hash = "533021A0E1FFDB7011232EB3C65EDC2D5A5DED208D11D1A8CD9188E5C978DBC4"

    write_cache(%{
      geo_hash => %{
        "city" => "Riverton",
        "region" => "California",
        "country" => "United States",
        "isp" => "Charter Communications",
        "org" => "Spectrum",
        "hosting" => false,
        "mobile" => false
      }
    })

    for {path, dt} <- [
          {"/blog", ~N[2026-10-10 21:00:00]},
          {"/fitness", ~N[2026-10-11 22:00:00]},
          {"/", ~N[2026-10-12 20:00:00]}
        ] do
      Repo.insert!(%Hit{
        ip_hash: geo_hash,
        path: path,
        user_agent: "Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) Chrome/134.0.0.0",
        referrer: "duckduckgo.com",
        inserted_at: dt
      })
    end

    # 2. A historical reader not in the GeoIP cache (guessed from active hours & local pages)
    guessed_hash = "9ABA3FE7058B73F4D4C87BB48E437DCA2DFB29F354AA75D7213EB3AAF1F1758E"

    for {path, dt} <- [
          {"/fitness/rides", ~N[2026-08-10 21:30:00]},
          {"/food", ~N[2026-08-11 22:00:00]}
        ] do
      Repo.insert!(%Hit{
        ip_hash: guessed_hash,
        path: path,
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) Safari/604.1",
        inserted_at: dt
      })
    end

    # 3. A single-day rapid bot burst (30 hits in 10 seconds)
    bot_hash = "431F31C95A80B33D016D2DF76170562C40DAA5E009E7294130F7A885E112E8D6"

    for i <- 1..30 do
      Repo.insert!(%Hit{
        ip_hash: bot_hash,
        path: "/page-#{i}",
        user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/124.0.0.0",
        inserted_at: ~N[2026-10-07 13:06:36]
      })
    end

    {:ok, view, html} = live(admin_conn(conn), "/admin/readers")

    assert html =~ "Readers"
    render_async(view)

    assert has_element?(view, "#reader-533021", "Riverton, California, United States")
    assert has_element?(view, "#reader-533021", "Charter Communications (Spectrum)")
    assert has_element?(view, "#reader-533021", "Chromebook")
    assert has_element?(view, "#reader-533021", "DuckDuckGo")

    assert has_element?(view, "#reader-9ABA3F", "Near the author (guessed)")
    assert has_element?(view, "#reader-9ABA3F", "reads the local training & ride pages")

    # Bot burst is hidden from the default Readers tab, but shown under Bot bursts
    refute has_element?(view, "#reader-431F31")

    view |> element("a.adm-tab", "Bot bursts") |> render_click()
    assert has_element?(view, "#reader-431F31")

    # Removing a visitor from the count deletes their hits
    view |> element("a.adm-tab", "Readers") |> render_click()

    view
    |> element("#reader-9ABA3F button[phx-click='forget']")
    |> render_click()

    render_async(view)
    refute has_element?(view, "#reader-9ABA3F")
  end

  describe "the author's own reading" do
    test "\"This is me\" moves a visitor to Mine and out of the site's figures",
         %{conn: conn} do
      hash = Analytics.hash_ip("192.0.2.10")
      today = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      for path <- ["/blog", "/fitness", "/"] do
        Repo.insert!(%Hit{ip_hash: hash, path: path, user_agent: "Firefox", inserted_at: today})
      end

      assert Analytics.count_hits_today() == 3

      {:ok, view, _html} = live(admin_conn(conn), "/admin/readers")
      render_async(view)

      badge = String.slice(hash, 0, 6)
      assert has_element?(view, "#reader-#{badge}")

      view |> element("#reader-#{badge} button[phx-click='mine']") |> render_click()
      render_async(view)

      # Gone from the readers, and gone from every count on the site.
      refute has_element?(view, "#reader-#{badge}")
      assert Analytics.count_hits_today() == 0

      # The visits themselves are still there: the mark is reversible, and
      # this is what makes it so.
      assert Repo.aggregate(Hit, :count, :id) == 3

      view |> element("a.adm-tab", "Mine") |> render_click()
      assert has_element?(view, "#reader-#{badge}", "You")

      view |> element("#reader-#{badge} button[phx-click='not_mine']") |> render_click()
      render_async(view)

      assert Analytics.count_hits_today() == 3
    end

    test "a visitor who is the author offers no delete button", %{conn: conn} do
      hash = Analytics.hash_ip("192.0.2.10")
      today = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

      for path <- ["/blog", "/fitness"] do
        Repo.insert!(%Hit{ip_hash: hash, path: path, user_agent: "Firefox", inserted_at: today})
      end

      Owner.add(hash, source: "manual")

      {:ok, view, _html} = live(admin_conn(conn), "/admin/readers")
      render_async(view)

      view |> element("a.adm-tab", "Mine") |> render_click()

      badge = String.slice(hash, 0, 6)
      assert has_element?(view, "#reader-#{badge} button[phx-click='not_mine']")
      refute has_element?(view, "#reader-#{badge} button[phx-click='forget']")
    end

    test "the Mine tab says how to fill itself when it is empty", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/readers?show=mine")
      render_async(view)

      assert render(view) =~ "Find my own addresses"
      assert render(view) =~ "None of your own addresses are recognised yet"
    end
  end

  # The page asked for the top 150 of everything and sorted readers out
  # afterwards, so one scraper working from a few hundred addresses filled the
  # list and left no room for anybody real. Each view is cut on its own now.
  test "a flood of bot bursts does not push a real reader off the Readers tab",
       %{conn: conn} do
    burst = ~N[2026-10-07 13:06:36]

    rows =
      for b <- 1..160, i <- 1..25 do
        %{
          ip_hash: String.duplicate("F", 2) <> String.pad_leading("#{b}", 62, "0"),
          path: "/page-#{i}",
          user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/124.0.0.0",
          inserted_at: burst
        }
      end

    Repo.insert_all(Hit, rows)

    reader = "AAAAAA0E1FFDB7011232EB3C65EDC2D5A5DED208D11D1A8CD9188E5C978DBC4A"

    for {path, dt} <- [
          {"/blog", ~N[2026-10-10 21:00:00]},
          {"/fitness", ~N[2026-10-11 22:00:00]},
          {"/", ~N[2026-10-12 20:00:00]}
        ] do
      Repo.insert!(%Hit{
        ip_hash: reader,
        path: path,
        user_agent: "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) Safari/604.1",
        inserted_at: dt
      })
    end

    {:ok, view, _html} = live(admin_conn(conn), "/admin/readers")
    render_async(view)

    assert has_element?(view, "#reader-AAAAAA")
  end

  defp write_cache(map) do
    path = Application.get_env(:web, :reader_geo_cache_path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, Jason.encode!(map))
  end
end
