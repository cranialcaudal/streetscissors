defmodule Web.WebmentionsTest do
  use Web.DataCase
  use Oban.Testing, repo: Web.Repo

  alias Web.Webmentions
  alias Web.Webmentions.Webmention

  # Our host in the test endpoint is localhost; hosts under .internal resolve
  # to a private address (Web.WebmentionsTestResolver).
  @host "localhost"
  @target "http://localhost:4000/blog/keyworded-post"
  @source "https://example.org/notes/ferry"

  defp page(body), do: fn conn -> Req.Test.html(conn, body) end

  defp citing_page do
    page("""
    <html><head><title>Notes on the ferry</title></head>
    <body><article class="h-entry"><a class="p-author h-card" href="/">Grace</a>
    <p>As <a href="#{@target}">streetscissors wrote</a>.</p></article></body></html>
    """)
  end

  describe "receive/3" do
    test "a mention of one of our pieces is stored and queued" do
      assert {:ok, %Webmention{status: "pending", piece: "post:keyworded-post"} = mention} =
               Webmentions.receive(@source, @target, @host)

      assert mention.source_host == "example.org"
      assert_enqueued(worker: Web.Workers.WebmentionVerifier, args: %{"id" => mention.id})
    end

    test "anything that isn't a mention of one of our pieces is refused" do
      assert {:error, :not_a_web_url} = Webmentions.receive("ftp://example.org/x", @target, @host)

      assert {:error, :target_not_ours} =
               Webmentions.receive(@source, "https://elsewhere.test/blog/keyworded-post", @host)

      assert {:error, :source_is_ours} =
               Webmentions.receive("http://localhost:4000/blog/x", @target, @host)

      assert {:error, :unknown_target} =
               Webmentions.receive(@source, "http://localhost:4000/about", @host)

      assert {:error, :unknown_target} =
               Webmentions.receive(@source, "http://localhost:4000/blog/no-such-post", @host)
    end

    test "a second ping re-verifies the same row rather than adding one" do
      {:ok, first} = Webmentions.receive(@source, @target, @host)
      {:ok, second} = Webmentions.receive(@source, @target, @host)
      assert first.id == second.id
    end
  end

  describe "verify/1" do
    setup do
      {:ok, mention} = Webmentions.receive(@source, @target, @host)
      %{mention: mention}
    end

    test "a source that links to the target is held for approval, with its title and author", %{
      mention: mention
    } do
      Req.Test.stub(Web.Webmentions, citing_page())

      assert :ok = Webmentions.verify(mention.id)

      assert %{status: "held", title: "Notes on the ferry", author_name: "Grace"} =
               Repo.reload(mention)
    end

    test "a source that doesn't link is gone, and comes back once it does", %{mention: mention} do
      Req.Test.stub(Web.Webmentions, page("<p>No link here.</p>"))
      Webmentions.verify(mention.id)
      assert %{status: "gone"} = Repo.reload(mention)

      Req.Test.stub(Web.Webmentions, citing_page())
      Webmentions.verify(mention.id)
      assert %{status: "held"} = Repo.reload(mention)
    end

    test "a 410 takes an approved mention off the page", %{mention: mention} do
      {:ok, _} = Webmentions.approve(mention)
      Req.Test.stub(Web.Webmentions, fn conn -> Plug.Conn.send_resp(conn, 410, "") end)

      Webmentions.verify(mention.id)
      assert %{status: "gone"} = Repo.reload(mention)
    end

    test "re-verifying an approved mention keeps it approved; a rejection sticks", %{
      mention: mention
    } do
      Req.Test.stub(Web.Webmentions, citing_page())

      {:ok, _} = Webmentions.approve(mention)
      Webmentions.verify(mention.id)
      assert %{status: "approved"} = Repo.reload(mention)

      {:ok, _} = Webmentions.reject(Repo.reload(mention))
      Webmentions.verify(mention.id)
      assert %{status: "rejected"} = Repo.reload(mention)
    end

    test "a source on a private address is never fetched" do
      {:ok, mention} = Webmentions.receive("http://router.internal/admin", @target, @host)
      Req.Test.stub(Web.Webmentions, fn _conn -> flunk("a private address was fetched") end)

      Webmentions.verify(mention.id)
      assert %{status: "gone"} = Repo.reload(mention)
    end

    test "a redirect into a private address is refused", %{mention: mention} do
      Req.Test.stub(Web.Webmentions, fn conn ->
        if conn.host == "example.org" do
          conn
          |> Plug.Conn.put_resp_header("location", "http://router.internal/")
          |> Plug.Conn.send_resp(302, "")
        else
          flunk("the redirect was followed to #{conn.host}")
        end
      end)

      Webmentions.verify(mention.id)
      assert %{status: "gone"} = Repo.reload(mention)
    end

    test "a public redirect is followed", %{mention: mention} do
      Req.Test.stub(Web.Webmentions, fn conn ->
        if conn.request_path == "/notes/ferry" do
          conn
          |> Plug.Conn.put_resp_header("location", "/notes/ferry-2")
          |> Plug.Conn.send_resp(301, "")
        else
          citing_page().(conn)
        end
      end)

      Webmentions.verify(mention.id)
      assert %{status: "held"} = Repo.reload(mention)
    end

    test "a transport failure is retried rather than decided", %{mention: mention} do
      Req.Test.stub(Web.Webmentions, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, _} = Webmentions.verify(mention.id)
      assert %{status: "pending"} = Repo.reload(mention)
    end
  end

  test "private, loopback, link-local and CGNAT addresses are not public" do
    for address <- [
          {127, 0, 0, 1},
          {10, 1, 2, 3},
          {172, 16, 0, 1},
          {192, 168, 1, 1},
          {169, 254, 1, 1},
          {100, 64, 0, 1},
          {0, 0, 0, 0},
          {0, 0, 0, 0, 0, 0, 0, 1},
          {0xFD00, 0, 0, 0, 0, 0, 0, 1},
          {0xFE80, 0, 0, 0, 0, 0, 0, 1},
          {0, 0, 0, 0, 0, 0xFFFF, 0x7F00, 1}
        ] do
      refute Webmentions.public_address?(address), "#{inspect(address)} passed as public"
    end

    assert Webmentions.public_address?({93, 184, 216, 34})
    assert Webmentions.public_address?({0x2606, 0x2800, 0x220, 1, 0x248, 0x1893, 0x25C8, 0x1946})
  end
end
