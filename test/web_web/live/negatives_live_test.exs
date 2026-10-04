defmodule WebWeb.NegativesLiveTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Web.NegativesFixtures, as: Fixture

  test "renders minimalist viewer and can toggle to index by scan date", %{conn: conn} do
    {:ok, view, html} = live(conn, "/negatives")

    assert html =~ "Full Index by Scan Date"
    assert has_element?(view, ".single-presentation-viewport")

    # Every control is a link now, so the toggle is a patch and lands in the
    # URL — which is what lets Back undo it.
    view |> element("a.index-toggle-btn") |> render_click()

    assert render(view) =~ "Contact Sheets Index"
    assert has_element?(view, ".minimal-index-table")

    view |> element("a.index-toggle-btn") |> render_click()

    assert has_element?(view, ".single-presentation-viewport")
  end

  # The archive's contents sit beside the sheet when there is room for both;
  # below 1200px CSS folds the rail away and the full table takes over.
  test "the rail lists every roll and marks the one on screen", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/negatives")

    assert has_element?(view, "nav.roll-rail")
    assert has_element?(view, "a.roll-rail-item.is-current[aria-current]")

    sheets = Web.Negatives.list_contact_sheets()

    for sheet <- sheets do
      assert has_element?(view, "a.roll-rail-item", sheet.roll)
    end
  end

  # The index is browsed along two axes: when it was scanned, and what it was
  # shot on.
  test "index sorts by scan date and film type, and the sort lives in the URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/negatives?mode=index")

    # Default: newest scans first.
    assert render(view) =~ "newest first"

    # Defaults stay out of the query string, the way /logs and /blog already
    # build theirs — `sort=date&dir=desc` says only "as usual".
    # Verified routes encode the query in a stable order of their own, which
    # is why these read alphabetically rather than in the order built.
    view |> element("th a", "Scan Date") |> render_click()
    assert_patched(view, "/negatives?dir=asc&mode=index")
    assert render(view) =~ "oldest first"

    view |> element("th a", "Format") |> render_click()
    assert_patched(view, "/negatives?mode=index&sort=format")
    assert render(view) =~ "film type"

    # Clicking the active column flips it rather than restarting.
    view |> element("th a", "Format") |> render_click()
    assert_patched(view, "/negatives?dir=asc&mode=index&sort=format")
  end

  test "a sorted index can be linked to directly", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/negatives?mode=index&sort=format&dir=asc")
    assert html =~ "film type"
    assert html =~ "oldest first"
  end

  # Every step the reader takes is a step the browser knows about. This is the
  # whole point of the rewrite: `patch` pushes a history entry, so Back means
  # "the roll before this one" rather than "leave the archive".
  describe "walking the archive" do
    setup do
      root = Fixture.archive!()

      for {roll, date} <- [{"011", "2026-01-01"}, {"012", "2026-02-01"}, {"013", "2026-03-01"}] do
        Fixture.put_roll!(root, roll: roll, date: date, format: "120")
        Fixture.put_sheet!(root, "roll#{roll}_#{date}_120_bw", 2400, 3000)
      end

      :ok
    end

    test "the front door opens on the newest roll", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/negatives")
      assert html =~ "Roll #013"
      assert html =~ "1 of 3"
    end

    test "stepping forward lands in the URL", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/negatives")

      view |> element("a.next-btn") |> render_click()
      assert_patched(view, "/negatives/roll/012")
      assert render(view) =~ "2 of 3"

      view |> element("a.next-btn") |> render_click()
      assert_patched(view, "/negatives/roll/011")
      assert render(view) =~ "3 of 3"
    end

    test "the archive is a list, not a loop", %{conn: conn} do
      # Newest roll: nothing before it.
      {:ok, view, _html} = live(conn, "/negatives/roll/13")
      refute has_element?(view, "a.prev-btn")
      assert has_element?(view, ".stage-arrow--prev.is-spent")
      assert has_element?(view, "a.next-btn")

      # Oldest roll: nothing after it.
      {:ok, view, _html} = live(conn, "/negatives/roll/11")
      assert has_element?(view, "a.prev-btn")
      refute has_element?(view, "a.next-btn")
      assert has_element?(view, ".stage-arrow--next.is-spent")
    end

    test "a roll can be linked to, and opens on itself", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/negatives/roll/012")
      assert html =~ "Roll #012"
      assert html =~ "2 of 3"
    end

    test "roll tokens resolve however they are spelled", %{conn: conn} do
      for token <- ["12", "012", "roll012"] do
        {:ok, _view, html} = live(conn, "/negatives/roll/#{token}")
        assert html =~ "Roll #012", "failed for #{token}"
      end
    end

    test "an unknown roll falls back to the archive", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/negatives"}}} = live(conn, "/negatives/roll/9999")
    end

    test "the old ?slug= form is patched to the roll's real address", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/negatives/roll/012"}}} =
               live(conn, "/negatives?slug=roll012_2026-02-01_120_bw")
    end

    test "a roll in the rail is a link to that roll", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/negatives")

      view |> element("a.roll-rail-item[href='/negatives/roll/011']") |> render_click()
      assert_patched(view, "/negatives/roll/011")
      assert render(view) =~ "Roll #011"
    end

    test "arrow keys walk the archive, and stop at the ends", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/negatives/roll/13")

      press(view, "key_next", "ArrowRight")
      assert_patched(view, "/negatives/roll/012")

      press(view, "key_prev", "ArrowLeft")
      assert_patched(view, "/negatives/roll/013")

      # Already at the newest: the key does nothing rather than wrapping.
      press(view, "key_prev", "ArrowLeft")
      assert render(view) =~ "Roll #013"
    end

    test "the neighbouring sheets are prefetched", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/negatives/roll/012")

      assert html =~ ~s(rel="prefetch")
      assert html =~ "roll013_2026-03-01_120_bw"
      assert html =~ "roll011_2026-01-01_120_bw"
    end
  end

  # The keyboard is the one control that cannot be a link, so it is the one
  # place that still pushes a patch of its own.
  defp press(view, event, key) do
    view |> element("[phx-window-keydown='#{event}']") |> render_keydown(%{"key" => key})
  end

  # A frame URL exists so a single photograph can be linked to and still name
  # the sheet it came from.
  test "an unresolvable frame falls back to the archive", %{conn: conn} do
    assert {:error, {:live_redirect, %{to: "/negatives"}}} =
             live(conn, "/negatives/roll/9999/frame/1")
  end

  test "a published frame renders and points back at its contact sheet", %{conn: conn} do
    tmp = fixture_archive()

    {:ok, view, html} = live(conn, "/negatives/roll/13/frame/3")

    assert html =~ "Frame 3"
    assert html =~ "/negatives/frame/13/3"
    # The provenance the URL exists to carry.
    assert html =~ "From Roll #013"
    assert has_element?(view, "a.frame-origin[href='/negatives/roll/013']")

    # Neighbours move within the roll: frame 3 is the last of {1, 3}, so it has
    # a previous and no next — the strip does not wrap into another sheet.
    assert has_element?(view, "a.prev-btn[href='/negatives/roll/013/frame/1']")
    refute has_element?(view, "a.next-btn")

    File.rm_rf!(tmp)
  end

  # Regression: the strip used to keep showing the first sheet's frames forever,
  # because the prev/next handlers assigned :sheet without recomputing them.
  test "the frame strip follows the sheet when you navigate", %{conn: conn} do
    fixture_archive(second_roll: true)

    {:ok, view, html} = live(conn, "/negatives")

    # Starts on the most recent roll — #14, which has nothing printed.
    assert html =~ "Roll #014"
    refute html =~ "frame-strip"

    view |> element("a.next-btn") |> render_click()

    # Roll #13 does have prints, so the strip appears and points at *its* frames.
    html = render(view)
    assert html =~ "Roll #013"
    assert html =~ "frame-strip"
    assert html =~ "/negatives/frame/13/1"

    # And going back drops it again rather than carrying roll 13's frames over.
    view |> element("a.prev-btn") |> render_click()
    html = render(view)
    assert html =~ "Roll #014"
    refute html =~ "frame-strip"
  end

  # A miniature archive: one contact sheet plus the individual frames it was
  # cut from, wired together by catalog.csv the way the real one is.
  # `second_roll: true` adds a later, frameless roll so navigation can be
  # observed crossing between a sheet that has frames and one that doesn't.
  defp fixture_archive(opts \\ []) do
    tmp = Path.join(System.tmp_dir!(), "neg_live_#{System.unique_integer([:positive])}")
    roll_dir = Path.join(tmp, "120 Film/roll013")
    File.mkdir_p!(Path.join(tmp, "Contact Sheets"))
    File.mkdir_p!(roll_dir)

    File.write!(Path.join([tmp, "Contact Sheets", "roll013_2026-08-03_120_bw.png"]), "x")

    # Two frames of this roll have been printed; the rest of it has not.
    File.mkdir_p!(Path.join(roll_dir, "frames"))
    for name <- ["01.jpg", "03.jpg"], do: File.write!(Path.join([roll_dir, "frames", name]), "x")

    catalog = """
    roll,scan_date,film_type,color,frames,folder
    13,2026-08-03,120,bw,4,120 Film/roll013
    """

    catalog =
      if opts[:second_roll] do
        # Later scan date, no frames on disk: sorts first, so the viewer opens
        # on a sheet whose strip should be empty.
        File.mkdir_p!(Path.join(tmp, "35mm Film/roll014"))
        File.write!(Path.join([tmp, "Contact Sheets", "roll014_2026-08-09_35mm_bw.png"]), "x")
        catalog <> "14,2026-08-09,35mm,bw,4,35mm Film/roll014\n"
      else
        catalog
      end

    File.write!(Path.join(tmp, "catalog.csv"), catalog)

    prev = Application.get_env(:web, :negatives_path)
    Application.put_env(:web, :negatives_path, tmp)

    on_exit(fn ->
      if prev,
        do: Application.put_env(:web, :negatives_path, prev),
        else: Application.delete_env(:web, :negatives_path)
    end)

    tmp
  end

  test "the sheet carries its controls on the image, and its metadata above", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/negatives")

    sheets = Web.Negatives.list_contact_sheets()

    case sheets do
      [_first | _] ->
        assert has_element?(view, ".stage-image")
        # Controls ride on the image rather than in a bar beneath it.
        assert has_element?(view, "a.stage-arrow.prev-btn") or
                 has_element?(view, ".stage-arrow--prev.is-spent")

        assert has_element?(view, "a.stage-arrow.next-btn") or
                 has_element?(view, ".stage-arrow--next.is-spent")

        assert has_element?(view, "a.stage-download")

        # Starts on the most recent roll (not random) and stages the preview
        most_recent = sheets |> Enum.sort_by(& &1.date, :desc) |> hd()
        assert render(view) =~ "/negatives/preview/"

        # The heading is the roll's metadata, not its filename.
        assert has_element?(view, ".sheet-meta", "Roll ##{most_recent.roll}")
        assert has_element?(view, ".sheet-meta", most_recent.date)
        refute has_element?(view, ".sheet-meta", most_recent.filename)

      # Stepping between rolls is exercised against a multi-roll archive in
      # "walking the archive" below; this fixture holds a single sheet, so
      # both arrows are correctly spent.

      [] ->
        assert render(view) =~ "No contact sheets found"
    end
  end

  # Marking the selects: a frame that has been printed gets a grease pencil
  # ring on the sheet, and the ring is the way in to the photograph.
  describe "the sheet's marks" do
    setup do
      root = Fixture.archive!()
      {folder, slug} = Fixture.golden_roll!(root)
      %{root: root, folder: folder, slug: slug}
    end

    test "a roll with nothing printed carries no marks", %{conn: conn, slug: _slug} do
      {:ok, _view, html} = live(conn, "/negatives/roll/013")

      # The page is otherwise exactly the page it has always been.
      assert html =~ "sheet-plate"
      refute html =~ "sheet-marks"
    end

    test "a printed frame is circled, and the circle opens it",
         %{conn: conn, folder: folder, slug: _slug} do
      Fixture.put_print!(folder, 3)

      {:ok, view, html} = live(conn, "/negatives/roll/013")

      assert html =~ "sheet-marks"
      assert has_element?(view, "a.sheet-mark[href='/negatives/roll/013/frame/3']")

      # Named for a screen reader, since the ring itself says nothing.
      assert has_element?(view, "a.sheet-mark[aria-label='View frame 3 of roll #013']")

      # Positioned as a fraction of the sheet, against a plate that carries the
      # sheet's own proportions — see negatives.css.
      assert html =~ "--sheet-ar: 0.8"
      assert html =~ "--x:"
    end

    test "only printed frames are circled", %{conn: conn, folder: folder, slug: _slug} do
      Fixture.put_print!(folder, 2)
      Fixture.put_print!(folder, 4)

      {:ok, view, _html} = live(conn, "/negatives/roll/013")

      assert has_element?(view, "a.sheet-mark[href='/negatives/roll/013/frame/2']")
      assert has_element?(view, "a.sheet-mark[href='/negatives/roll/013/frame/4']")
      refute has_element?(view, "a.sheet-mark[href='/negatives/roll/013/frame/1']")
      refute has_element?(view, "a.sheet-mark[href='/negatives/roll/013/frame/3']")
    end

    test "an archive the layout cannot account for draws nothing, and still renders",
         %{conn: conn, root: root, folder: folder, slug: slug} do
      Fixture.put_print!(folder, 3)
      # A strip scanned since the last analysis: frames.json no longer
      # describes the roll, so where anything sits is no longer known.
      File.write!(Path.join(folder, "009.tiff"), "a strip scanned later")

      {:ok, _view, html} = live(conn, "/negatives/roll/013")

      refute html =~ "sheet-marks"
      # The print is still reachable, just not from the sheet.
      assert html =~ "frame-strip"
      assert File.exists?(Path.join([root, "Contact Sheets", "#{slug}.png"]))
    end

    test "the strip below the sheet links to the frame's page, not its bytes",
         %{conn: conn, folder: folder, slug: _slug} do
      Fixture.put_print!(folder, 3)

      {:ok, view, _html} = live(conn, "/negatives/roll/013")

      assert has_element?(view, "a.frame-thumb[href='/negatives/roll/013/frame/3']")
      refute has_element?(view, "a.frame-thumb[href='/negatives/frame/013/3']")
    end
  end
end
