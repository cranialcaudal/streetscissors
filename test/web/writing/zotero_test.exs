defmodule Web.Writing.ZoteroTest do
  use ExUnit.Case, async: false

  alias Web.Writing.Outline
  alias Web.Writing.Zotero

  setup do
    original = Application.get_env(:web, :zotero)

    Application.put_env(:web, :zotero,
      user_id: "12345",
      api_key: "test-zotero-key",
      collection: "streetscissors"
    )

    on_exit(fn ->
      if original,
        do: Application.put_env(:web, :zotero, original),
        else: Application.delete_env(:web, :zotero)
    end)

    :ok
  end

  test "configured?/0 checks for user_id and api_key" do
    assert Zotero.configured?()

    Application.put_env(:web, :zotero, user_id: nil, api_key: nil)
    refute Zotero.configured?()
  end

  test "list_collections/0 prioritizes streetscissors and its subfolders with full paths" do
    Req.Test.stub(Web.Writing.Zotero, fn conn ->
      assert conn.request_path == "/users/12345/collections"
      assert Plug.Conn.get_req_header(conn, "zotero-api-key") == ["test-zotero-key"]

      Req.Test.json(conn, [
        %{"key" => "COL2", "data" => %{"name" => "Zeta"}, "meta" => %{"numItems" => 4}},
        %{
          "key" => "ROOT1",
          "data" => %{"name" => "streetscissors", "parentCollection" => false},
          "meta" => %{"numItems" => 0, "numCollections" => 1}
        },
        %{
          "key" => "SUB1",
          "data" => %{"name" => "harbor-essay", "parentCollection" => "ROOT1"},
          "meta" => %{"numItems" => 3}
        }
      ])
    end)

    assert {:ok,
            [
              %{
                key: "ROOT1",
                name: "streetscissors",
                path: "streetscissors",
                in_root?: true,
                is_root?: true
              },
              %{
                key: "SUB1",
                name: "harbor-essay",
                path: "streetscissors / harbor-essay",
                in_root?: true,
                is_root?: false
              },
              %{key: "COL2", name: "Zeta", in_root?: false}
            ]} = Zotero.list_collections()
  end

  test "create_collection/2 creates a subfolder inside streetscissors" do
    Req.Test.stub(Web.Writing.Zotero, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/users/12345/collections"} ->
          Req.Test.json(conn, [
            %{
              "key" => "ROOT1",
              "data" => %{"name" => "streetscissors", "parentCollection" => false},
              "meta" => %{"numItems" => 0}
            }
          ])

        {"POST", "/users/12345/collections"} ->
          {:ok, raw, conn} = Plug.Conn.read_body(conn)
          assert [%{"name" => "grid-essay", "parentCollection" => "ROOT1"}] = Jason.decode!(raw)

          Req.Test.json(conn, %{
            "successful" => %{
              "0" => %{
                "key" => "SUB9",
                "data" => %{
                  "key" => "SUB9",
                  "name" => "grid-essay",
                  "parentCollection" => "ROOT1"
                },
                "meta" => %{"numItems" => 0}
              }
            }
          })
      end
    end)

    assert {:ok, %{key: "SUB9", path: "streetscissors / grid-essay", in_root?: true}} =
             Zotero.create_collection("grid-essay", :root)
  end

  test "create_item/2 and sync_reading_list/2 push documents and thoughts into a Zotero folder" do
    Req.Test.stub(Web.Writing.Zotero, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/users/12345/collections/SUB9/items/top"} ->
          Req.Test.json(conn, [])

        {"POST", "/users/12345/items"} ->
          {:ok, raw, conn} = Plug.Conn.read_body(conn)
          [first | _] = Jason.decode!(raw)

          if first["itemType"] == "note" do
            assert first["parentItem"] == "NEWITEM1"
            assert first["note"] =~ "Anchor the opening scene"
            Req.Test.json(conn, %{"successful" => %{"0" => %{"key" => "NEWNOTE1"}}})
          else
            assert first["title"] == "Tide Tables of the Sound"
            assert first["collections"] == ["SUB9"]
            assert first["callNumber"] == "VK798 .V3 2021"

            Req.Test.json(conn, %{
              "successful" => %{
                "0" => %{
                  "key" => "NEWITEM1",
                  "data" => Map.put(first, "key", "NEWITEM1")
                }
              }
            })
          end
      end
    end)

    entries = [
      %{
        done?: false,
        text:
          "**Vance, Clara.** *Tide Tables of the Sound* (Harbor Press, 2021). *Call Number: VK798 .V3 2021*",
        thoughts: ["Anchor the opening scene on those eleven minutes."]
      }
    ]

    assert {:ok, %{created: [created], skipped: 0}} = Zotero.sync_reading_list(entries, "SUB9")
    assert created.key == "NEWITEM1"
    assert created.title == "Tide Tables of the Sound"
    assert created.authors == "Vance, Clara"
    assert created.notes == ["Anchor the opening scene on those eleven minutes."]
  end

  test "fetch_item_with_notes/1 pulls item metadata, child notes, and PDF annotations" do
    Req.Test.stub(Web.Writing.Zotero, fn conn ->
      case conn.request_path do
        "/users/12345/items/ITEM1" ->
          Req.Test.json(conn, %{
            "key" => "ITEM1",
            "meta" => %{"numChildren" => 2},
            "data" => %{
              "itemType" => "book",
              "title" => "The Future of Nostalgia",
              "creators" => [
                %{"creatorType" => "author", "firstName" => "Svetlana", "lastName" => "Boym"}
              ],
              "publisher" => "Basic Books",
              "date" => "2001",
              "callNumber" => "PN56.N6 B69 2001"
            }
          })

        "/users/12345/items/ITEM1/children" ->
          Req.Test.json(conn, [
            %{
              "key" => "NOTE1",
              "data" => %{
                "itemType" => "note",
                "note" =>
                  "<p>Restorative nostalgia rebuilds monuments; reflective nostalgia lingers on ruins.</p>"
              }
            },
            %{
              "key" => "ATT1",
              "meta" => %{"numChildren" => 1},
              "data" => %{"itemType" => "attachment"}
            }
          ])

        "/users/12345/items/ATT1/children" ->
          Req.Test.json(conn, [
            %{
              "key" => "ANN1",
              "data" => %{
                "itemType" => "annotation",
                "annotationText" => "Nostalgia is a rebellion against the modern idea of time",
                "annotationComment" => "Connect this to the comic-book Sovereign.",
                "annotationPageLabel" => "41"
              }
            }
          ])
      end
    end)

    assert {:ok, item} = Zotero.fetch_item_with_notes("ITEM1")
    assert item.title == "The Future of Nostalgia"
    assert item.authors == "Boym, Svetlana"
    assert item.year == "2001"
    assert item.call_number == "PN56.N6 B69 2001"

    assert [
             "Restorative nostalgia rebuilds monuments; reflective nostalgia lingers on ruins.",
             "“Nostalgia is a rebellion against the modern idea of time” (p. 41) — Connect this to the comic-book Sovereign."
           ] = item.notes

    formatted = Zotero.format_reading_item(item)

    assert formatted =~
             "- [x] **Boym, Svetlana.** *The Future of Nostalgia* (Basic Books, 2001). *Call Number: PN56.N6 B69 2001*"

    assert formatted =~ "> [!thought]\n> Restorative nostalgia rebuilds monuments"

    assert formatted =~
             "> “Nostalgia is a rebellion against the modern idea of time” (p. 41) — Connect this to the comic-book Sovereign."

    # Inserting into a post creates or updates the top Reading List and is idempotent
    doc =
      "---\ntitle: Essay\ndraft: true\n---\n\n## I. Opening (~200 words)\n\n> [!beat] Hook\n> Start here.\n"

    updated = Outline.insert_reading_items(doc, [item])
    assert updated =~ "## Reading List\n\n- [x] **Boym, Svetlana.**"
    assert Outline.insert_reading_items(updated, [item]) == updated
  end

  test "a source's own citation key comes through and keys its reading-list line" do
    Req.Test.stub(Web.Writing.Zotero, fn conn ->
      Req.Test.json(conn, [
        %{
          "key" => "KEYED1",
          "data" => %{
            "title" => "Ferries at Dusk",
            "creators" => [
              %{"creatorType" => "author", "lastName" => "Ortiz", "firstName" => "Ana"}
            ],
            "date" => "2019",
            "extra" => "Original date: 2018\nCitation Key: ortiz2019ferries"
          }
        },
        %{"key" => "PLAIN1", "data" => %{"title" => "Fog Signals", "citationKey" => "lund2015"}}
      ])
    end)

    assert {:ok, [keyed, plain]} = Zotero.search_items()
    assert keyed.citation_key == "ortiz2019ferries"
    assert plain.citation_key == "lund2015"

    text = Outline.insert_reading_items("## Reading List\n", [keyed])
    assert text =~ "*Ferries at Dusk* (2019). ^ortiz2019ferries"

    # Pushed back to Zotero, the key is not part of the title.
    [item] = Outline.analyze(text).research.items
    assert Zotero.parse_markdown_reading_item(item.text).title == "Ferries at Dusk"

    assert Zotero.parse_markdown_reading_item("- [ ] *Ferries at Dusk* (2019). ^k").title ==
             "Ferries at Dusk"
  end

  test "a reading-list line's year is its publication's, not one its title holds" do
    parsed =
      Zotero.parse_markdown_reading_item(
        ~s{- [ ] **Katz, Lawrence F. & Krueger, Alan B.** "The Rise of Alternative Work, 1995–2015," *NBER Working Paper* 22667 (2016).}
      )

    assert parsed.year == "2016"

    assert Zotero.parse_markdown_reading_item("*Trends Since 1940* (Harbor Press, 2017).").year ==
             "2017"
  end
end
