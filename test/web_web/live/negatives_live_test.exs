defmodule WebWeb.NegativesLiveTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest

  test "renders minimalist viewer and can toggle to index by scan date", %{conn: conn} do
    {:ok, view, html} = live(conn, "/negatives")

    assert html =~ "Full Index by Scan Date"
    assert has_element?(view, ".single-presentation-viewport")

    # Toggle to index view
    view
    |> element("button.index-toggle-btn")
    |> render_click()

    assert render(view) =~ "Contact Sheets Index"
    assert has_element?(view, ".minimal-index-table")

    # Toggle back to single view
    view
    |> element("button.index-toggle-btn")
    |> render_click()

    assert has_element?(view, ".single-presentation-viewport")
  end

  # The index is browsed along two axes: when it was scanned, and what it was
  # shot on.
  test "index sorts by scan date and film type, and the sort lives in the URL", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/negatives?mode=index")

    # Default: newest scans first.
    assert render(view) =~ "newest first"

    view |> element("th", "Scan Date") |> render_click()
    assert_patched(view, "/negatives?mode=index&sort=date&dir=asc")
    assert render(view) =~ "oldest first"

    view |> element("th", "Format") |> render_click()
    assert_patched(view, "/negatives?mode=index&sort=format&dir=desc")
    assert render(view) =~ "film type"

    # Clicking the active column flips it rather than restarting.
    view |> element("th", "Format") |> render_click()
    assert_patched(view, "/negatives?mode=index&sort=format&dir=asc")
  end

  test "a sorted index can be linked to directly", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/negatives?mode=index&sort=format&dir=asc")
    assert html =~ "film type"
    assert html =~ "oldest first"
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
    assert has_element?(view, "a.frame-origin[href*='slug=']")

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

    # Starts on the most recent roll — #14, which has no individual scans.
    assert html =~ "Roll #014"
    refute html =~ "frame-strip"

    view |> element("button.next-btn") |> render_click()

    # Roll #13 does have scans, so the strip appears and points at *its* frames.
    html = render(view)
    assert html =~ "Roll #013"
    assert html =~ "frame-strip"
    assert html =~ "/negatives/frame/13/1"

    # And going back drops it again rather than carrying roll 13's frames over.
    view |> element("button.prev-btn") |> render_click()
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
    for name <- ["01.jpg", "03.jpg"], do: File.write!(Path.join(roll_dir, name), "x")

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
        assert has_element?(view, "button.stage-arrow.prev-btn")
        assert has_element?(view, "button.stage-arrow.next-btn")
        assert has_element?(view, "a.stage-download")

        # Starts on the most recent roll (not random) and stages the preview
        most_recent = sheets |> Enum.sort_by(& &1.date, :desc) |> hd()
        assert render(view) =~ "/negatives/preview/"

        # The heading is the roll's metadata, not its filename.
        assert has_element?(view, ".sheet-meta", "Roll ##{most_recent.roll}")
        assert has_element?(view, ".sheet-meta", most_recent.date)
        refute has_element?(view, ".sheet-meta", most_recent.filename)

        # Click next and prev buttons
        view |> element("button.next-btn") |> render_click()
        assert has_element?(view, ".stage-image")

        view |> element("button.prev-btn") |> render_click()
        assert has_element?(view, ".stage-image")

      [] ->
        assert render(view) =~ "No contact sheets found"
    end
  end
end
