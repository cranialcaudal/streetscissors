defmodule Web.IndexNowTest do
  # The key is application config, so not async.
  use WebWeb.ConnCase, async: false
  use Oban.Testing, repo: Web.Repo

  alias Web.IndexNow
  alias Web.Workers.IndexNowPing

  defp with_key(key) do
    previous = Application.get_env(:web, :indexnow_key)
    Application.put_env(:web, :indexnow_key, key)
    on_exit(fn -> Application.put_env(:web, :indexnow_key, previous) end)
  end

  test "without a key nothing is queued and no key file is served", %{conn: conn} do
    with_key(nil)
    assert :ok = IndexNow.changed("/blog/a-post")
    refute_enqueued(worker: IndexNowPing)
    assert conn |> get("/indexnow.txt") |> response(404)
  end

  test "with a key, the file serves it and a change is queued", %{conn: conn} do
    with_key("abc123key")
    assert conn |> get("/indexnow.txt") |> response(200) == "abc123key"

    IndexNow.changed(["/blog/a-post", "/logs/2026-09-18"])

    assert_enqueued(
      worker: IndexNowPing,
      args: %{"paths" => ["/blog/a-post", "/logs/2026-09-18"]}
    )
  end

  test "a ping names the site, its key and the full addresses" do
    with_key("abc123key")

    Req.Test.stub(IndexNow, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      sent = Jason.decode!(body)
      assert sent["key"] == "abc123key"
      assert String.ends_with?(sent["keyLocation"], "/indexnow.txt")
      assert [url] = sent["urlList"]
      assert String.ends_with?(url, "/blog/a-post")
      Plug.Conn.send_resp(conn, 202, "")
    end)

    assert :ok = perform_job(IndexNowPing, %{"paths" => ["/blog/a-post"]})
  end

  test "a refused key is not retried" do
    with_key("abc123key")
    Req.Test.stub(IndexNow, &Plug.Conn.send_resp(&1, 403, ""))
    assert {:cancel, _} = perform_job(IndexNowPing, %{"paths" => ["/blog/a-post"]})
  end
end
