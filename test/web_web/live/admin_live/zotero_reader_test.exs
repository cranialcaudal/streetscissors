defmodule WebWeb.AdminLive.ZoteroReaderTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest

  @md5 "0123456789abcdef0123456789abcdef"

  setup do
    original = Application.get_env(:web, :zotero)
    original_cache = Application.get_env(:web, :zotero_cache_path)
    cache = Path.join(System.tmp_dir!(), "zotero-reader-#{System.unique_integer([:positive])}")
    Application.put_env(:web, :zotero, user_id: "12345", api_key: "test-key")
    Application.put_env(:web, :zotero_cache_path, cache)

    on_exit(fn ->
      File.rm_rf!(cache)
      Application.put_env(:web, :zotero, original)

      if original_cache,
        do: Application.put_env(:web, :zotero_cache_path, original_cache),
        else: Application.delete_env(:web, :zotero_cache_path)
    end)

    {:ok, cache: cache}
  end

  @book %{
    "key" => "BOOK0001",
    "data" => %{
      "key" => "BOOK0001",
      "itemType" => "book",
      "title" => "Tide Tables of the Sound",
      "creators" => [%{"creatorType" => "author", "lastName" => "Vance", "firstName" => "Clara"}],
      "date" => "2021"
    }
  }

  @pdf %{
    "key" => "PDF00001",
    "data" => %{
      "itemType" => "attachment",
      "parentItem" => "BOOK0001",
      "linkMode" => "imported_file",
      "contentType" => "application/pdf",
      "title" => "Full text",
      "md5" => @md5
    }
  }

  @highlight %{
    "key" => "ANN00001",
    "version" => 7,
    "data" => %{
      "annotationType" => "highlight",
      "annotationText" => "Slack water holds for eleven minutes.",
      "annotationComment" => "The opening.",
      "annotationColor" => "#ffd400",
      "annotationPageLabel" => "19",
      "annotationSortIndex" => "00018|000120|00300",
      "annotationPosition" => ~s({"pageIndex":18,"rects":[[1,2,3,4]]})
    }
  }

  # A library of one book, one PDF and its one highlight. Writes are sent to
  # the test process to look at; with `refuse: true` Zotero answers them 500.
  defp library(test, opts \\ []) do
    Req.Test.stub(Web.Writing.Zotero, fn conn ->
      case {conn.method, conn.request_path, conn.query_params["itemType"]} do
        {"GET", "/users/12345/items/BOOK0001", _} ->
          Req.Test.json(conn, @book)

        {"GET", "/users/12345/items/PDF00001", _} ->
          Req.Test.json(conn, @pdf)

        {"GET", "/users/12345/items/BOOK0001/children", "attachment"} ->
          Req.Test.json(conn, [@pdf])

        {"GET", "/users/12345/items/BOOK0001/children", "note"} ->
          Req.Test.json(conn, [
            %{"key" => "NOTE0001", "data" => %{"note" => "<p>Read twice.</p>"}}
          ])

        {"GET", "/users/12345/items/PDF00001/children", "annotation"} ->
          Req.Test.json(conn, [@highlight])

        {"GET", "/users/12345/items/PDF00001/file", _} ->
          send(test, :file_fetched)
          Plug.Conn.send_resp(conn, 200, "%PDF-1.7 0123456789")

        {method, path, _} ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          send(test, {:write, method, path, body})

          cond do
            opts[:refuse] ->
              Plug.Conn.send_resp(conn, 500, "down")

            method == "POST" ->
              Req.Test.json(conn, %{"successful" => %{"0" => %{"key" => "NEW00001"}}})

            true ->
              Plug.Conn.send_resp(conn, 204, "")
          end
      end
    end)
  end

  test "anonymous visitors are turned away from the reader and the file", %{conn: conn} do
    assert {:error, {:redirect, _}} = live(conn, "/admin/zotero/BOOK0001")
    assert get(conn, "/admin/zotero/file/PDF00001/#{@md5}").status == 404
  end

  test "opens the item's PDF beside its annotations and notes", %{conn: conn} do
    library(self())

    {:ok, view, _html} =
      live(log_in_admin(conn), "/admin/zotero/BOOK0001?back=/admin/blog/essay/edit")

    render_async(view)

    assert has_element?(view, ".adm-title", "Tide Tables of the Sound")

    assert has_element?(
             view,
             ~s(#reader-PDF00001[phx-hook=ZoteroReader][data-kind=pdf][data-src="/admin/zotero/file/PDF00001/#{@md5}"])
           )

    assert has_element?(view, "#ann-ANN00001 blockquote", "Slack water holds")
    assert has_element?(view, "#ann-ANN00001 .adm-reader-swatch.adm-ann--yellow")
    assert has_element?(view, "#ann-ANN00001", "p. 19")
    assert has_element?(view, "#note-NOTE0001", "Read twice.")
    assert has_element?(view, ~s(a[href="/admin/blog/essay/edit"]), "Back")

    # The hook, once the document is open, is given the marks to draw.
    view |> element("#reader-PDF00001") |> render_hook("reader_ready", %{})

    assert_reply(view, %{
      annotations: [%{key: "ANN00001", color_name: "yellow", position: %{"pageIndex" => 18}}]
    })
  end

  test "a return address outside the admin is not followed", %{conn: conn} do
    library(self())

    {:ok, view, _html} =
      live(log_in_admin(conn), "/admin/zotero/BOOK0001?back=https://example.org")

    render_async(view)
    assert has_element?(view, ~s(a[href="/admin/blog"]), "Back")
  end

  test "a selection in the document is offered as a highlight, and saved to Zotero", %{conn: conn} do
    library(self())
    {:ok, view, _html} = live(log_in_admin(conn), "/admin/zotero/BOOK0001")
    render_async(view)

    # The toolbar is there all along, idle until something is selected.
    assert has_element?(view, "#annotate-form button[disabled]", "Highlight")
    assert has_element?(view, "#reader-picked", "Select text in the document")

    view
    |> element("#reader-PDF00001")
    |> render_hook("selection", %{
      "text" => "The ferries  wait.",
      "position" => %{"pageIndex" => 2, "rects" => [[10, 20, 30, 40]]},
      "sort_index" => "00002|000050|00100",
      "page_label" => "3"
    })

    assert has_element?(view, "#reader-picked", "“The ferries wait.”")
    refute has_element?(view, "#annotate-form button[disabled]", "Highlight")
    # The reading page is not a draft: nothing to quote into.
    refute has_element?(view, "#reader-quote-selection")

    view
    |> form("#annotate-form", highlight: %{color: "green", comment: "Tie to the hook."})
    |> render_submit(%{"type" => "underline"})

    render_async(view)
    assert_received {:write, "POST", "/users/12345/items", body}

    assert [
             %{
               "parentItem" => "PDF00001",
               "annotationType" => "underline",
               "annotationText" => "The ferries wait.",
               "annotationColor" => "#5fb236",
               "annotationComment" => "Tie to the hook.",
               "annotationPageLabel" => "3",
               "annotationSortIndex" => "00002|000050|00100"
             }
           ] = Jason.decode!(body)

    assert_push_event(view, "reader:clear_selection", %{})
    assert has_element?(view, "#flash-info", "Saved to Zotero.")
    assert has_element?(view, "#annotate-form button[disabled]", "Highlight")
    # The comment box comes back empty, in the colour last used.
    refute has_element?(view, ~s(#annotate-form input[value="Tie to the hook."]))
    assert has_element?(view, ~s(#annotate-form input[value=green][checked]))
  end

  test "a save Zotero refuses is said so, and the toolbar is usable again", %{conn: conn} do
    library(self(), refuse: true)

    {:ok, view, _html} = live(log_in_admin(conn), "/admin/zotero/BOOK0001")
    render_async(view)

    view
    |> element("#reader-PDF00001")
    |> render_hook("selection", %{
      "text" => "The ferries wait.",
      "position" => %{"pageIndex" => 2, "rects" => [[10, 20, 30, 40]]},
      "sort_index" => "00002|000050|00100",
      "page_label" => "3"
    })

    view
    |> form("#annotate-form", highlight: %{color: "red", comment: "Keep me."})
    |> render_submit()

    render_async(view)

    assert has_element?(view, "#flash-error", "Not saved")
    # The selection and the comment are still there to try again.
    refute has_element?(view, "#annotate-form button[disabled]", "Highlight")
    assert has_element?(view, ~s(#annotate-form input[value="Keep me."]))
  end

  test "a reader event that reaches the page is let go, not a crash", %{conn: conn} do
    library(self())
    {:ok, view, _html} = live(log_in_admin(conn), "/admin/zotero/BOOK0001")
    render_async(view)

    render_hook(view, "reader_ready", %{})
    render_hook(view, "selection", %{"text" => "x"})
    send(view.pid, :something_else)
    assert has_element?(view, "#reader-PDF00001")
  end

  test "an emptied selection takes the offer away", %{conn: conn} do
    library(self())
    {:ok, view, _html} = live(log_in_admin(conn), "/admin/zotero/BOOK0001")
    render_async(view)

    reader = element(view, "#reader-PDF00001")

    render_hook(reader, "selection", %{
      "text" => "x",
      "position" => %{},
      "sort_index" => "",
      "page_label" => ""
    })

    refute has_element?(view, "#annotate-form button[disabled]", "Highlight")
    render_hook(reader, "selection", %{"text" => ""})
    assert has_element?(view, "#annotate-form button[disabled]", "Highlight")
  end

  test "a comment, a jump, a delete and a note each go to Zotero", %{conn: conn} do
    library(self())
    {:ok, view, _html} = live(log_in_admin(conn), "/admin/zotero/BOOK0001")
    render_async(view)

    view |> form("#ann-ANN00001 form", comment: "Open on this.") |> render_submit()
    render_async(view)
    assert_received {:write, "PATCH", "/users/12345/items/ANN00001", patch}
    assert Jason.decode!(patch) == %{"annotationComment" => "Open on this."}

    view |> element("#ann-ANN00001 button", "Show") |> render_click()
    assert_push_event(view, "reader:jump", %{key: "ANN00001"})

    view |> element("#ann-ANN00001 button", "Delete") |> render_click()
    render_async(view)
    assert_received {:write, "DELETE", "/users/12345/items/ANN00001", _}

    view |> form("#note-form", note: %{text: "Pull this into Section I."}) |> render_submit()
    render_async(view)
    assert_received {:write, "POST", "/users/12345/items", note}
    assert [%{"itemType" => "note", "parentItem" => "BOOK0001"}] = Jason.decode!(note)
    assert has_element?(view, "#flash-info", "Note saved to Zotero.")
    refute has_element?(view, "#note-form textarea", "Pull this into Section I.")
  end

  test "the file is served to the admin, whole or by the range asked for", %{conn: conn} do
    library(self())
    conn = log_in_admin(conn)

    whole = get(conn, "/admin/zotero/file/PDF00001/#{@md5}")
    assert whole.status == 200
    assert whole.resp_body == "%PDF-1.7 0123456789"
    assert get_resp_header(whole, "content-type") == ["application/pdf"]
    assert get_resp_header(whole, "accept-ranges") == ["bytes"]
    assert get_resp_header(whole, "cache-control") == ["private, no-store"]
    assert_received :file_fetched

    part =
      conn |> put_req_header("range", "bytes=0-7") |> get("/admin/zotero/file/PDF00001/#{@md5}")

    assert part.status == 206
    assert part.resp_body == "%PDF-1.7"
    assert get_resp_header(part, "content-range") == ["bytes 0-7/19"]
    # The second asking is answered from the cache.
    refute_received :file_fetched

    tail =
      conn |> put_req_header("range", "bytes=-4") |> get("/admin/zotero/file/PDF00001/#{@md5}")

    assert tail.resp_body == "6789"

    out =
      conn |> put_req_header("range", "bytes=50-60") |> get("/admin/zotero/file/PDF00001/#{@md5}")

    assert out.status == 416

    assert get(conn, "/admin/zotero/file/PDF00001/not-an-md5").status == 404
  end
end
