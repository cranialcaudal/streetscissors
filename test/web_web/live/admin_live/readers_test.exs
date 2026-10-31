defmodule WebWeb.AdminLive.ReadersTest do
  use WebWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Web.Analytics.Hit
  alias Web.Repo

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  setup do
    cache_path = Application.get_env(:web, :reader_geo_cache_path)
    if is_binary(cache_path), do: File.rm(cache_path)
    on_exit(fn -> if is_binary(cache_path), do: File.rm(cache_path) end)
    :ok
  end

  test "anonymous visitors are redirected away", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/readers")
  end

  test "renders GeoIP-resolved and behavior-guessed locations and removes a visitor on request",
       %{conn: conn} do
    # 1. A reader matched in the GeoIP cache
    geo_hash = "533021A0E1FFDB7011232EB3C65EDC2D5A5DED208D11D1A8CD9188E5C978DBC4"

    cache_path = Application.get_env(:web, :reader_geo_cache_path)
    File.mkdir_p!(Path.dirname(cache_path))

    File.write!(
      cache_path,
      Jason.encode!(%{
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
    )

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

    refute has_element?(view, "#reader-9ABA3F")
  end
end
