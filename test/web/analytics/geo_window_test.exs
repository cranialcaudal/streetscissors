defmodule Web.Analytics.GeoWindowTest do
  # The location cache is one file on disk, shared by every test that touches it.
  use Web.DataCase, async: false

  alias Web.Analytics
  alias Web.Analytics.{AccessLog, Hit, Owner}

  setup do
    cache = Application.get_env(:web, :reader_geo_cache_path)
    File.mkdir_p!(Path.dirname(cache))
    File.rm(cache)

    on_exit(fn -> :persistent_term.erase({Owner, :hashes}) end)
    on_exit(fn -> File.rm(cache) end)

    Owner.reload()
    {:ok, cache: cache}
  end

  describe "the access log on disk" do
    setup do
      dir = Path.join(System.tmp_dir!(), "geo_window_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)
      {:ok, dir: dir}
    end

    # Caddy rolls its own log and gzips what it rolls. The scan globbed
    # `caddy_access*.log`, which matches the live file and none of the
    # rotations — five and a half days of a five-month history, which is why
    # nearly every reader's location was a timezone guess.
    test "the gzipped rotations are read, not only the live file", %{dir: dir} do
      File.write!(Path.join(dir, "caddy_access.log"), line("198.51.100.1") <> "\n")

      File.write!(
        Path.join(dir, "caddy_access-2026-10-07T21-15-21.111.log.gz"),
        :zlib.gzip(line("198.51.100.2") <> "\n" <> line("198.51.100.3") <> "\n")
      )

      ips =
        AccessLog.reduce_lines(
          [],
          fn l, acc ->
            case Regex.run(~r/"client_ip":"([^"]+)"/, l) do
              [_, ip] -> [ip | acc]
              _ -> acc
            end
          end,
          dir: dir
        )

      assert Enum.sort(ips) == ["198.51.100.1", "198.51.100.2", "198.51.100.3"]
    end

    test "a line split across two inflate chunks is still one line", %{dir: dir} do
      # Well over the 256 KB read size, so the lines certainly straddle chunks.
      body = Enum.map_join(1..4000, "", fn i -> line("198.51.100.#{rem(i, 250) + 1}") <> "\n" end)
      File.write!(Path.join(dir, "caddy_access-old.log.gz"), :zlib.gzip(body))

      whole =
        AccessLog.reduce_lines(0, fn l, n -> if AccessLog.decode(l), do: n + 1, else: n end,
          dir: dir
        )

      assert whole == 4000
    end

    test "coverage/1 says what the logs can answer for", %{dir: dir} do
      File.write!(Path.join(dir, "caddy_access.log"), line("198.51.100.1") <> "\n")

      assert %{files: 1, ips: 1, earliest: %DateTime{}} = AccessLog.coverage(dir: dir)
    end

    test "no log directory is not an error", %{} do
      assert AccessLog.files(dir: nil) == []
      assert AccessLog.coverage(dir: nil) == %{files: 0, earliest: nil, ips: 0}
    end
  end

  describe "prune_geo_cache/0" do
    test "forgets the location of a visitor the site has forgotten", %{cache: cache} do
      gone = String.duplicate("A", 64)
      here = String.duplicate("B", 64)
      mine = Analytics.hash_ip("192.0.2.10")

      File.write!(
        cache,
        Jason.encode!(%{
          gone => %{"city" => "Harborview"},
          here => %{"city" => "Riverton"},
          mine => %{"city" => "Lakeside"}
        })
      )

      Repo.insert!(%Hit{
        ip_hash: here,
        path: "/blog",
        inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
      })

      Owner.add(mine, source: "manual")

      assert {:ok, 1} = Analytics.prune_geo_cache()

      kept = Analytics.load_geo_cache()

      # The visitor still in the table keeps theirs; so does the author, whose
      # hashes have no hits to point at once his visits are left out.
      assert Map.has_key?(kept, here)
      assert Map.has_key?(kept, mine)
      refute Map.has_key?(kept, gone)
    end

    test "an empty cache is left alone" do
      assert {:ok, 0} = Analytics.prune_geo_cache()
    end
  end

  defp line(ip) do
    Jason.encode!(%{
      "level" => "info",
      "ts" => 1_793_009_858.371467,
      "request" => %{"client_ip" => ip, "uri" => "/blog", "method" => "GET"},
      "status" => 200
    })
  end
end
