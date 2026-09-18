defmodule WebWeb.Plugs.MediaServeTest do
  @moduledoc """
  The dev-time media reader. In production Caddy answers `/uploads/*` off disk
  before Phoenix sees it, but this is the fallback, and the range arithmetic
  here is the sort that is either right or silently corrupts a seek.
  """

  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias WebWeb.Plugs.MediaServe

  @body "0123456789abcdef"

  setup do
    dir = Path.join(Web.Uploads.root(), "logs/mediaserve-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "v0"))
    File.write!(Path.join(dir, "master.m3u8"), @body)
    File.write!(Path.join(dir, "v0/seg000.m4s"), @body)
    File.write!(Path.join(dir, "poster.jpg"), @body)

    on_exit(fn -> File.rm_rf(dir) end)

    %{rel: Path.relative_to(dir, Web.Uploads.root())}
  end

  defp request(path, headers \\ [], method \\ :get) do
    Enum.reduce(headers, conn(method, path), fn {k, v}, acc -> put_req_header(acc, k, v) end)
    |> MediaServe.call([])
  end

  describe "content types" do
    test "an HLS playlist is served as one, which is what the player insists on", %{rel: rel} do
      conn = request("/uploads/#{rel}/master.m3u8")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/vnd.apple.mpegurl"]
    end

    test "a CMAF segment gets its own type too", %{rel: rel} do
      conn = request("/uploads/#{rel}/v0/seg000.m4s")
      assert get_resp_header(conn, "content-type") == ["video/iso.segment"]
    end

    test "a poster is an image", %{rel: rel} do
      conn = request("/uploads/#{rel}/poster.jpg")
      assert get_resp_header(conn, "content-type") == ["image/jpeg"]
    end
  end

  describe "ranges" do
    test "a byte range comes back as a partial, not the whole file", %{rel: rel} do
      conn = request("/uploads/#{rel}/poster.jpg", [{"range", "bytes=4-7"}])

      assert conn.status == 206
      assert get_resp_header(conn, "content-range") == ["bytes 4-7/16"]
      assert get_resp_header(conn, "content-length") == ["4"]
      assert conn.resp_body == "4567"
    end

    test "an open-ended range runs to the end of the file", %{rel: rel} do
      conn = request("/uploads/#{rel}/poster.jpg", [{"range", "bytes=10-"}])

      assert conn.status == 206
      assert get_resp_header(conn, "content-range") == ["bytes 10-15/16"]
      assert conn.resp_body == "abcdef"
    end

    test "a suffix range takes the last bytes", %{rel: rel} do
      conn = request("/uploads/#{rel}/poster.jpg", [{"range", "bytes=-4"}])

      assert conn.status == 206
      assert conn.resp_body == "cdef"
    end

    test "a suffix longer than the file is the whole file, not a negative offset",
         %{rel: rel} do
      conn = request("/uploads/#{rel}/poster.jpg", [{"range", "bytes=-999"}])

      assert conn.status == 206
      assert conn.resp_body == @body
    end

    test "a range past the end is refused with the file's size", %{rel: rel} do
      conn = request("/uploads/#{rel}/poster.jpg", [{"range", "bytes=99-200"}])

      assert conn.status == 416
      assert get_resp_header(conn, "content-range") == ["bytes */16"]
    end

    test "nonsense in the range header falls back to the whole file", %{rel: rel} do
      conn = request("/uploads/#{rel}/poster.jpg", [{"range", "bytes=abc-def"}])

      assert conn.status == 206
      assert conn.resp_body == @body
    end

    test "every response advertises that ranges are accepted", %{rel: rel} do
      conn = request("/uploads/#{rel}/poster.jpg")
      assert get_resp_header(conn, "accept-ranges") == ["bytes"]
    end
  end

  describe "conditional requests" do
    test "a reload costs a 304 rather than the bytes again", %{rel: rel} do
      first = request("/uploads/#{rel}/v0/seg000.m4s")
      [etag] = get_resp_header(first, "etag")

      second = request("/uploads/#{rel}/v0/seg000.m4s", [{"if-none-match", etag}])

      assert second.status == 304
      assert second.resp_body == ""
    end

    test "a stale etag gets the file", %{rel: rel} do
      conn = request("/uploads/#{rel}/v0/seg000.m4s", [{"if-none-match", ~s("nope")}])

      assert conn.status == 200
      assert conn.resp_body == @body
    end

    test "different files do not share an etag", %{rel: rel} do
      File.write!(Path.join(Web.Uploads.root(), "#{rel}/other.m4s"), "a different length here")

      a = get_resp_header(request("/uploads/#{rel}/v0/seg000.m4s"), "etag")
      b = get_resp_header(request("/uploads/#{rel}/other.m4s"), "etag")

      refute a == b
    end

    test "the cache lifetime is long, which the token in the directory name earns",
         %{rel: rel} do
      conn = request("/uploads/#{rel}/v0/seg000.m4s")
      assert get_resp_header(conn, "cache-control") == ["public, max-age=31536000, immutable"]
    end
  end

  test "HEAD reports the size without sending the file", %{rel: rel} do
    conn = request("/uploads/#{rel}/poster.jpg", [], :head)

    assert conn.status == 200
    assert get_resp_header(conn, "content-length") == ["16"]
    assert conn.resp_body == ""
  end

  describe "what it refuses" do
    test "a traversing path is not followed" do
      conn = request("/uploads/../../etc/passwd")
      refute conn.halted
      assert conn.status == nil
    end

    test "a missing file is left for the rest of the pipeline" do
      conn = request("/uploads/logs/nothing-here/master.m3u8")
      refute conn.halted
    end

    test "a directory is not served as a file", %{rel: rel} do
      conn = request("/uploads/#{rel}/v0")
      refute conn.halted
    end

    test "anything outside /uploads passes straight through" do
      conn = request("/blog")
      refute conn.halted
      assert conn.status == nil
    end
  end
end
