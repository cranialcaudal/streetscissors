defmodule Web.Darkroom.RepairTest do
  use ExUnit.Case, async: false

  import Web.NegativesFixtures

  alias Web.Darkroom
  alias Web.Darkroom.Repair

  # Masks are pictures; these tests make real ones.
  if System.find_executable("magick") do
    setup do
      root = archive!()
      folder = put_roll!(root, roll: "007", format: "35mm", color: "color")
      File.mkdir_p!(Path.join(folder, "frames"))
      print = Path.join([folder, "frames", "03.png"])
      {_, 0} = System.cmd("magick", ["-size", "40x20", "gradient:white-gray", print])
      %{folder: folder, print: print}
    end

    defp png(args) do
      path = Path.join(System.tmp_dir!(), "mask_#{System.unique_integer([:positive])}.png")
      {_, 0} = System.cmd("magick", args ++ [path])
      bytes = File.read!(path)
      File.rm(path)
      bytes
    end

    test "found lines are added to the mask", %{folder: folder} do
      refute Repair.mask?(folder, 3)
      assert {:ok, 1} = Repair.find_lines(folder, 3)
      assert Repair.mask?(folder, 3)
      assert Darkroom.dimensions(Darkroom.mask_path(folder, 3)) == {40, 20}
    end

    test "a painted mask is kept at the picture's size, and an empty one is no mask", %{
      folder: folder
    } do
      painted = png(~w(-size 400x200 xc:black -fill white -draw) ++ ["rectangle 10,10 50,30"])
      assert :ok = Repair.put_mask(folder, 3, painted)
      assert Darkroom.dimensions(Darkroom.mask_path(folder, 3)) == {40, 20}

      assert :ok = Repair.put_mask(folder, 3, png(~w(-size 400x200 xc:black)))
      refute Repair.mask?(folder, 3)

      assert {:error, _} = Repair.put_mask(folder, 3, "not a png")
    end

    test "a repair is made from the print as developed, and the sliders work on it", %{
      folder: folder,
      print: print
    } do
      developed = File.read!(print)
      assert {:error, _} = Repair.lama(folder, 3)

      {:ok, _} = Repair.find_lines(folder, 3)
      assert {:ok, %{lines: 1, places: 1}} = Repair.lama(folder, 3)
      assert File.read!(Darkroom.base_path(folder, 3)) == developed
      assert Darkroom.source_path(folder, 3) == Darkroom.repaired_path(folder, 3)

      # A repair alone is worth saving: the print is made from it.
      assert :ok = Darkroom.save(folder, 3, Darkroom.empty())
      assert Darkroom.edited?(folder, 3)

      :ok = Darkroom.revert(folder, 3)
      refute Repair.mask?(folder, 3)
      refute Repair.repaired?(folder, 3)
      assert File.read!(print) == developed
    end

    test "the mask and the repair turn with the frame", %{folder: folder} do
      {:ok, _} = Repair.find_lines(folder, 3)
      {:ok, _} = Repair.lama(folder, 3)
      :ok = Darkroom.save(folder, 3, Darkroom.empty())

      :ok = Darkroom.turn(folder, 3, 90)
      assert Darkroom.dimensions(Darkroom.mask_path(folder, 3)) == {20, 40}
      assert Darkroom.dimensions(Darkroom.repaired_path(folder, 3)) == {20, 40}
    end

    test "a failed repair says so and changes nothing", %{folder: folder} do
      {:ok, _} = Repair.find_lines(folder, 3)
      System.put_env("STUB_FILM_REPAIR_FAIL", "1")
      on_exit(fn -> System.delete_env("STUB_FILM_REPAIR_FAIL") end)

      assert {:error, reason} = Repair.lama(folder, 3)
      assert reason =~ "could not read"
      refute Repair.repaired?(folder, 3)
    end
  end
end
