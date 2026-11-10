defmodule WebWeb.AdminLive.WritingDeskTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest

  setup do
    tmp = Path.join(System.tmp_dir!(), "writing-desk-#{System.unique_integer([:positive])}")
    dir = Path.join(tmp, "writing")
    File.mkdir_p!(dir)
    original = Application.get_env(:web, :writing_path)
    Application.put_env(:web, :writing_path, dir)

    on_exit(fn ->
      File.rm_rf!(tmp)

      if original,
        do: Application.put_env(:web, :writing_path, original),
        else: Application.delete_env(:web, :writing_path)
    end)

    File.write!(Path.join(dir, "slack-water.md"), """
    ---
    title: "Slack Water"
    author: A. Writer
    ---

    ## Reading List

    - [x] **Vance, Clara.** *Tide Tables* (2021). ^vance2021
    > [!thought]
    > Eleven minutes of still water.

    ## Introduction (~100 words)

    > [!beat] The narrows
    > Open on the water.

    The tide turns [@vance2021, p. 19].
    """)

    {:ok, dir: dir}
  end

  test "anonymous visitors are turned away", %{conn: conn} do
    assert {:error, {:redirect, _}} = live(conn, "/admin/writing")
    assert {:error, {:redirect, _}} = live(conn, "/admin/writing/slack-water")
    conn = get(conn, "/admin/writing/slack-water/export/docx")
    assert conn.status == 404
  end

  test "lists the papers and starts a new one from a skeleton", %{conn: conn, dir: dir} do
    {:ok, view, _html} = live(log_in_admin(conn), "/admin/writing")

    assert has_element?(view, "#paper-slack-water", "Slack Water")

    view
    |> form("#new-paper-form", paper: %{title: "Fog Study", kind: "review"})
    |> render_submit()

    assert_redirect(view, "/admin/writing/fog-study")
    assert File.read!(Path.join(dir, "fog-study.md")) =~ "## Synthesis and gaps"
  end

  test "a paper opens in the workbench, never with a publish button", %{conn: conn} do
    {:ok, view, _html} = live(log_in_admin(conn), "/admin/writing/slack-water")

    assert has_element?(view, ".adm-title", "Slack Water")
    assert has_element?(view, "#post-source[phx-hook=DocumentEditor]")
    refute has_element?(view, "button[value=publish]")
    assert has_element?(view, ~s(#post-preview a[href="#ref-vance2021"]), "Vance 2021")
    assert has_element?(view, "#post-outline-progress .adm-outline-says", "The tide turns")
    assert has_element?(view, "#post-outline-progress .adm-cite-key", "@vance2021")
    assert has_element?(view, "#reading-0 .adm-reading-used", "The narrows")
    # Read aloud at 150 words a minute: the goal of 100 words is a minute.
    assert has_element?(view, "#post-aloud", "1 at the goal")
  end

  test "a thought on a source is carried to a beat, cited", %{conn: conn} do
    {:ok, view, _html} = live(log_in_admin(conn), "/admin/writing/slack-water")

    view
    |> form("#to-beat-0-0", %{"beat" => "The narrows"})
    |> render_submit()

    assert_push_event(view, "editor:set", %{id: "post-source", content: text})

    assert text =~
             "> [!beat] The narrows\n> Open on the water.\n\n> [!thought]\n> Eleven minutes of still water. [@vance2021]"
  end

  test "a missing paper sends you back to the list", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/admin/writing"}}} =
             live(log_in_admin(conn), "/admin/writing/nope")
  end

  @tag :pandoc
  test "exports the saved paper as Word, to the admin", %{conn: conn} do
    conn = get(log_in_admin(conn), "/admin/writing/slack-water/export/docx")

    assert conn.status == 200

    assert ["attachment; filename=\"slack-water.docx\"" <> _] =
             get_resp_header(conn, "content-disposition")

    assert <<"PK", _::binary>> = conn.resp_body
  end

  test "an unknown format is a 404", %{conn: conn} do
    assert get(log_in_admin(conn), "/admin/writing/slack-water/export/rtf").status == 404
  end
end
