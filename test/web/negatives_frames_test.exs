defmodule Web.NegativesFramesTest do
  use ExUnit.Case, async: false

  alias Web.Negatives

  # A roll folder holds the individual frames the contact sheet was cut from.
  # list_frames/1 is what lets a single photograph be published under — and
  # point back at — the sheet it came from.
  setup do
    tmp = Path.join(System.tmp_dir!(), "negatives_test_#{System.unique_integer([:positive])}")
    roll_dir = Path.join(tmp, "120 Film/roll013")
    File.mkdir_p!(Path.join(tmp, "Contact Sheets"))
    File.mkdir_p!(Path.join(roll_dir, "previews"))

    # Frames land out of order on disk on purpose: list_frames/1 sorts.
    for name <- ["03.jpg", "01.jpg", "10.jpg"], do: File.write!(Path.join(roll_dir, name), "x")
    # Not a frame: no digits before the extension.
    File.write!(Path.join(roll_dir, "roll013_2026-08-03_120_bw.png"), "x")

    File.write!(Path.join(tmp, "catalog.csv"), """
    roll,scan_date,film_type,color,frames,folder
    13,2026-08-03,120,bw,4,120 Film/roll013
    """)

    prev = Application.get_env(:web, :negatives_path)
    Application.put_env(:web, :negatives_path, tmp)

    on_exit(fn ->
      if prev,
        do: Application.put_env(:web, :negatives_path, prev),
        else: Application.delete_env(:web, :negatives_path)

      File.rm_rf!(tmp)
    end)

    {:ok, tmp: tmp}
  end

  test "lists a roll's frames in frame order with their own URLs" do
    assert [
             %{frame: 1, url: "/negatives/frame/13/1"},
             %{frame: 3, url: "/negatives/frame/13/3"},
             %{frame: 10, url: "/negatives/frame/13/10"}
           ] = Negatives.list_frames("13")
  end

  test "accepts the padded and prefixed forms of a roll" do
    assert Negatives.list_frames("013") == Negatives.list_frames("13")
    assert Negatives.list_frames("roll013") == Negatives.list_frames("13")
  end

  test "the contact sheet in the folder is not mistaken for a frame" do
    refute Enum.any?(Negatives.list_frames("13"), &(&1.frame == 2026))
  end

  test "returns [] for a roll that is not in the catalog" do
    assert Negatives.list_frames("999") == []
    assert Negatives.list_frames("nonsense") == []
  end
end
