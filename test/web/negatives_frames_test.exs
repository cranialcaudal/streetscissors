defmodule Web.NegativesFramesTest do
  use ExUnit.Case, async: false

  alias Web.Negatives
  alias Web.NegativesFixtures, as: Fixture

  # A frame is a finished print: one exposure, rescanned at high resolution and
  # developed into the roll's `frames/` directory. That is what can be looked
  # at, so it is what list_frames/1 answers with — and what gets circled on the
  # contact sheet the exposure was cut from.
  setup do
    root = Fixture.archive!()
    folder = Fixture.put_roll!(root, roll: "013", format: "120", frames: "4")

    # The strips the sheet was assembled from. These are not frames: each one
    # holds three exposures, and the sheet already shows every one of them.
    for n <- ["001", "002", "003", "004"] do
      File.write!(Path.join(folder, "#{n}.tiff"), "strip scan")
    end

    %{root: root, folder: folder}
  end

  test "lists a roll's prints in frame order with their own URLs", %{folder: folder} do
    # Out of order on disk on purpose: list_frames/1 sorts.
    for n <- [3, 1, 10], do: Fixture.put_print!(folder, n)

    assert [
             %{frame: 1, url: "/negatives/frame/13/1"},
             %{frame: 3, url: "/negatives/frame/13/3"},
             %{frame: 10, url: "/negatives/frame/13/10"}
           ] = Negatives.list_frames("13")
  end

  test "every print carries a link to the original file too", %{folder: folder} do
    Fixture.put_print!(folder, 3)

    assert [%{original_url: "/negatives/frame/13/3/original"}] = Negatives.list_frames("13")
  end

  # The bug this replaces: the strip scans in the folder above were being
  # served as though each were a single photograph, so "frame 3" of a 120 roll
  # meant its third strip of three exposures.
  test "strip scans are not frames", %{folder: folder} do
    assert Negatives.list_frames("13") == []
    assert Negatives.frame_path("13", "1") == :error

    Fixture.put_print!(folder, 1)
    assert [%{frame: 1}] = Negatives.list_frames("13")
  end

  test "a roll that has never been printed answers with nothing" do
    assert Negatives.list_frames("13") == []
  end

  test "an unknown roll answers with nothing rather than raising" do
    assert Negatives.list_frames("9999") == []
    assert Negatives.list_frames("not-a-roll") == []
  end

  test "both of the pipeline's naming conventions resolve", %{folder: folder} do
    # `film-develop develop` writes NN.png; its --export writes frame-NN.png.
    Fixture.put_print!(folder, 1)
    Fixture.put_print!(folder, 2, name: "frame-02.png")

    assert [%{frame: 1}, %{frame: 2}] = Negatives.list_frames("13")
    assert {:ok, path} = Negatives.frame_path("13", "2")
    assert Path.basename(path) == "frame-02.png"
  end

  test "roll tokens are accepted padded, unpadded and prefixed", %{folder: folder} do
    Fixture.put_print!(folder, 1)

    for token <- ["13", "013", "roll013", "roll13"] do
      assert [%{frame: 1}] = Negatives.list_frames(token), "failed for #{token}"
    end
  end

  test "frame tokens are accepted padded", %{folder: folder} do
    Fixture.put_print!(folder, 3)

    assert {:ok, _} = Negatives.frame_path("13", "3")
    assert {:ok, _} = Negatives.frame_path("13", "003")
    assert Negatives.frame_path("13", "4") == :error
  end

  # What counts as a frame is "digits immediately before the extension", which
  # is what lets both naming conventions through. A file that ends in anything
  # else is skipped rather than guessed at.
  test "a file with no digits before its extension is not a frame", %{folder: folder} do
    dir = Path.join(folder, "frames")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "roll013_2026-08-03_120_bw.png"), "the sheet, misfiled")
    File.write!(Path.join(dir, "notes.txt"), "not an image either")

    assert Negatives.list_frames("13") == []
  end

  test "prints_dir/1 is the pipeline's own output directory" do
    assert Negatives.prints_dir("/archive/120 Film/roll013") == "/archive/120 Film/roll013/frames"
  end

  test "roll_dir/1 resolves through the catalog, and refuses what is not in it",
       %{folder: folder} do
    assert Negatives.roll_dir("13") == {:ok, folder}
    assert Negatives.roll_dir("9999") == :error
    assert Negatives.roll_dir("../../etc") == :error
  end
end
