defmodule Web.Analytics.OwnerTest do
  # The owner set lives in one site_settings row and a :persistent_term key,
  # both of which outlive a test, so these run alone and clean up after
  # themselves.
  use Web.DataCase, async: false

  alias Web.Analytics
  alias Web.Analytics.Owner

  setup do
    # :persistent_term is outside the sandbox, so it is erased first and on its
    # own: the site_settings row is rolled back anyway, and a cleanup that
    # raised on the way to this line would leave the next test's visitor marked
    # as the author. That is how speed_test.exs — whose visitor is one of the
    # addresses below — started failing about one run in three.
    on_exit(fn -> :persistent_term.erase({Owner, :hashes}) end)

    Owner.reload()
    :ok
  end

  describe "the set" do
    test "a hash added is the owner's, and a hash removed is not" do
      hash = Analytics.hash_ip("203.0.113.111")

      refute Owner.mine?(hash)
      assert {:ok, 1} = Owner.add(hash, source: "manual")
      assert Owner.mine?(hash)
      assert Owner.mine_ip?("203.0.113.111")

      assert :ok = Owner.remove(hash)
      refute Owner.mine?(hash)
      refute Owner.mine_ip?("203.0.113.111")
    end

    test "adding the same hash twice keeps the day it was first recognised" do
      hash = Analytics.hash_ip("203.0.113.111")

      assert {:ok, 1} = Owner.add(hash, source: "admin-log")
      [%{since: first, source: "admin-log"}] = Owner.list()

      assert {:ok, 0} = Owner.add(hash, source: "manual")
      assert [%{since: ^first, source: "admin-log"}] = Owner.list()
    end

    test "the set survives a reload, because it is the one thing never rebuilt" do
      hash = Analytics.hash_ip("203.0.113.111")
      Owner.add(hash)

      :persistent_term.erase({Owner, :hashes})

      assert Owner.mine?(hash)
    end

    test "with nothing recorded, no address is the owner's and no hash is computed" do
      assert Owner.hash_list() == []
      refute Owner.mine_ip?("203.0.113.111")
    end
  end

  describe "a visit that is the owner's is not counted" do
    test "by hash, with a clean browser user agent and no EXCLUDED_IPS" do
      ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:157.0) Gecko/20100101 Firefox/157.0"

      assert WebWeb.Visitor.counted?("203.0.113.111", ua, false)

      Owner.add(Analytics.hash_ip("203.0.113.111"))

      refute WebWeb.Visitor.counted?("203.0.113.111", ua, false)
      assert WebWeb.Visitor.counted?("203.0.113.112", ua, false)
    end
  end

  describe "scan_access_logs/1" do
    setup do
      dir = Path.join(System.tmp_dir!(), "owner_log_test_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)
      {:ok, dir: dir}
    end

    test "an answered /admin page is the owner; a redirected one is not", %{dir: dir} do
      write(dir, "caddy_access.log", [
        line("192.0.2.10", "/admin/dashboard", 200),
        line("203.0.113.50", "/admin/blog/a-post/edit", 302)
      ])

      assert addresses(Owner.scan_access_logs(dir: dir)) == ["192.0.2.10"]
    end

    # /admin/login is a public page: it is answered for anyone who asks. Five
    # addresses in the real log have a 200 there and nothing else, and reading
    # those as the author would hide five strangers from the page.
    test "a 200 on /admin/login is not evidence of anything", %{dir: dir} do
      write(dir, "caddy_access.log", [
        line("203.0.113.51", "/admin/login", 200),
        line("203.0.113.52", "/admin/logout", 200)
      ])

      assert Owner.scan_access_logs(dir: dir) == %{}
    end

    test "a scanner probing for an admin it guessed at is not the owner", %{dir: dir} do
      write(dir, "caddy_access.log", [
        line("203.0.113.53", "/admin.php", 404),
        line("203.0.113.54", "/admin/elmah.axd/", 404),
        line("203.0.113.55", "/adminfuns.php", 404)
      ])

      assert Owner.scan_access_logs(dir: dir) == %{}
    end

    test "loopback is the proxy, not a visitor", %{dir: dir} do
      write(dir, "caddy_access.log", [line("127.0.0.1", "/admin/dashboard", 200)])

      assert Owner.scan_access_logs(dir: dir) == %{}
    end

    # Most admin traffic is the LiveView socket, which names the admin page it
    # belongs to in its query. One of those could be typed by anyone (they are
    # refused, and the refusal is logged all the same), so it takes a few.
    test "a longpoll naming an admin page counts once it keeps happening", %{dir: dir} do
      write(dir, "caddy_access.log", [
        longpoll("203.0.113.60", "/admin/dashboard"),
        longpoll("203.0.113.61", "/admin/darkroom"),
        longpoll("203.0.113.61", "/admin/darkroom"),
        longpoll("203.0.113.61", "/admin/darkroom")
      ])

      assert addresses(Owner.scan_access_logs(dir: dir)) == ["203.0.113.61"]
    end

    # Until 2026-10-31 the glob was `caddy_access*.log`, which matches the live
    # file and none of the rotations — the window was five days of a five-month
    # history, which is why almost every reader's location was a guess.
    test "the gzipped rotations are read too", %{dir: dir} do
      write(dir, "caddy_access.log", [line("192.0.2.10", "/admin/dashboard", 200)])

      write_gz(dir, "caddy_access-2026-10-07T21-15-21.111.log.gz", [
        line("198.51.100.26", "/admin/settings", 200)
      ])

      assert addresses(Owner.scan_access_logs(dir: dir)) == ["192.0.2.10", "198.51.100.26"]
    end

    test "a rotation that ends mid-line gives up what it had" do
      dir = Path.join(System.tmp_dir!(), "owner_trunc_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)

      whole = line("198.51.100.26", "/admin/settings", 200) <> "\n"
      File.write!(Path.join(dir, "caddy_access.log"), whole <> String.slice(whole, 0, 40))

      assert addresses(Owner.scan_access_logs(dir: dir)) == ["198.51.100.26"]
    end

    # An answered admin request proves the address was the author's when it
    # was made, not that every visit from it was: a reassigned address may
    # later be read from other devices by someone else. So nothing is marked
    # without being looked at.
    test "a log candidate is proposed, not recorded", %{dir: dir} do
      hash = Analytics.hash_ip("203.0.113.50")
      Analytics.record_hit("/blog", "Mozilla/5.0 (X11; CrOS x86_64) Chrome/152", hash)

      write(dir, "caddy_access.log", [line("203.0.113.50", "/admin/dashboard", 200)])

      assert {:ok, %{candidates: 1}} = Owner.refresh(dir: dir)

      refute Owner.mine?(hash)
      assert Analytics.count_hits_today() == 1
    end

    test "a candidate carries the session's browser beside the visits' own", %{dir: dir} do
      hash = Analytics.hash_ip("203.0.113.50")

      for _ <- 1..3,
          do:
            Analytics.record_hit(
              "/blog",
              "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) Safari/604.1",
              hash
            )

      write(dir, "caddy_access.log", [
        line(
          "203.0.113.50",
          "/admin/dashboard",
          200,
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:154.0) Gecko/20100101 Firefox/154.0"
        )
      ])

      assert [candidate] = Owner.candidates(dir: dir)

      assert candidate.hash == hash
      assert candidate.admin_requests == 1
      assert candidate.admin_agents == ["Mac"]
      assert candidate.hits == 3
      assert candidate.devices == ["iPhone"]
      assert %DateTime{} = candidate.admin_first
    end

    # The home address, whose visits were already deleted by hand. Every key
    # is still there, so the page does not have to ask whether it got a row.
    test "a candidate with no visits left still comes back whole", %{dir: dir} do
      write(dir, "caddy_access.log", [line("192.0.2.10", "/admin/dashboard", 200)])

      assert [candidate] = Owner.candidates(dir: dir)

      assert candidate.hits == 0
      assert candidate.days == 0
      assert candidate.devices == []
      assert candidate.first_seen == nil
      assert candidate.admin_requests == 1
    end

    # Nothing is hidden by recording a hash with no visits, and ten of the
    # twenty the live log turned up were exactly that. Asking about them
    # buries the ones where being wrong costs a reader their history.
    test "a candidate with nothing to hide is recorded without asking", %{dir: dir} do
      with_visits = Analytics.hash_ip("203.0.113.50")
      Analytics.record_hit("/blog", "Firefox", with_visits)

      write(dir, "caddy_access.log", [
        line("203.0.113.50", "/admin/dashboard", 200),
        line("198.51.100.26", "/admin/settings", 200)
      ])

      assert {:ok, %{added: 1, candidates: 1}} = Owner.refresh(dir: dir)

      # The one with no visits is simply the author's now; the one with reading against
      # it is still a question.
      assert Owner.mine_ip?("198.51.100.26")
      refute Owner.mine?(with_visits)
      assert [%{hash: ^with_visits}] = Owner.candidates(dir: dir)
    end

    test "a hash already recorded is not proposed again", %{dir: dir} do
      Owner.add(Analytics.hash_ip("192.0.2.10"), source: "manual")
      write(dir, "caddy_access.log", [line("192.0.2.10", "/admin/dashboard", 200)])

      assert Owner.candidates(dir: dir) == []
    end

    # Without this the nightly scan proposes the same reader every night for
    # as long as the log remembers the address.
    test "a hash left as a reader stops being proposed", %{dir: dir} do
      hash = Analytics.hash_ip("203.0.113.50")
      write(dir, "caddy_access.log", [line("203.0.113.50", "/admin/dashboard", 200)])

      assert [%{hash: ^hash}] = Owner.candidates(dir: dir)

      assert :ok = Owner.dismiss(hash)
      assert Owner.candidates(dir: dir) == []
      refute Owner.mine?(hash)

      assert :ok = Owner.undismiss(hash)
      assert [%{hash: ^hash}] = Owner.candidates(dir: dir)
    end

    test "the addresses named in EXCLUDED_IPS are recorded without asking", %{dir: dir} do
      System.put_env("EXCLUDED_IPS", "192.0.2.10")
      on_exit(fn -> System.delete_env("EXCLUDED_IPS") end)

      assert {:ok, %{added: 1}} = Owner.refresh(dir: dir)
      assert Owner.mine_ip?("192.0.2.10")
    end
  end

  describe "hashes_from_excluded_ips/0" do
    test "takes the addresses named outright and leaves the ranges alone" do
      System.put_env("EXCLUDED_IPS", "192.0.2.10,192.0.2.0/24,203.0.*,not-an-address")
      on_exit(fn -> System.delete_env("EXCLUDED_IPS") end)

      assert Owner.hashes_from_excluded_ips() == [Analytics.hash_ip("192.0.2.10")]
    end
  end

  defp addresses(found),
    do: found |> Map.values() |> Enum.map(& &1.ip) |> Enum.sort()

  defp write(dir, name, lines),
    do: File.write!(Path.join(dir, name), Enum.map_join(lines, "\n", & &1) <> "\n")

  defp write_gz(dir, name, lines),
    do:
      File.write!(
        Path.join(dir, name),
        :zlib.gzip(Enum.map_join(lines, "\n", & &1) <> "\n")
      )

  defp line(ip, uri, status, agent \\ "Mozilla/5.0") do
    Jason.encode!(%{
      "level" => "info",
      "ts" => 1_793_009_858.371467,
      "msg" => "handled request",
      "request" => %{
        "client_ip" => ip,
        "remote_ip" => ip,
        "method" => "GET",
        "host" => "streetscissors.com",
        "uri" => uri,
        "headers" => %{"User-Agent" => [agent]}
      },
      "status" => status
    })
  end

  defp longpoll(ip, admin_path) do
    referer = URI.encode_www_form("https://streetscissors.com" <> admin_path)
    line(ip, "/live/longpoll?_csrf_token=x&_live_referer=#{referer}", 200)
  end
end
