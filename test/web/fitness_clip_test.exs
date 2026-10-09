defmodule Web.FitnessClipTest do
  # Films are files in the uploads folder every test shares.
  use ExUnit.Case, async: false

  alias Web.Fitness.Clip

  # The invented vault has one exercise with a figure, push-ups, whose
  # anatomy is "Chest". The camera is test/support/stub_camera.

  setup do
    scratch = Path.join(System.tmp_dir!(), "clip-test-#{System.unique_integer([:positive])}")
    vault = Path.join(scratch, "vault")
    uploads = Path.join(scratch, "uploads")
    File.mkdir_p!(uploads)
    File.cp_r!(Web.Fitness.Vault.base_path(), vault)

    was = for key <- [:fitness_path, :uploads_path], do: {key, Application.get_env(:web, key)}
    Application.put_env(:web, :fitness_path, vault)
    Application.put_env(:web, :uploads_path, uploads)

    on_exit(fn ->
      for {key, value} <- was, do: Application.put_env(:web, key, value)
      System.delete_env("STUB_CAMERA_FAIL")
      System.delete_env("STUB_CAMERA_TAKE")
      File.rm_rf(scratch)
    end)

    {:ok, vault: vault, figure: Path.join([vault, "figures", "push-ups.json"])}
  end

  describe "the muscles an anatomy line names" do
    test "are the camera's own, in the body's order" do
      assert Clip.muscles("Quadriceps, glutes and core") == ["abs", "glutes", "quads"]
      assert Clip.muscles("Rear delts, rhomboids, lats") == ["lats", "traps", "delts"]
      assert Clip.muscles("Posterior chain") == ["glutes", "hamstrings"]
    end

    test "the quadratus is a muscle of the back, not the thigh" do
      assert Clip.muscles("Obliques, quadratus lumborum") == ["obliques"]
    end

    test "the rotators of the hip are not the rotator cuff" do
      assert Clip.muscles("Rotator Cuff") == ["delts"]
      assert Clip.muscles("Hip Rotators & Adductors") == ["glutes", "adductors"]
      assert Clip.muscles("Glutes & External Rotators") == ["glutes"]
    end

    test "the hip flexors show at the front of the thigh, and the hips are the glutes" do
      assert Clip.muscles("Hip Flexors & Core") == ["abs", "quads"]
      assert Clip.muscles("Obliques & Hips") == ["obliques", "glutes"]
      assert Clip.muscles("Glute Medius & Hip Abductors") == ["glutes"]
    end

    test "nothing said lights nothing" do
      assert Clip.muscles(nil) == []
      assert Clip.muscles("Cardiovascular") == []
    end

    test "each has a name for the page" do
      assert Clip.label("delts") == "Shoulders"
      assert Clip.label("lowback") == "Lower back"
    end
  end

  test "an exercise that has not been filmed has no film" do
    assert Clip.find("push-ups", "Chest") == nil
    assert Clip.unfilmed() == []
  end

  test "filming files a film named by its own bytes, and the page is told how to play it" do
    assert %{filmed: ["push-ups"], current: [], refused: []} = Clip.film()

    assert %{video: "/uploads/figures/push-ups-" <> name, poster: poster} =
             clip = Clip.find("push-ups", "Chest")

    assert name =~ ~r/^[0-9a-f]{12}\.mp4$/
    assert poster == String.replace_suffix(clip.video, ".mp4", ".jpg")
    assert File.read!(Path.join(Clip.dir(), Path.basename(clip.video))) =~ "film of push-ups"
    assert File.exists?(Path.join(Clip.dir(), Path.basename(poster)))

    assert clip.width == 720 and clip.height == 720
    assert clip.seconds == 2.8
    assert clip.stops == [%{name: "top", at: 0.0}, %{name: "bottom", at: 1.5}]
    assert clip.muscles == ["chest"]

    # the camera's scratch folder is gone
    assert Enum.sort(File.ls!(Clip.dir())) ==
             Enum.sort(["clips.json", Path.basename(clip.video), Path.basename(poster)])
  end

  test "what has a current film is not filmed again, unless everything is asked for" do
    Clip.film()
    assert %{filmed: [], current: ["push-ups"]} = Clip.film()
    assert %{filmed: ["push-ups"], current: []} = Clip.film(all: true)
  end

  test "a figure edited since it was filmed loses its film until it is filmed again", %{
    figure: figure
  } do
    Clip.film()
    first = Clip.find("push-ups", "Chest")
    assert Clip.unfilmed() == []

    File.write!(figure, String.replace(File.read!(figure), ~s("hold": 0.3), ~s("hold": 0.4)))

    assert Clip.find("push-ups", "Chest") == nil
    assert Clip.unfilmed() == ["push-ups"]

    System.put_env("STUB_CAMERA_TAKE", "2")
    assert %{filmed: ["push-ups"]} = Clip.film()

    second = Clip.find("push-ups", "Chest")
    assert second.video != first.video
    assert Clip.unfilmed() == []

    # the film it replaces is swept
    refute File.exists?(Path.join(Clip.dir(), Path.basename(first.video)))
    refute File.exists?(Path.join(Clip.dir(), Path.basename(first.poster)))
  end

  test "the film is of the muscles lit when it was shot" do
    Clip.film()
    assert Clip.find("push-ups", "Chest")
    assert Clip.find("push-ups", "Chest and triceps") == nil
  end

  test "a figure that does not draw is refused, as the page refuses it", %{figure: figure} do
    File.write!(figure, ~s({"poses": [{"name": "nowhere"}]}))

    assert %{filmed: [], refused: [{"push-ups", why}]} = Clip.film()
    assert why =~ "pelvis"
    assert Clip.find("push-ups", "Chest") == nil
  end

  test "a camera that fails films nothing and leaves nothing behind" do
    System.put_env("STUB_CAMERA_FAIL", "1")

    assert %{filmed: [], refused: [{"push-ups", why}]} = Clip.film()
    assert why =~ "the browser did not start"
    assert File.ls!(Clip.dir()) == []
  end

  test "a figure can be looked at pose by pose before it is filmed" do
    to = Path.join(Clip.dir(), "../stills")

    assert {:ok, [top, bottom]} = Clip.stills(["push-ups"], to)
    assert Path.basename(top) == "push-ups-0.png"
    assert File.read!(bottom) == "pose 1 of push-ups"
    assert Clip.find("push-ups", "Chest") == nil
  end

  test "the scratch folder of a run that was killed is cleared by the next, once it is old" do
    File.mkdir_p!(Clip.dir())
    killed = Path.join(Clip.dir(), ".filming-1")
    under_way = Path.join(Clip.dir(), ".filming-2")
    File.mkdir_p!(killed)
    File.mkdir_p!(under_way)
    File.touch!(killed, System.os_time(:second) - 7200)

    Clip.film()

    refute File.exists?(killed)
    assert File.exists?(under_way)
  end

  test "films can be made into another folder, which is how the live site's are" do
    elsewhere = Path.join(Clip.dir(), "../live-figures")

    assert %{filmed: ["push-ups"]} = Clip.film(to: elsewhere)
    assert "clips.json" in File.ls!(elsewhere)
    assert Clip.find("push-ups", "Chest") == nil
  end
end
