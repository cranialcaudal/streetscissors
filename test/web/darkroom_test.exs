defmodule Web.DarkroomTest do
  # The archive and the stub's switches are process-wide: environment
  # variables and the negatives path.
  use ExUnit.Case, async: false

  import Web.NegativesFixtures

  alias Web.Darkroom
  alias Web.Darkroom.Session

  setup do
    root = archive!()
    folder = put_roll!(root, roll: "007", format: "35mm", color: "color")
    File.mkdir_p!(Path.join(folder, "frames"))
    print = Path.join([folder, "frames", "03.png"])
    File.write!(print, png_bytes(30, 20))

    on_exit(fn ->
      System.delete_env("STUB_LIGHTCRAFT_FAIL")
      System.delete_env("STUB_LIGHTCRAFT_LOG")
    end)

    {:ok, folder: folder, print: print}
  end

  @schema [
    %{
      "id" => "light.exposure",
      "section" => "light",
      "min" => -5.0,
      "max" => 5.0,
      "default" => 0.0
    },
    %{"id" => "hdr.maxEv", "section" => "light", "min" => 0.0, "max" => 4.0, "default" => 0.0},
    %{
      "id" => "hdr.sdrWhites",
      "section" => "light",
      "min" => -100.0,
      "max" => 100.0,
      "default" => 0.0
    },
    %{
      "id" => "wb.temp",
      "section" => "color",
      "min" => 2000.0,
      "max" => 50000.0,
      "default" => 6500.0
    },
    %{
      "id" => "optics.distortion",
      "section" => "optics",
      "min" => -100.0,
      "max" => 100.0,
      "default" => 0.0
    }
  ]

  @recipe %{
    controls: %{"light.exposure" => 0.4},
    crop: %{rect: [0.1, 0.2, 0.5, 0.6], angle: 2.0},
    spots: []
  }

  describe "the recipe" do
    test "a crop turns with its picture, a quarter at a time" do
      crop = %{rect: [0.1, 0.2, 0.5, 0.6], angle: 2.0}

      assert Darkroom.turn_crop(crop, 90).rect == [0.4, 0.1, 0.8, 0.5]
      assert Darkroom.turn_crop(crop, 90).angle == 2.0
      assert Darkroom.turn_crop(crop, 360) == crop

      four = Enum.reduce(1..4, crop, fn _, c -> Darkroom.turn_crop(c, 90) end)
      assert Enum.map(four.rect, &Float.round(&1, 9)) == crop.rect
      assert Darkroom.turn_crop(crop, 270) == Darkroom.turn_crop(crop, -90)
      assert Darkroom.turn_crop(nil, 90) == nil
    end

    test "only real sliders off their default are kept, each held to its range" do
      sent = %{
        "light.exposure" => "7.5",
        "wb.temp" => "6500",
        "nope.x" => "1",
        "_target" => ["light.exposure"],
        "hdr.maxEv" => "not a number"
      }

      assert Darkroom.clean_controls(sent, @schema) == %{"light.exposure" => 5.0}
    end

    test "a black and white print is offered no colour, and nothing describes a camera" do
      colour = Darkroom.sections(@schema, false)
      grey = Darkroom.sections(@schema, true)

      assert Enum.map(colour, & &1.key) == ["light", "color"]
      assert Enum.map(grey, & &1.key) == ["light"]
      assert [%{controls: [%{"id" => "light.exposure"}]} | _] = colour
    end

    test "a crop that is the whole picture and level is no crop" do
      assert Darkroom.clean_crop(%{"rect" => [0, 0, 1, 1], "angle" => 0}) == nil
      assert Darkroom.clean_crop(%{"rect" => [0, 0, 1, 1], "angle" => "3.5"}).angle == 3.5
      assert Darkroom.clean_crop(%{"rect" => [-1, 0.2, 2, 0.8]}).rect == [0.0, 0.2, 1.0, 0.8]
      assert Darkroom.clean_crop(%{"rect" => [0.5, 0.5, 0.505, 0.9]}) == nil
      assert Darkroom.clean_crop(%{"rect" => "0,0,1,1"}) == nil
    end

    test "the commands start from nothing, so a slider let go is undone" do
      assert [
               {"develop.reset", %{}},
               {"develop.set", %{"values" => %{"light.exposure" => 0.4}}},
               {"crop.set", %{"rect" => [0.1, 0.2, 0.5, 0.6], "angle" => 2.0}}
             ] = Darkroom.commands(@recipe)

      assert Darkroom.commands(Darkroom.empty()) == [{"develop.reset", %{}}]
    end
  end

  describe "dust and the crop's pixels" do
    test "a crop's edges are put on whole pixels, so LightCraft does not resample the print" do
      [{"develop.reset", _}, {"crop.set", %{"rect" => rect}}] =
        Darkroom.commands(
          %{controls: %{}, crop: %{rect: [0.3, 0.2, 0.6, 0.5], angle: 0.0}, spots: []},
          {2229, 1488}
        )

      assert rect == [669 / 2229, 298 / 1488, 1337 / 2229, 744 / 1488]
    end

    test "dust spots are healed after the crop, in the whole picture's fractions" do
      recipe = %{controls: %{}, crop: nil, spots: [%{x: 0.25, y: 0.5, size: 0.004}]}

      assert [_, {"spot.add", %{"mode" => "heal", "points" => [[0.25, 0.5]], "size" => 0.004}}] =
               Darkroom.commands(recipe)
    end

    test "spots from anywhere are held to the picture and a sensible size" do
      assert [%{x: 0.5, y: 0.25, size: 0.05}, %{x: 0.1, y: 0.1, size: 0.004}] =
               Darkroom.clean_spots([
                 %{"x" => 0.5, "y" => 0.25, "size" => 1},
                 %{"x" => 2, "y" => 0.5},
                 %{"x" => "0.1", "y" => 0.1},
                 "nonsense"
               ])

      assert Darkroom.clean_spots(nil) == []
    end

    test "spots are kept with the recipe and turn with the picture", %{folder: folder} do
      recipe = %{
        controls: %{"light.exposure" => 0.2},
        crop: nil,
        spots: [%{x: 0.25, y: 0.75, size: 0.004}]
      }

      :ok = Darkroom.save(folder, 3, recipe)
      assert Darkroom.recipe(folder, 3) == recipe

      :ok = Darkroom.turn(folder, 3, 90)
      assert [%{x: 0.25, y: 0.25}] = Darkroom.recipe(folder, 3).spots
    end
  end

  describe "printing" do
    test "the first save sets the print as developed aside and keeps the recipe",
         %{folder: folder, print: print} do
      developed = File.read!(print)

      assert :ok = Darkroom.save(folder, 3, @recipe)
      assert File.read!(Darkroom.base_path(folder, 3)) == developed
      assert Darkroom.recipe(folder, 3) == @recipe
      assert Darkroom.edited?(folder, 3)
      assert File.regular?(print)
      assert Darkroom.source_path(folder, 3) == Darkroom.base_path(folder, 3)
      assert File.ls!(Path.join(folder, "developed")) == ["03.png"]
    end

    test "LightCraft is given the recipe and asked for the whole print",
         %{folder: folder} do
      log = Path.join(folder, "lightcraft.log")
      System.put_env("STUB_LIGHTCRAFT_LOG", log)

      :ok = Darkroom.save(folder, 3, @recipe)

      commands =
        log |> File.read!() |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

      assert Enum.map(commands, & &1["command"]) ==
               ["develop.reset", "develop.set", "crop.set", "app.export"]

      assert %{"params" => %{"values" => %{"light.exposure" => 0.4}}} = Enum.at(commands, 1)
      assert %{"params" => %{"longEdge" => 0, "metadata" => "none"}} = List.last(commands)
    end

    test "a refused edit leaves the print alone and keeps no recipe",
         %{folder: folder, print: print} do
      before = File.read!(print)
      System.put_env("STUB_LIGHTCRAFT_FAIL", "1")

      assert {:error, reason} = Darkroom.save(folder, 3, @recipe)
      assert reason =~ "develop.set"
      assert File.read!(print) == before
      refute Darkroom.edited?(folder, 3)
    end

    test "revert puts the print back as developed and forgets the recipe",
         %{folder: folder, print: print} do
      developed = File.read!(print)
      :ok = Darkroom.save(folder, 3, @recipe)
      File.write!(print, "an edited print")

      assert :ok = Darkroom.revert(folder, 3)
      assert File.read!(print) == developed
      refute Darkroom.edited?(folder, 3)
      refute File.exists?(Darkroom.base_path(folder, 3))
    end

    test "saving an empty recipe is a revert", %{folder: folder, print: print} do
      developed = File.read!(print)
      :ok = Darkroom.save(folder, 3, @recipe)

      assert :ok = Darkroom.save(folder, 3, Darkroom.empty())
      assert File.read!(print) == developed
      refute Darkroom.edited?(folder, 3)
    end

    test "developed again, the new print is what the recipe applies to",
         %{folder: folder, print: print} do
      :ok = Darkroom.save(folder, 3, @recipe)
      File.write!(print, png_bytes(40, 30))

      assert :ok = Darkroom.reapply(folder, 3)
      assert File.read!(Darkroom.base_path(folder, 3)) == png_bytes(40, 30)
      assert Darkroom.recipe(folder, 3) == @recipe
      assert File.regular?(print)
    end

    test "turned, the crop stays on the same part of the picture", %{folder: folder} do
      :ok = Darkroom.save(folder, 3, @recipe)

      assert :ok = Darkroom.turn(folder, 3, 90)
      assert Darkroom.recipe(folder, 3).crop.rect == [0.4, 0.1, 0.8, 0.5]
    end

    test "a frame with no recipe is left alone", %{folder: folder, print: print} do
      before = File.read!(print)

      assert :ok = Darkroom.reapply(folder, 3)
      assert :ok = Darkroom.turn(folder, 3, 90)
      assert File.read!(print) == before
      refute File.exists?(Path.join(folder, "developed"))
      refute File.exists?(Path.join(folder, "edits"))
    end
  end

  describe "the session" do
    test "opens LightCraft, offers its sliders and sends each picture to its owner",
         %{print: print} do
      assert {:ok, pid, info} = Session.start(print)
      assert "light.exposure" in Enum.map(info.schema, & &1["id"])
      {:ok, dir} = Session.dir(info.token)
      assert File.regular?(Path.join(dir, "before.jpg"))
      assert {:ok, %File.Stat{access: _, mode: mode}} = File.stat(dir)
      assert Bitwise.band(mode, 0o077) == 0

      Session.preview(pid, %{controls: %{"light.exposure" => 0.5}, crop: nil}, 1)
      assert_receive {:darkroom_preview, 1, "p-1.jpg"}, 5_000
      assert File.regular?(Path.join(dir, "p-1.jpg"))

      Session.stop(pid)
    end

    test "only the newest of the pictures asked for meanwhile is kept", %{print: print} do
      {:ok, pid, info} = Session.start(print)
      {:ok, dir} = Session.dir(info.token)

      for n <- 1..6, do: Session.preview(pid, Darkroom.empty(), n)
      assert_receive {:darkroom_preview, 6, "p-6.jpg"}, 5_000

      # The page may still be loading the one before; nothing older is kept.
      assert length(Path.wildcard(Path.join(dir, "p-*.jpg"))) <= 2
      Session.stop(pid)
    end

    test "a refused edit is said, and the session carries on", %{print: print} do
      System.put_env("STUB_LIGHTCRAFT_FAIL", "1")
      {:ok, pid, _info} = Session.start(print)

      Session.preview(pid, %{controls: %{"light.exposure" => 0.5}, crop: nil}, 1)
      assert_receive {:darkroom_error, 1, reason}, 5_000
      assert reason =~ "unknown control"

      Session.preview(pid, Darkroom.empty(), 2)
      assert_receive {:darkroom_preview, 2, _}, 5_000
      Session.stop(pid)
    end

    test "ends with the page that opened it, taking its pictures along", %{print: print} do
      test = self()

      owner =
        spawn(fn ->
          {:ok, pid, info} = Session.start(print)
          send(test, {:opened, pid, info.token})
          receive do: (:stop -> :ok)
        end)

      assert_receive {:opened, pid, token}, 5_000
      {:ok, dir} = Session.dir(token)
      ref = Process.monitor(pid)

      send(owner, :stop)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 5_000
      refute File.exists?(dir)
    end

    test "a token of any other shape names no folder" do
      assert Session.dir("../../etc") == :error
      assert Session.dir(String.duplicate("A", 32)) == :error
      assert {:ok, _} = Session.dir(String.duplicate("a", 32))
    end
  end
end
