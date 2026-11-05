defmodule Web.Writing.Zotero.ReaderTest do
  use ExUnit.Case, async: false

  alias Web.Writing.Zotero.Reader

  @md5 "0123456789abcdef0123456789abcdef"

  setup do
    original = Application.get_env(:web, :zotero)
    original_cache = Application.get_env(:web, :zotero_cache_path)
    cache = Path.join(System.tmp_dir!(), "zotero-cache-#{System.unique_integer([:positive])}")
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

  defp attachment(key, attrs) do
    %{
      "key" => key,
      "version" => 3,
      "data" =>
        Map.merge(
          %{
            "key" => key,
            "itemType" => "attachment",
            "linkMode" => "imported_file",
            "contentType" => "application/pdf",
            "title" => "PDF",
            "filename" => "tides.pdf",
            "md5" => @md5
          },
          attrs
        )
    }
  end

  @book %{
    "key" => "BOOK0001",
    "data" => %{
      "key" => "BOOK0001",
      "itemType" => "book",
      "title" => "Tide Tables of the Sound",
      "creators" => [%{"creatorType" => "author", "lastName" => "Vance", "firstName" => "Clara"}],
      "date" => "2021"
    },
    "meta" => %{"numChildren" => 3}
  }

  defp body(conn) do
    {:ok, body, _} = Plug.Conn.read_body(conn)
    Jason.decode!(body)
  end

  describe "document/1" do
    test "an item's PDFs and EPUBs stored in Zotero; a linked file is left out" do
      Req.Test.stub(Web.Writing.Zotero, fn conn ->
        case conn.request_path do
          "/users/12345/items/BOOK0001" ->
            Req.Test.json(conn, @book)

          "/users/12345/items/BOOK0001/children" ->
            assert conn.query_params["itemType"] == "attachment"

            conn
            |> Plug.Conn.put_resp_header("total-results", "3")
            |> Req.Test.json([
              attachment("PDF00001", %{"parentItem" => "BOOK0001"}),
              attachment("LINKED01", %{"parentItem" => "BOOK0001", "linkMode" => "linked_file"}),
              attachment("EPUB0001", %{
                "parentItem" => "BOOK0001",
                "contentType" => "application/epub+zip",
                "title" => "EPUB"
              })
            ])
        end
      end)

      assert {:ok, %{item: item, attachments: [pdf, epub], notes_key: "BOOK0001"}} =
               Reader.document("BOOK0001")

      assert item.title == "Tide Tables of the Sound"
      assert %{key: "PDF00001", kind: :pdf, md5: @md5, parent_key: "BOOK0001"} = pdf
      assert %{key: "EPUB0001", kind: :epub} = epub
    end

    test "an attachment's key opens its parent, with that attachment first" do
      Req.Test.stub(Web.Writing.Zotero, fn conn ->
        case conn.request_path do
          "/users/12345/items/EPUB0001" ->
            Req.Test.json(
              conn,
              attachment("EPUB0001", %{
                "parentItem" => "BOOK0001",
                "contentType" => "application/epub+zip"
              })
            )

          "/users/12345/items/BOOK0001" ->
            Req.Test.json(conn, @book)

          "/users/12345/items/BOOK0001/children" ->
            Req.Test.json(conn, [
              attachment("PDF00001", %{"parentItem" => "BOOK0001"}),
              attachment("EPUB0001", %{
                "parentItem" => "BOOK0001",
                "contentType" => "application/epub+zip"
              })
            ])
        end
      end)

      assert {:ok, %{attachments: [%{key: "EPUB0001"}, %{key: "PDF00001"}]}} =
               Reader.document("EPUB0001")
    end

    test "a standalone file is its own document, with nowhere to put notes" do
      Req.Test.stub(Web.Writing.Zotero, fn conn ->
        Req.Test.json(
          conn,
          attachment("LONE0001", %{"title" => "fields-2019-automated-landlord"})
        )
      end)

      assert {:ok, %{item: item, attachments: [%{key: "LONE0001"}], notes_key: nil}} =
               Reader.document("LONE0001")

      assert item.title == "fields-2019-automated-landlord"
    end

    test "a key that is not a Zotero key asks nothing" do
      Req.Test.stub(Web.Writing.Zotero, fn _conn -> flunk("no request for a bad key") end)
      assert Reader.document("../etc") == {:error, :not_found}
    end
  end

  describe "annotations" do
    test "are read in reading order, every page of them, with their colours named" do
      Req.Test.stub(Web.Writing.Zotero, fn conn ->
        assert conn.request_path == "/users/12345/items/PDF00001/children"
        assert conn.query_params["itemType"] == "annotation"

        page =
          case conn.query_params["start"] do
            "0" ->
              [
                %{
                  "key" => "ANNB0001",
                  "version" => 7,
                  "data" => %{
                    "annotationType" => "highlight",
                    "annotationText" => "Slack water holds.",
                    "annotationComment" => "",
                    "annotationColor" => "#5FB236",
                    "annotationPageLabel" => "19",
                    "annotationSortIndex" => "00018|000120|00300",
                    "annotationPosition" => ~s({"pageIndex":18,"rects":[[1,2,3,4]]})
                  }
                }
              ]

            "1" ->
              [
                %{
                  "key" => "ANNA0001",
                  "version" => 8,
                  "data" => %{
                    "annotationType" => "underline",
                    "annotationText" => "The narrows.",
                    "annotationColor" => "#123456",
                    "annotationSortIndex" => "00002|000010|00100",
                    "annotationPosition" => "not json"
                  }
                }
              ]
          end

        conn |> Plug.Conn.put_resp_header("total-results", "2") |> Req.Test.json(page)
      end)

      assert {:ok, [first, second]} = Reader.annotations("PDF00001")
      assert %{key: "ANNA0001", type: "underline", color_name: "other", position: %{}} = first

      assert %{
               key: "ANNB0001",
               version: 7,
               color_name: "green",
               page_label: "19",
               position: %{"pageIndex" => 18, "rects" => [[1, 2, 3, 4]]}
             } = second
    end

    test "a highlight from a PDF selection is written as Zotero writes one" do
      test = self()

      Req.Test.stub(Web.Writing.Zotero, fn conn ->
        assert conn.method == "POST"
        assert conn.request_path == "/users/12345/items"
        [payload] = body(conn)
        send(test, {:payload, payload})

        Req.Test.json(conn, %{
          "successful" => %{"0" => %{"key" => "NEWANN01", "version" => 9, "data" => payload}},
          "failed" => %{}
        })
      end)

      selection = %{
        "type" => "highlight",
        "text" => "  Slack water holds\nfor eleven minutes. ",
        "position" => %{"pageIndex" => 18, "rects" => [[61.5, 130.25, 293.6, 139.4]]},
        "sort_index" => "00018|000120|00300",
        "page_label" => "19",
        "color" => "blue",
        "comment" => "The opening scene."
      }

      assert {:ok, %{key: "NEWANN01", color_name: "blue"}} =
               Reader.create_annotation(%{key: "PDF00001", kind: :pdf}, selection)

      assert_received {:payload, payload}

      assert payload == %{
               "itemType" => "annotation",
               "parentItem" => "PDF00001",
               "annotationType" => "highlight",
               "annotationText" => "Slack water holds\nfor eleven minutes.",
               "annotationComment" => "The opening scene.",
               "annotationColor" => "#2ea8e5",
               "annotationPageLabel" => "19",
               "annotationSortIndex" => "00018|000120|00300",
               "annotationPosition" => ~s({"pageIndex":18,"rects":[[61.5,130.25,293.6,139.4]]}),
               "tags" => []
             }
    end

    test "an EPUB highlight carries its CFI, and its own sort index" do
      assert {:ok, payload} =
               Reader.annotation_payload(:epub, %{
                 "text" => "Fog.",
                 "position" => %{
                   "type" => "FragmentSelector",
                   "conformsTo" => "http://www.idpf.org/epub/linking/cfi/epub-cfi.html",
                   "value" => "epubcfi(/6/4!/4/2,/1:0,/1:4)"
                 },
                 "sort_index" => "00002|00000123"
               })

      assert payload["annotationPosition"] =~ "epubcfi(/6/4!/4/2,/1:0,/1:4)"
      assert payload["annotationColor"] == "#ffd400"
    end

    test "a selection that cannot be placed is refused before anything is sent" do
      Req.Test.stub(Web.Writing.Zotero, fn _conn -> flunk("nothing should be written") end)
      pdf = %{key: "PDF00001", kind: :pdf}
      position = %{"pageIndex" => 0, "rects" => [[1, 2, 3, 4]]}

      assert {:error, :bad_sort_index} =
               Reader.create_annotation(pdf, %{
                 "text" => "x",
                 "position" => position,
                 "sort_index" => "1|2"
               })

      assert {:error, :bad_position} =
               Reader.create_annotation(pdf, %{
                 "text" => "x",
                 "position" => %{"pageIndex" => 0, "rects" => []},
                 "sort_index" => "00000|000000|00000"
               })

      assert {:error, :no_text} =
               Reader.create_annotation(pdf, %{
                 "text" => " ",
                 "position" => position,
                 "sort_index" => "00000|000000|00000"
               })

      # A PDF position is not an EPUB's, nor the other way round.
      assert {:error, :bad_position} =
               Reader.create_annotation(%{key: "EPUB0001", kind: :epub}, %{
                 "text" => "x",
                 "position" => position,
                 "sort_index" => "00000|00000000"
               })
    end

    test "a comment is changed over the version read; a newer one in Zotero is a conflict" do
      test = self()

      Req.Test.stub(Web.Writing.Zotero, fn conn ->
        assert conn.method == "PATCH"

        send(
          test,
          {:patch, Plug.Conn.get_req_header(conn, "if-unmodified-since-version"), body(conn)}
        )

        case Plug.Conn.get_req_header(conn, "if-unmodified-since-version") do
          ["7"] -> Plug.Conn.send_resp(conn, 204, "")
          _ -> Plug.Conn.send_resp(conn, 412, "")
        end
      end)

      assert :ok = Reader.update_annotation("ANNB0001", 7, %{"comment" => " Anchor the scene. "})
      assert_received {:patch, ["7"], %{"annotationComment" => "Anchor the scene."}}
      assert {:error, :conflict} = Reader.update_annotation("ANNB0001", 6, %{"color" => "red"})
      assert_received {:patch, ["6"], %{"annotationColor" => "#ff6666"}}
    end

    test "deleting asks for the version read" do
      Req.Test.stub(Web.Writing.Zotero, fn conn ->
        assert conn.method == "DELETE"
        assert conn.request_path == "/users/12345/items/ANNB0001"
        assert Plug.Conn.get_req_header(conn, "if-unmodified-since-version") == ["7"]
        Plug.Conn.send_resp(conn, 204, "")
      end)

      assert :ok = Reader.delete_annotation("ANNB0001", 7)
    end
  end

  describe "files/2" do
    test "lists the stored PDFs and EPUBs in the folders given, under their items' titles" do
      test = self()

      at = fn key, attrs, modified ->
        attachment(key, Map.put(attrs, "dateModified", modified))
      end

      Req.Test.stub(Web.Writing.Zotero, fn conn ->
        send(test, {:asked, conn.request_path, conn.query_params})

        case conn.request_path do
          "/users/12345/collections/ROOT0001/items" ->
            Req.Test.json(conn, [
              at.("LOOSE001", %{"filename" => "harbor-notes.pdf"}, "2026-10-02T00:00:00Z"),
              at.("PDF00001", %{"parentItem" => "BOOK0001"}, "2026-10-01T00:00:00Z"),
              at.("LINK0001", %{"linkMode" => "linked_file"}, "2026-10-04T00:00:00Z"),
              at.("HTML0001", %{"contentType" => "text/html"}, "2026-10-04T00:00:00Z")
            ])

          # A file under an item in two folders comes back from both.
          "/users/12345/collections/SUB00001/items" ->
            Req.Test.json(conn, [
              at.(
                "EPUB0001",
                %{"parentItem" => "BOOK0001", "contentType" => "application/epub+zip"},
                "2026-10-03T00:00:00Z"
              ),
              at.("PDF00001", %{"parentItem" => "BOOK0001"}, "2026-10-01T00:00:00Z")
            ])

          "/users/12345/items" ->
            Req.Test.json(conn, [@book])
        end
      end)

      assert {:ok, [epub, loose, pdf]} = Reader.files(["ROOT0001", "SUB00001"], "  tides ")

      assert %{
               key: "BOOK0001",
               file_key: "PDF00001",
               kind: :pdf,
               title: "Tide Tables of the Sound",
               year: "2021",
               standalone?: false
             } = pdf

      assert pdf.authors =~ "Vance"
      assert %{key: "BOOK0001", file_key: "EPUB0001", kind: :epub} = epub

      assert %{
               key: "LOOSE001",
               file_key: "LOOSE001",
               title: "harbor-notes.pdf",
               standalone?: true
             } =
               loose

      for folder <- ["ROOT0001", "SUB00001"] do
        path = "/users/12345/collections/#{folder}/items"

        assert_received {:asked, ^path,
                         %{"itemType" => "attachment", "q" => "tides", "qmode" => "everything"}}
      end

      # The parents are asked for once, together; the library as a whole never.
      assert_received {:asked, "/users/12345/items", %{"itemKey" => "BOOK0001"}}
      refute_received {:asked, _, _}
    end

    test "no folders, no files, and nothing asked" do
      Req.Test.stub(Web.Writing.Zotero, fn _conn -> raise "asked Zotero" end)
      assert {:ok, []} = Reader.files([])
    end
  end

  describe "notes" do
    test "a note is written as escaped paragraphs under the item" do
      test = self()

      Req.Test.stub(Web.Writing.Zotero, fn conn ->
        send(test, {:note, body(conn)})
        Req.Test.json(conn, %{"successful" => %{"0" => %{"key" => "NOTE0001"}}})
      end)

      assert :ok = Reader.create_note("BOOK0001", "Slack <b>water</b>.\n\nSecond thought.")

      assert_received {:note,
                       [
                         %{
                           "itemType" => "note",
                           "parentItem" => "BOOK0001",
                           "note" =>
                             "<p>Slack &lt;b&gt;water&lt;/b&gt;.</p><p>Second thought.</p>"
                         }
                       ]}

      assert Reader.create_note("BOOK0001", "  ") == {:error, :blank}
    end

    test "notes read as plain text" do
      Req.Test.stub(Web.Writing.Zotero, fn conn ->
        Req.Test.json(conn, [
          %{
            "key" => "NOTE0001",
            "version" => 2,
            "data" => %{"note" => "<p>Eleven <em>minutes</em>.</p>"}
          }
        ])
      end)

      assert {:ok, [%{key: "NOTE0001", text: "Eleven minutes."}]} = Reader.notes("BOOK0001")
      assert {:ok, []} = Reader.notes(nil)
    end
  end

  describe "files" do
    test "are fetched once into the cache, and an older copy is let go", %{cache: cache} do
      test = self()

      Req.Test.stub(Web.Writing.Zotero, fn conn ->
        assert conn.request_path == "/users/12345/items/PDF00001/file"
        send(test, :fetched)
        Plug.Conn.send_resp(conn, 200, "%PDF-1.7 tide tables")
      end)

      File.mkdir_p!(cache)
      File.write!(Path.join(cache, "PDF00001-ffffffffffffffffffffffffffffffff.pdf"), "old")

      pdf = %{key: "PDF00001", kind: :pdf, md5: @md5}
      assert {:ok, path} = Reader.file(pdf)
      assert File.read!(path) == "%PDF-1.7 tide tables"
      assert_received :fetched
      assert {:ok, ^path} = Reader.file(pdf)
      refute_received :fetched

      assert File.ls!(cache) == ["PDF00001-#{@md5}.pdf"]
      assert Bitwise.band(File.stat!(cache).mode, 0o777) == 0o700
      assert Reader.cached_file("PDF00001", @md5) == {path, :pdf}
      assert Reader.cached_file("PDF00001", "../../x") == nil
    end

    test "an attachment with no file in Zotero says so" do
      Req.Test.stub(Web.Writing.Zotero, fn conn -> Plug.Conn.send_resp(conn, 404, "") end)
      assert {:error, :no_file} = Reader.file(%{key: "PDF00002", kind: :pdf, md5: @md5})
    end
  end
end
