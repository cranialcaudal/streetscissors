defmodule WebWeb.AdminLive.BlogEditorTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Web.Blog

  defp admin_conn(conn), do: init_test_session(conn, %{"admin_user" => "true"})

  # A whole throwaway vault, since a forced save writes to the .trash beside
  # the blog folder.
  setup do
    vault = Path.join(System.tmp_dir!(), "vault-editor-#{System.unique_integer([:positive])}")
    blog = Path.join(vault, "blog")
    File.mkdir_p!(blog)
    original = Application.get_env(:web, :blog_path)
    Application.put_env(:web, :blog_path, blog)

    path = Path.join(blog, "essay.md")

    File.write!(path, """
    ---
    title: "An Essay"
    description: "What it is about."
    date: 2030-03-02
    keywords: film, ferry
    draft: true
    ---

    The first paragraph, as it was opened.
    """)

    on_exit(fn ->
      File.rm_rf!(vault)
      Application.put_env(:web, :blog_path, original)
    end)

    {:ok, vault: vault, path: path}
  end

  test "anonymous visitors are redirected away", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn, "/admin/blog/essay/edit")
  end

  test "a post that is not there sends you back to the blog", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/admin/blog"}}} =
             live(admin_conn(conn), "/admin/blog/no-such-post/edit")
  end

  test "opens the whole file, with the page it makes beside it", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/blog/essay/edit")

    # The field the form posts, and the editor over it (WebWeb.DocumentEditor).
    assert has_element?(view, "#post-source[phx-hook=DocumentEditor][data-complete=blog]")
    source = view |> element("#post-source-input") |> render()
    assert source =~ "title: &quot;An Essay&quot;"
    assert source =~ "draft: true"

    assert has_element?(view, ".adm-title", "An Essay")

    assert has_element?(
             view,
             "#post-preview .adm-prose p",
             "The first paragraph, as it was opened."
           )

    assert has_element?(view, "#post-preview .adm-pill--draft", "draft")
    assert has_element?(view, "#post-preview .adm-chip", "ferry")
    assert has_element?(view, "#post-preview", "What it is about.")
  end

  test "the preview follows the text as it is typed, frontmatter included", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/blog/essay/edit")

    view
    |> form("#post-editor", content: "---\ntitle: Retitled\n---\n\nA **new** opening.\n")
    |> render_change()

    assert has_element?(view, ".adm-title", "Retitled")
    assert has_element?(view, "#post-preview .adm-prose strong", "new")
    assert has_element?(view, "#post-preview .adm-pill--live", "published")
    # Nothing in the frontmatter now: the preview says what is missing.
    assert has_element?(view, "#post-preview .adm-pill--held", "none")
    assert has_element?(view, "#post-editor[data-dirty=true]")
  end

  test "saving writes the file back", %{conn: conn, path: path} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/blog/essay/edit")

    view
    |> form("#post-editor", content: "---\ntitle: Saved\ndraft: true\n---\n\nSaved body.\n")
    |> render_submit()

    assert File.read!(path) == "---\ntitle: Saved\ndraft: true\n---\n\nSaved body.\n"
    assert has_element?(view, "#flash-info", "Saved essay.md.")
    assert has_element?(view, "#post-editor[data-dirty=false]")
  end

  test "save and publish takes the draft line out as it saves", %{conn: conn, path: path} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/blog/essay/edit")
    assert {:error, :not_found} = Blog.get_post("essay")

    view
    |> form("#post-editor", content: File.read!(path))
    |> render_submit(%{"then" => "publish"})

    refute File.read!(path) =~ "draft"
    assert {:ok, %{title: "An Essay", keywords: ["film", "ferry"]}} = Blog.get_post("essay")
    # The editor is shown the text as saved, without its draft line.
    assert_push_event(view, "editor:set", %{id: "post-source", content: saved})
    assert saved == File.read!(path)
    assert has_element?(view, "#post-preview .adm-pill--live", "published")
  end

  test "[[ in the editor offers the blog's pieces", %{conn: conn} do
    {:ok, view, _html} = live(admin_conn(conn), "/admin/blog/essay/edit")

    render_hook(view, "editor_complete", %{"q" => "essay", "kind" => "link", "scope" => "blog"})
    assert_reply(view, %{items: [%{insert: "[An Essay](/blog/essay)", detail: "draft"} | _]})
  end

  test "a file saved with \\r\\n is saved unchanged when nothing was typed",
       %{conn: conn, path: path} do
    crlf = "---\r\ntitle: Windows\r\n---\r\n\r\n![[roll012/3]] \r\nBody.\r\n"
    File.write!(path, crlf)
    {:ok, view, _html} = live(admin_conn(conn), "/admin/blog/essay/edit")

    # What a browser sends back: the same text with \n.
    sent = String.replace(crlf, "\r\n", "\n")
    view |> form("#post-editor", content: sent) |> render_change()
    assert has_element?(view, "#post-editor[data-dirty=false]")

    view |> form("#post-editor", content: sent) |> render_submit()
    assert File.read!(path) == crlf
  end

  describe "when the file changed on disk while the page was open" do
    setup %{conn: conn, path: path} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/blog/essay/edit")
      File.write!(path, "Edited in Obsidian.\n")

      view |> form("#post-editor", content: "Edited in the admin.\n") |> render_submit()
      {:ok, view: view}
    end

    test "the save is refused and both versions are put on the table", %{view: view, path: path} do
      assert File.read!(path) == "Edited in Obsidian.\n"

      assert has_element?(view, "#post-conflict", "changed on disk while you had it open")
      assert has_element?(view, "#post-conflict pre", "Edited in Obsidian.")
      # The author's own text is still in the editor: nothing replaced it.
      refute_push_event(view, "editor:set", %{id: "post-source"})
    end

    test "taking the disk version replaces the editor's text", %{view: view, path: path} do
      view |> element("#post-conflict button", "Take the version on disk") |> render_click()

      refute has_element?(view, "#post-conflict")

      assert_push_event(view, "editor:set", %{id: "post-source", content: "Edited in Obsidian.\n"})

      assert File.read!(path) == "Edited in Obsidian.\n"
      assert has_element?(view, "#post-editor[data-dirty=false]")
    end

    test "saving over it keeps the replaced version in the vault's trash",
         %{view: view, path: path, vault: vault} do
      view |> element("#post-conflict button", "Save mine over it") |> render_click()

      refute has_element?(view, "#post-conflict")
      assert File.read!(path) == "Edited in the admin.\n"

      assert [kept] = File.ls!(Path.join(vault, ".trash"))
      assert File.read!(Path.join([vault, ".trash", kept])) == "Edited in Obsidian.\n"
    end

    test "after either choice the next save goes through", %{view: view, path: path} do
      view |> element("#post-conflict button", "Take the version on disk") |> render_click()
      view |> form("#post-editor", content: "Third version.\n") |> render_submit()

      assert File.read!(path) == "Third version.\n"
      refute has_element?(view, "#post-conflict")
    end
  end

  describe "outline -> draft -> preview pipeline" do
    test "strips beats from the preview, tracks section and beat progress, and toggles beat cards",
         %{conn: conn, path: path} do
      File.write!(path, """
      ---
      title: "Harbor Essay"
      description: "An essay from an outline."
      date: 2030-03-02
      keywords: ferry
      target_words: 500
      draft: true
      ---

      ## Research Checklist

      - [ ] Harbor master's logbook.
      - [x] Tide tables for March.
      > [!thought]
      > My note on the tide tables: high water never waits for the 6:15 commuter bell.

      ## I. Opening (~200 words)

      > [!beat] The Morning Slip
      > Open on the fog horn before sunrise.

      > [!beat] The Commuters
      > Show the line at the turnstile.

      > [!thought]
      > Fifty wool coats steamed in the turnstile queue while the deckhands coiled wet hemp.
      """)

      {:ok, view, _html} = live(admin_conn(conn), "/admin/blog/essay/edit")

      # Outline progress strip shows beats, sources, and reading notes, while the preview prose is empty
      assert has_element?(view, "#post-outline-progress", "0/2")
      assert has_element?(view, "#post-outline-progress", "1/2")
      assert has_element?(view, "#post-outline-progress", "1 notes")
      assert has_element?(view, "#post-zotero", "high water never waits")
      assert has_element?(view, "#post-outline-progress", "I. Opening")
      assert has_element?(view, "#post-preview", "/ 500")
      refute has_element?(view, "#post-preview .adm-prose", "Open on the fog horn")
      refute has_element?(view, "#post-preview .adm-prose", "Harbor master")

      # Toggle "Show beats" to inspect unwritten beat cards and paired thoughts inside the preview
      view |> element("#toggle-beats") |> render_click()

      assert has_element?(
               view,
               "#post-preview .adm-prose aside.adm-beat-card",
               "The Morning Slip"
             )

      assert has_element?(
               view,
               "#post-preview .adm-prose aside.adm-beat-card",
               "Open on the fog horn"
             )

      assert has_element?(
               view,
               "#post-preview .adm-prose .adm-beat-thoughts",
               "Fifty wool coats steamed"
             )

      # Toggle back to prose-only and click "Use my phrasings" on The Commuters beat
      view |> element("#toggle-beats") |> render_click()
      refute has_element?(view, "#post-preview .adm-prose aside.adm-beat-card")

      view
      |> element(~s(button[phx-click=seed_beat][phx-value-beat="The Commuters"]))
      |> render_click()

      assert has_element?(view, "#post-outline-progress", "1/2")
      assert has_element?(view, "#post-outline-progress", "✓ The Commuters")

      assert has_element?(
               view,
               "#post-preview .adm-prose p",
               "Fifty wool coats steamed in the turnstile queue while the deckhands coiled wet hemp."
             )

      drafted = """
      ---
      title: "Harbor Essay"
      description: "An essay from an outline."
      date: 2030-03-02
      keywords: ferry
      target_words: 500
      draft: true
      ---

      ## I. Opening (~200 words)

      > [!beat] The Morning Slip
      > Open on the fog horn before sunrise.

      The fog horn sounded twice before the gates lifted.

      > [!beat] The Commuters
      > Show the line at the turnstile.
      """

      view |> form("#post-editor", content: drafted) |> render_change()

      assert has_element?(view, "#post-outline-progress", "1/2")
      assert has_element?(view, "#post-outline-progress", "✓ The Morning Slip")
      assert has_element?(view, "#post-preview .adm-prose h2", "I. Opening")
      refute has_element?(view, "#post-preview .adm-prose h2", "(~200 words)")

      assert has_element?(
               view,
               "#post-preview .adm-prose p",
               "The fog horn sounded twice before the gates lifted."
             )
    end

    test "imports a Zotero item and its PDF annotations into the top reading list", %{
      conn: conn,
      path: path
    } do
      prev = Application.get_env(:web, :zotero, [])

      on_exit(fn ->
        Application.put_env(:web, :zotero, prev)
      end)

      Application.put_env(:web, :zotero,
        user_id: "99999",
        api_key: "secret-key"
      )

      Req.Test.stub(Web.Writing.Zotero, fn http ->
        case {http.method, http.request_path} do
          {"GET", "/users/99999/collections"} ->
            Req.Test.json(http, [
              %{
                "key" => "COL1",
                "data" => %{"name" => "Harbor Ledger"},
                "meta" => %{"numItems" => 1}
              }
            ])

          {"GET", "/users/99999/items/top"} ->
            Req.Test.json(http, [
              %{
                "key" => "ZITEM1",
                "meta" => %{"numChildren" => 1},
                "data" => %{
                  "key" => "ZITEM1",
                  "itemType" => "book",
                  "title" => "Tide Tables of the Sound",
                  "creators" => [
                    %{"creatorType" => "author", "firstName" => "Clara", "lastName" => "Vance"}
                  ],
                  "date" => "2021",
                  "url" => "https://example.org/tide-tables"
                }
              }
            ])

          {"GET", "/users/99999/items/ZITEM1"} ->
            Req.Test.json(http, %{
              "key" => "ZITEM1",
              "meta" => %{"numChildren" => 1},
              "data" => %{
                "key" => "ZITEM1",
                "itemType" => "book",
                "title" => "Tide Tables of the Sound",
                "creators" => [
                  %{"creatorType" => "author", "firstName" => "Clara", "lastName" => "Vance"}
                ],
                "date" => "2021",
                "url" => "https://example.org/tide-tables"
              }
            })

          {"GET", "/users/99999/items/ZITEM1/children"} ->
            Req.Test.json(http, [
              %{
                "key" => "PDF1",
                "meta" => %{"numChildren" => 1},
                "data" => %{
                  "key" => "PDF1",
                  "itemType" => "attachment",
                  "contentType" => "application/pdf"
                }
              }
            ])

          {"GET", "/users/99999/items/PDF1/children"} ->
            Req.Test.json(http, [
              %{
                "key" => "ANN1",
                "data" => %{
                  "key" => "ANN1",
                  "itemType" => "annotation",
                  "annotationText" => "Slack water holds for eleven minutes at the narrows.",
                  "annotationComment" => "Anchor the opening scene on those eleven minutes.",
                  "annotationPageLabel" => "19"
                }
              }
            ])
        end
      end)

      File.write!(path, """
      ---
      title: "Harbor Essay"
      description: "An essay with Zotero."
      date: 2030-03-03
      keywords: ferry
      target_words: 200
      draft: true
      ---

      ## I. Opening (~200 words)

      > [!beat] The Morning Slip
      > Open on the fog horn before sunrise.
      """)

      {:ok, view, _html} = live(admin_conn(conn), "/admin/blog/essay/edit")

      assert has_element?(view, "#toggle-zotero")
      view |> element("#toggle-zotero") |> render_click()

      assert has_element?(view, "#post-zotero", "Harbor Ledger (1)")
      assert has_element?(view, "#zotero-item-ZITEM1", "Tide Tables of the Sound")

      # It has a child (its PDF), so it can be read, and the reader comes back here.
      assert has_element?(
               view,
               ~s(#zotero-item-ZITEM1 a[href="/admin/zotero/ZITEM1?back=%2Fadmin%2Fblog%2Fessay%2Fedit"]),
               "Read"
             )

      view |> element("#zotero-item-ZITEM1 button", "Add to reading list") |> render_click()

      assert has_element?(
               view,
               "#post-zotero .adm-reading-list",
               "Tide Tables of the Sound"
             )

      assert has_element?(
               view,
               "#post-zotero .adm-reading-thought",
               "Anchor the opening scene on those eleven minutes."
             )
    end
  end

  describe "citations" do
    setup %{path: path} do
      File.write!(path, """
      ---
      title: "Harbor Essay"
      draft: true
      ---

      ## Reading List

      - [x] **Vance, Clara.** *Tide Tables of the Sound* (2021). ^vance2021
      - [ ] **Ortiz, Ana.** *Ferries at Dusk* (2019).

      ## I. Opening

      Slack water holds [@vance2021, p. 19] and [@ghost1999].
      """)

      :ok
    end

    test "the preview renders citations and References; the panel names a key with no source",
         %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/blog/essay/edit")

      assert has_element?(
               view,
               ~s(#post-preview .adm-prose a[href="#ref-vance2021"]),
               "Vance 2021"
             )

      assert has_element?(view, "#post-preview .adm-prose #ref-vance2021", "Tide Tables")
      assert has_element?(view, "#post-citations", "No source for")
      assert has_element?(view, "#post-citations code", "@ghost1999")
      assert has_element?(view, "#reading-0 .adm-cite-key", "@vance2021")
    end

    test "Cite on a source with no key gives it one and types [@key] at the cursor",
         %{conn: conn, path: path} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/blog/essay/edit")

      view |> element("#reading-1 button", "Cite") |> render_click()

      assert_push_event(view, "editor:set", %{id: "post-source", content: keyed})
      assert keyed =~ "*Ferries at Dusk* (2019). ^ortiz2019\n"
      assert_push_event(view, "editor:insert", %{id: "post-source", text: "[@ortiz2019]"})

      # Changed in the editor, not on disk, until it is saved.
      assert has_element?(view, "#post-editor[data-dirty=true]")
      refute File.read!(path) =~ "^ortiz2019"
    end

    test "Give sources a key keys every source without one", %{conn: conn} do
      {:ok, view, _html} = live(admin_conn(conn), "/admin/blog/essay/edit")

      view |> element("#key-reading-items") |> render_click()

      assert has_element?(view, "#reading-1 .adm-cite-key", "@ortiz2019")
      refute has_element?(view, "#key-reading-items")
    end
  end
end
