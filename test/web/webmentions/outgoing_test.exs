defmodule Web.Webmentions.OutgoingTest do
  use Web.DataCase
  use Oban.Testing, repo: Web.Repo

  alias Web.Webmentions.Outgoing
  alias Web.Webmentions.Sent
  alias Web.Workers.WebmentionSender

  # Hosts under .internal resolve to a private address, everything else to a
  # public one (Web.WebmentionsTestResolver); Req.Test stands in for the web.
  @theirs "https://example.org/notes/ferry"

  setup do
    tmp = Path.join(System.tmp_dir!(), "outgoing-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    original = Application.get_env(:web, :blog_path)
    Application.put_env(:web, :blog_path, tmp)

    on_exit(fn ->
      File.rm_rf!(tmp)
      Application.put_env(:web, :blog_path, original)
    end)

    {:ok, tmp: tmp}
  end

  defp write_post(tmp, slug, body) do
    File.write!(Path.join(tmp, slug <> ".md"), "---\ntitle: #{slug}\n---\n\n#{body}\n")
  end

  defp stub(fun), do: Req.Test.stub(Web.Webmentions, fun)

  # A site that takes webmentions at /webmention, and records what it is sent.
  defp receiving_site(test_pid, opts \\ []) do
    status = Keyword.get(opts, :status, 202)

    stub(fn
      %{method: "GET"} = conn ->
        Req.Test.html(
          conn,
          ~s(<html><head><link rel="webmention" href="/webmention"></head></html>)
        )

      %{method: "POST", request_path: "/webmention"} = conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:posted, URI.decode_query(body)})
        Plug.Conn.send_resp(conn, status, "")
    end)
  end

  describe "citations/0" do
    test "is every link a published post makes to another site", %{tmp: tmp} do
      write_post(tmp, "essay", """
      As [someone wrote](#{@theirs}), and as [I wrote](/blog/other), and
      [again by full name](http://localhost/blog/other).

      <iframe src="https://player.example.com/embed/1"></iframe>

      ![A picture hosted elsewhere](https://images.example.com/a.png)
      """)

      assert Outgoing.citations() == [{"/blog/essay", @theirs}]
    end

    test "a draft cites nobody yet", %{tmp: tmp} do
      File.write!(Path.join(tmp, "wip.md"), "---\ndraft: true\n---\n\n[A link](#{@theirs}).\n")
      assert Outgoing.citations() == []
    end
  end

  describe "run/0" do
    test "queues each new link once", %{tmp: tmp} do
      write_post(tmp, "essay", "[One](#{@theirs}) and [two](https://example.net/b).")

      assert Outgoing.run() == %{queued: 2, withdrawn: 0}
      assert [%Sent{status: "queued"}, %Sent{status: "queued"}] = Outgoing.list()
      assert length(all_enqueued(worker: WebmentionSender)) == 2

      # The next hour finds nothing new.
      assert Outgoing.run() == %{queued: 0, withdrawn: 0}
      assert length(all_enqueued(worker: WebmentionSender)) == 2
    end

    test "run_scheduled/0 can be switched off, and never raises", %{tmp: tmp} do
      write_post(tmp, "essay", "[One](#{@theirs}).")
      Application.put_env(:web, :webmention_send, false)
      on_exit(fn -> Application.delete_env(:web, :webmention_send) end)

      assert Outgoing.run_scheduled() == :ok
      assert Outgoing.list() == []
    end
  end

  describe "deliver/1" do
    setup %{tmp: tmp} do
      write_post(tmp, "essay", "As [someone wrote](#{@theirs}).")
      Outgoing.run()
      [sent] = Outgoing.list()
      {:ok, sent: sent}
    end

    test "posts our page and theirs to the endpoint their page names", %{sent: sent} do
      receiving_site(self())

      assert :ok = perform_job(WebmentionSender, %{"id" => sent.id})

      assert_received {:posted, %{"source" => source, "target" => @theirs}}
      assert source =~ ~r{^http://localhost:\d+/blog/essay$}

      assert %Sent{status: "sent", endpoint: "https://example.org/webmention", sent_at: at} =
               Outgoing.get!(sent.id)

      assert %DateTime{} = at
    end

    test "a Link header wins over the document, and may be relative", %{sent: sent} do
      test = self()

      stub(fn
        %{method: "GET"} = conn ->
          conn
          |> Plug.Conn.put_resp_header(
            "link",
            ~s(<https://other.example/x>; rel="other", </wm/in>; rel="webmention")
          )
          |> Req.Test.html(~s(<link rel="webmention" href="/from-the-document">))

        %{method: "POST"} = conn ->
          send(test, {:posted_to, conn.request_path})
          Plug.Conn.send_resp(conn, 201, "")
      end)

      assert :ok = Outgoing.deliver(sent.id)
      assert_received {:posted_to, "/wm/in"}
    end

    # Most of the web takes none, and that is not a fault.
    test "a page with no endpoint is noted and nothing is posted", %{sent: sent} do
      stub(fn %{method: "GET"} = conn ->
        Req.Test.html(conn, "<html><body>No endpoint.</body></html>")
      end)

      assert :ok = Outgoing.deliver(sent.id)
      assert %Sent{status: "no_endpoint", endpoint: nil} = Outgoing.get!(sent.id)
    end

    test "an endpoint on a private address is refused, not posted to", %{sent: sent} do
      stub(fn
        %{method: "GET"} = conn ->
          Req.Test.html(conn, ~s(<link rel="webmention" href="http://router.internal/admin">))

        %{method: "POST"} ->
          flunk("posted to a private address")
      end)

      assert :ok = Outgoing.deliver(sent.id)
      assert %Sent{status: "failed", detail: "refused: private_address"} = Outgoing.get!(sent.id)
    end

    test "an endpoint that says no is a failure that is not retried", %{sent: sent} do
      receiving_site(self(), status: 400)

      assert :ok = Outgoing.deliver(sent.id)
      assert %Sent{status: "failed", detail: "answered 400"} = Outgoing.get!(sent.id)
    end

    test "a site that cannot be reached is recorded, and the job retried", %{sent: sent} do
      stub(fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, _} = Outgoing.deliver(sent.id)

      assert %Sent{status: "failed", detail: "could not connect: econnrefused"} =
               Outgoing.get!(sent.id)
    end

    test "retry/1 queues a failure again", %{sent: sent} do
      stub(fn %{method: "GET"} = conn -> Req.Test.html(conn, "<html></html>") end)
      :ok = Outgoing.deliver(sent.id)

      assert {:ok, _job} = sent.id |> Outgoing.get!() |> Outgoing.retry()
      assert %Sent{status: "queued", detail: nil} = Outgoing.get!(sent.id)
    end

    test "a row that was deleted meanwhile is nothing to do" do
      assert Outgoing.deliver(-1) == :ok
    end
  end

  # The receiver re-reads our page when pinged; with the link gone it drops
  # the citation. So a removed link is announced once more, then forgotten.
  test "a link that leaves its post is announced once more, as a withdrawal", %{tmp: tmp} do
    write_post(tmp, "essay", "As [someone wrote](#{@theirs}).")
    receiving_site(self())
    Outgoing.run()
    [sent] = Outgoing.list()
    :ok = Outgoing.deliver(sent.id)
    assert_received {:posted, _}

    write_post(tmp, "essay", "I have thought better of citing anyone.")
    assert Outgoing.run() == %{queued: 0, withdrawn: 1}

    :ok = Outgoing.deliver(sent.id)
    assert_received {:posted, %{"target" => @theirs}}
    assert %Sent{status: "withdrawn"} = Outgoing.get!(sent.id)

    # And that is the end of it.
    assert Outgoing.run() == %{queued: 0, withdrawn: 0}
  end
end
