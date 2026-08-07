defmodule WebWeb.PcLiveTest do
  use WebWeb.ConnCase
  import Phoenix.LiveViewTest

  @moduledoc """
  `/pc` is a navigator, not a museum piece: the tests that matter are the ones
  proving a real host filename gets you to the right page. PcLive had no tests
  at all before this.
  """

  # Points :negatives_path at a fixture volume laid out exactly like the real
  # one, so the terminal indexes real filenames.
  setup do
    tmp = Path.join(System.tmp_dir!(), "pc-negatives-#{System.unique_integer([:positive])}")
    sheets = Path.join(tmp, "Contact Sheets")
    roll = Path.join([tmp, "120 Film", "roll007_2026-07-22_120_bw"])
    File.mkdir_p!(sheets)
    File.mkdir_p!(roll)

    File.write!(Path.join(sheets, "roll007_2026-07-22_120_bw.png"), "png")

    for n <- ["01", "02", "03"] do
      File.write!(Path.join(roll, "roll007_2026-07-22_120_bw_#{n}.png"), "png")
    end

    File.write!(Path.join(tmp, "catalog.csv"), """
    roll,scan_date,film_type,color,frames,folder
    007,2026-07-22,120,bw,3,120 Film/roll007_2026-07-22_120_bw
    """)

    prev = Application.get_env(:web, :negatives_path)
    Application.put_env(:web, :negatives_path, tmp)

    on_exit(fn ->
      File.rm_rf!(tmp)

      if prev,
        do: Application.put_env(:web, :negatives_path, prev),
        else: Application.delete_env(:web, :negatives_path)
    end)

    :ok
  end

  defp run(view, command) do
    view |> form("form", %{"command" => command}) |> render_submit()
  end

  describe "the tree mirrors the host" do
    test "ls shows the real sections", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pc")
      out = run(view, "ls")

      assert out =~ "NEGATIVES"
      assert out =~ "BLOG"
    end

    test "names keep their real case and hyphens", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pc")
      out = run(view, "ls NEGATIVES/Contact Sheets")

      # The old build_fs upcased and turned "-" into "_", producing
      # ROLL007_2026_07_22_120_BW — a name on no disk anywhere.
      assert out =~ "roll007_2026-07-22_120_bw.png"
      refute out =~ "ROLL007_2026_07_22_120_BW"
    end

    test "cd is case-insensitive but the path keeps what you typed", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pc")
      assert run(view, "cd negatives") =~ "negatives"
      assert run(view, "ls") =~ "Contact Sheets"
    end

    test "the real catalog.csv is readable", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pc")
      out = run(view, "cat NEGATIVES/catalog.csv")

      assert out =~ "roll,scan_date,film_type"
      assert out =~ "007,2026-07-22,120,bw"
    end
  end

  describe "smart jump" do
    test "a bare roll name navigates to that contact sheet", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pc")
      run(view, "roll007_2026-07-22_120_bw")

      assert_redirect(view, "/negatives?slug=roll007_2026-07-22_120_bw")
    end

    test "a bare roll number navigates too", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pc")
      run(view, "7")

      assert_redirect(view, "/negatives?slug=roll007_2026-07-22_120_bw")
    end

    test "case does not matter", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pc")
      run(view, "ROLL007_2026-07-22_120_BW")

      assert_redirect(view, "/negatives?slug=roll007_2026-07-22_120_bw")
    end

    test "a frame name navigates to that frame's own page", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pc")
      run(view, "roll007_2026-07-22_120_bw_02")

      assert_redirect(view, "/negatives/roll/7/frame/2")
    end

    test "`open` does the same as a bare name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pc")
      run(view, "open roll007_2026-07-22_120_bw")

      assert_redirect(view, "/negatives?slug=roll007_2026-07-22_120_bw")
    end

    test "roll007 is not ambiguous — a roll answers to its number", %{conn: conn} do
      # It substring-matches every frame on the roll, but the roll reference is
      # an exact hit and has to win outright or the shorthand is useless.
      {:ok, view, _html} = live(conn, ~p"/pc")
      run(view, "roll007")

      assert_redirect(view, "/negatives?slug=roll007_2026-07-22_120_bw")
    end

    test "a genuinely ambiguous query lists numbered choices instead of guessing",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pc")
      # "120" matches the sheet and all three frames, with no exact hit.
      out = run(view, "120")

      assert out =~ "matches"
      assert out =~ "/negatives?slug=roll007_2026-07-22_120_bw"
      assert out =~ "/negatives/roll/7/frame/"
    end

    test "a digit then picks from the pending list", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pc")
      run(view, "120")
      run(view, "1")

      assert_redirect(view, "/negatives?slug=roll007_2026-07-22_120_bw")
    end

    test "with no pending list a digit is a roll number, not a choice", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pc")
      run(view, "7")

      assert_redirect(view, "/negatives?slug=roll007_2026-07-22_120_bw")
    end

    test "an out-of-range choice says so rather than crashing", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pc")
      run(view, "120")

      assert run(view, "99") =~ "No choice 99"
    end

    test "an unmatched token suggests how to look properly", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pc")
      out = run(view, "zzzznotathing")

      assert out =~ "Nothing here matches"
      assert out =~ "grep zzzznotathing"
    end
  end

  describe "looking without leaving" do
    test "view renders a contact sheet inline", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pc")
      out = run(view, "view roll007_2026-07-22_120_bw")

      assert out =~ "pc-rendered-media"
      assert out =~ "/negatives/preview/"
      # Rendering is not navigating.
      refute_redirected(view, "/negatives?slug=roll007_2026-07-22_120_bw")
    end

    test "view works on a bare name from anywhere, without cd-ing first", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pc")
      run(view, "cd BLOG")

      assert run(view, "view roll007_2026-07-22_120_bw") =~ "pc-rendered-media"
    end

    test "frames lists a roll's frames with their destinations", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pc")
      out = run(view, "frames 7")

      assert out =~ "3 frames"
      assert out =~ "/negatives/roll/7/frame/1"
      assert out =~ "roll007_2026-07-22_120_bw_03"
    end
  end

  describe "finding" do
    test "find matches names and prints path plus destination", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pc")
      out = run(view, "find 120")

      assert out =~ "C:\\NEGATIVES\\Contact Sheets\\roll007_2026-07-22_120_bw.png"
      assert out =~ "/negatives?slug="
    end

    test "find reports honestly when nothing matches", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pc")
      assert run(view, "find zzzz") =~ "No names match"
    end

    test "grep searches post bodies, not just names", %{conn: conn} do
      # The committed blog fixtures are the content here.
      {:ok, view, _html} = live(conn, ~p"/pc")
      out = run(view, "grep frontmatter")

      # Terminal output is HTML-escaped by format_info/1, so quotes arrive as
      # &#39; — assert on text that carries none.
      assert out =~ "matching"
      assert out =~ "BLOG"
      refute out =~ "No matches for"
    end
  end

  describe "housekeeping" do
    test "help documents the jump, which is the point of the machine", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pc")
      out = run(view, "help")

      assert out =~ "open"
      assert out =~ "frames"
      assert out =~ "just type it"
    end

    test "refresh rebuilds the index in place", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pc")
      assert run(view, "refresh") =~ "Index rebuilt"
    end

    test "the retired placeholders are gone", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pc")
      out = run(view, "ls")

      # GUESTBK.TXT said "coming soon"; TEST_AUDIO.MP3 pointed at "#".
      refute out =~ "GUESTBK"
      refute out =~ "TEST_AUDIO"
    end

    test "exit leaves the terminal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/pc")
      run(view, "exit")

      assert_redirect(view, "/")
    end
  end
end
