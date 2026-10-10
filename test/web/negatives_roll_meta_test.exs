defmodule Web.Negatives.RollMetaTest do
  use ExUnit.Case, async: true

  alias Web.Negatives.RollMeta

  setup do
    dir = Path.join(System.tmp_dir!(), "roll_meta_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)
    %{dir: dir}
  end

  test "a roll nothing has been said about is empty, folder or no folder", %{dir: dir} do
    assert RollMeta.empty?(RollMeta.read(dir))
    assert RollMeta.empty?(RollMeta.read(Path.join(dir, "not-there")))
  end

  test "when it was shot is as exact as is known, and no more" do
    assert {:ok, %{shot: "2023"}} = RollMeta.cast(%{"shot" => " 2023 "})
    assert {:ok, %{shot: "2023-06"}} = RollMeta.cast(%{"shot" => "2023-06"})
    assert {:ok, %{shot: "2023-06-14"}} = RollMeta.cast(%{"shot" => "2023-06-14"})
    assert {:ok, %{shot: nil}} = RollMeta.cast(%{"shot" => ""})

    for nonsense <- ["last summer", "23", "2023-13", "2023-02-30", "2023/06/14", "3023"] do
      assert {:error, said} = RollMeta.cast(%{"shot" => nonsense})
      assert said =~ "is not a date"
    end

    assert RollMeta.shot_line("2023") == "2023"
    assert RollMeta.shot_line("2023-06") == "June 2023"
    assert RollMeta.shot_line("2023-06-04") == "June 4, 2023"
    assert RollMeta.shot_line(%{shot: nil}) == nil
  end

  test "it is written beside the strips, and what else the file held is kept", %{dir: dir} do
    # The negatives command once left the catalog row here.
    File.write!(Path.join(dir, "roll.json"), ~s({"roll": "001", "frames": 4}))

    {:ok, meta} =
      RollMeta.cast(%{
        "shot" => "2023",
        "camera" => "  Olympus XA ",
        "film" => "Portra 400",
        "place" => "",
        "notes" => "Found in a drawer."
      })

    assert :ok = RollMeta.write(dir, meta)

    assert %{shot: "2023", camera: "Olympus XA", film: "Portra 400", place: nil} =
             RollMeta.read(dir)

    assert RollMeta.gear_line(RollMeta.read(dir)) == "Olympus XA · Portra 400"

    assert %{"roll" => "001", "frames" => 4} =
             Jason.decode!(File.read!(Path.join(dir, "roll.json")))

    # A field emptied is a field removed.
    {:ok, meta} = RollMeta.cast(%{"shot" => "2023"})
    assert :ok = RollMeta.write(dir, meta)
    assert %{camera: nil, notes: nil, shot: "2023"} = RollMeta.read(dir)
    assert RollMeta.gear_line(RollMeta.read(dir)) == nil
  end

  test "a roll with no folder has nowhere to keep it, and a file left empty is removed", %{
    dir: dir
  } do
    {:ok, meta} = RollMeta.cast(%{"shot" => "2023"})
    assert {:error, :no_folder} = RollMeta.write(Path.join(dir, "not-there"), meta)

    assert :ok = RollMeta.write(dir, meta)
    {:ok, none} = RollMeta.cast(%{})
    assert :ok = RollMeta.write(dir, none)
    refute File.exists?(Path.join(dir, "roll.json"))
  end
end
