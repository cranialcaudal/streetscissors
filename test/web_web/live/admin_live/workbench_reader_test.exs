defmodule WebWeb.AdminLive.WorkbenchReaderTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  setup do
    vault = Path.join(System.tmp_dir!(), "vault-reading-#{System.unique_integer([:positive])}")
    blog = Path.join(vault, "blog")
    File.mkdir_p!(blog)
    original_blog = Application.get_env(:web, :blog_path)
    original_zotero = Application.get_env(:web, :zotero)
    original_cache = Application.get_env(:web, :zotero_cache_path)
    Application.put_env(:web, :blog_path, blog)
    Application.put_env(:web, :zotero, user_id: "12345", api_key: "test-key")
    Application.put_env(:web, :zotero_cache_path, Path.join(vault, "cache"))

    File.write!(Path.join(blog, "essay.md"), """
    ---
    title: "Harbor Essay"
    draft: true
    ---

    ## I. Opening (~200 words)

    The tide comes in.
    """)

    on_exit(fn ->
      File.rm_rf!(vault)
      Application.put_env(:web, :blog_path, original_blog)
      Application.put_env(:web, :zotero, original_zotero)

      if original_cache,
        do: Application.put_env(:web, :zotero_cache_path, original_cache),
        else: Application.delete_env(:web, :zotero_cache_path)
    end)

    :ok
  end

  # A record with no file, as a reading list often has.
  @record %{
    "key" => "LIST0001",
    "meta" => %{"numChildren" => 0},
    "data" => %{"key" => "LIST0001", "itemType" => "book", "title" => "Ferries at Dusk"}
  }

  @book %{
    "key" => "BOOK0001",
    "meta" => %{"numChildren" => 1},
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
      "key" => "PDF00001",
      "itemType" => "attachment",
      "parentItem" => "BOOK0001",
      "linkMode" => "imported_file",
      "contentType" => "application/pdf",
      "title" => "Full Text PDF",
      "md5" => "0123456789abcdef0123456789abcdef"
    }
  }

  # A PDF dropped into Zotero on its own, with no item around it.
  @standalone %{
    "key" => "LOOSE001",
    "data" => %{
      "key" => "LOOSE001",
      "itemType" => "attachment",
      "linkMode" => "imported_file",
      "contentType" => "application/pdf",
      "title" => "harbor-notes.pdf",
      "filename" => "harbor-notes.pdf"
    }
  }

  # A link to a file on some other machine: nothing here can read it.
  @linked %{
    "key" => "LINK0001",
    "data" => %{
      "itemType" => "attachment",
      "linkMode" => "linked_file",
      "contentType" => "application/pdf",
      "title" => "Elsewhere"
    }
  }

  @highlight %{
    "key" => "ANN00001",
    "version" => 7,
    "data" => %{
      "itemType" => "annotation",
      "annotationType" => "highlight",
      "annotationText" => "Slack water holds for eleven minutes.",
      "annotationComment" => "",
      "annotationColor" => "#ffd400",
      "annotationPageLabel" => "19",
      "annotationSortIndex" => "00018|000120|00300",
      "annotationPosition" => ~s({"pageIndex":18,"rects":[[1,2,3,4]]})
    }
  }

  # The site's folder, a folder inside it, and a folder of other work.
  @folders [
    %{"key" => "ROOT0001", "data" => %{"name" => "streetscissors"}, "meta" => %{"numItems" => 1}},
    %{
      "key" => "SUB00001",
      "data" => %{"name" => "harbor-essay", "parentCollection" => "ROOT0001"},
      "meta" => %{"numItems" => 1}
    },
    %{"key" => "WORK0001", "data" => %{"name" => "Coursework"}, "meta" => %{"numItems" => 9}}
  ]

  # The stub has no answer for the other folder, or the library as a whole.
  defp library do
    Req.Test.stub(Web.Writing.Zotero, fn conn ->
      q = conn.query_params

      case {conn.request_path, q["itemType"], q["itemKey"]} do
        {"/users/12345/collections", _, _} ->
          Req.Test.json(conn, @folders)

        {"/users/12345/collections/ROOT0001/items/top", _, _} ->
          Req.Test.json(conn, [@record])

        {"/users/12345/collections/ROOT0001/items", "attachment", _} ->
          Req.Test.json(conn, [@standalone, @linked])

        {"/users/12345/collections/SUB00001/items", "attachment", _} ->
          Req.Test.json(conn, [@pdf])

        {"/users/12345/items", _, "BOOK0001"} ->
          Req.Test.json(conn, [@book])

        {"/users/12345/items/BOOK0001", _, _} ->
          Req.Test.json(conn, @book)

        {"/users/12345/items/PDF00001", _, _} ->
          Req.Test.json(conn, @pdf)

        {"/users/12345/items/BOOK0001/children", "note", _} ->
          Req.Test.json(conn, [])

        {"/users/12345/items/BOOK0001/children", _, _} ->
          Req.Test.json(conn, [@pdf])

        {"/users/12345/items/PDF00001/children", _, _} ->
          Req.Test.json(conn, [@highlight])
      end
    end)
  end

  test "a file in the site's Zotero folders is read in the first panel and quoted into the draft",
       %{conn: conn} do
    library()
    {:ok, view, _html} = live(admin_conn(conn), "/admin/blog/essay/edit")

    # The folder's record has no file, and the panel says where the files are.
    assert has_element?(view, "#zotero-item-LIST0001", "Ferries at Dusk")
    refute has_element?(view, "#zotero-item-LIST0001 button", "Read")
    assert has_element?(view, "#zotero-no-files", "PDFs & EPUBs")

    # Every PDF in streetscissors and the folders inside it: under its
    # item's title, or alone by its name.
    view |> element("#zotero-files") |> render_click()
    assert has_element?(view, "#zotero-files[aria-pressed=true]")
    assert has_element?(view, "#zotero-item-PDF00001", "Tide Tables of the Sound")
    assert has_element?(view, "#zotero-item-LOOSE001", "harbor-notes.pdf")
    assert has_element?(view, "#zotero-item-LOOSE001", "on its own")
    refute has_element?(view, "#zotero-item-LINK0001")

    # Read opens it beside the draft; the outline and the preview fold away.
    view |> element("#zotero-item-PDF00001 button", "Read") |> render_click()
    render_async(view)

    assert has_element?(view, "#post-zotero[data-reading=true]")
    assert has_element?(view, "#post-outline-progress[data-collapsed=true]")
    assert has_element?(view, "#post-preview[data-collapsed=true]")
    assert has_element?(view, "#panel-draft[data-collapsed=false]")
    assert has_element?(view, "#post-zotero .adm-reader-head", "Tide Tables of the Sound")
    assert has_element?(view, "#reader-PDF00001[phx-hook=ZoteroReader]")
    assert has_element?(view, "#ann-ANN00001", "Slack water holds")

    assert has_element?(
             view,
             ~s(#reader-full-page[href="/admin/zotero/PDF00001?back=%2Fadmin%2Fblog%2Fessay%2Fedit"])
           )

    # A selection quoted at the draft's cursor, cited with its page; the
    # source goes into the reading list on the way.
    view
    |> element("#reader-PDF00001")
    |> render_hook("selection", %{
      "text" => "The ferries  wait.",
      "position" => %{"pageIndex" => 2, "rects" => [[10, 20, 30, 40]]},
      "sort_index" => "00002|000050|00100",
      "page_label" => "3"
    })

    view |> element("#reader-quote-selection") |> render_click()

    assert_push_event(view, "editor:insert", %{id: "post-source", text: quoted})
    assert [_, key] = Regex.run(~r/^“The ferries wait\.” \[@([\w-]+), p\. 3\]$/u, quoted)

    # An annotation already made is quoted the same way.
    view |> element("#ann-ANN00001 button", "Quote") |> render_click()

    assert_push_event(view, "editor:insert", %{
      text: "“Slack water holds for eleven minutes.” [@" <> _
    })

    # Closing brings the panels back as they were.
    view |> element("#reader-close") |> render_click()
    assert has_element?(view, "#post-zotero[data-reading=false]")
    assert has_element?(view, "#post-outline-progress[data-collapsed=false]")
    assert has_element?(view, "#post-preview[data-collapsed=false]")
    assert has_element?(view, "#post-zotero .adm-reading-list", "Tide Tables of the Sound")
    assert has_element?(view, "#post-zotero .adm-reading-list", key)
  end

  test "a file on its own can be read and marked, but not quoted: nothing to cite",
       %{conn: conn} do
    Req.Test.stub(Web.Writing.Zotero, fn conn ->
      case conn.request_path do
        "/users/12345/collections" -> Req.Test.json(conn, Enum.take(@folders, 1))
        "/users/12345/collections/ROOT0001/items/top" -> Req.Test.json(conn, [@standalone])
        "/users/12345/items/LOOSE001" -> Req.Test.json(conn, @standalone)
        "/users/12345/items/LOOSE001/children" -> Req.Test.json(conn, [])
      end
    end)

    {:ok, view, _html} = live(admin_conn(conn), "/admin/blog/essay/edit")
    view |> element("#zotero-item-LOOSE001 button", "Read") |> render_click()
    render_async(view)

    assert has_element?(view, "#reader-LOOSE001")
    assert has_element?(view, "#reader-standalone", "drag it onto its item")
    refute has_element?(view, "#note-form")

    view
    |> element("#reader-LOOSE001")
    |> render_hook("selection", %{
      "text" => "Loose words.",
      "position" => %{"pageIndex" => 0, "rects" => [[1, 2, 3, 4]]},
      "sort_index" => "00000|000000|00000",
      "page_label" => "1"
    })

    refute has_element?(view, "#annotate-form button[disabled]", "Highlight")
    assert has_element?(view, "#reader-quote-selection[disabled]")
  end
end
