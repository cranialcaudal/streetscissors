defmodule Web.Cuts.RenderTest do
  # Renders a real cut with the real ffmpeg, so the filter graph is proved by
  # the program that has to read it, not by a reading of its text. Skipped on
  # a machine without ffmpeg and ImageMagick.
  use ExUnit.Case, async: false

  alias Web.Cuts.{Render, Timeline, Titles}

  @ffmpeg System.find_executable("ffmpeg")
  @ffprobe System.find_executable("ffprobe")
  @magick System.find_executable("magick")

  if @ffmpeg && @ffprobe && @magick do
    setup do
      dir = Path.join(System.tmp_dir!(), "cut_render_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf(dir) end)
      %{dir: dir}
    end

    defp make(args),
      do: {_, 0} = System.cmd(@ffmpeg, ["-hide_banner", "-loglevel", "error", "-y" | args])

    test "a cut of takes, a print, a title and ducked music renders to its length", %{dir: dir} do
      take = Path.join(dir, "take.mp4")
      quiet = Path.join(dir, "quiet.mp4")
      print = Path.join(dir, "print.png")
      music = Path.join(dir, "music.m4a")
      title = Path.join(dir, "t-a.png")

      make(
        ~w(-f lavfi -i testsrc=size=640x360:rate=25:duration=3 -f lavfi -i sine=frequency=440:duration=3 -shortest -c:v libx264 -pix_fmt yuv420p -c:a aac) ++
          [take]
      )

      make(
        ~w(-f lavfi -i testsrc=size=360x640:rate=30:duration=2 -c:v libx264 -pix_fmt yuv420p) ++
          [quiet]
      )

      make(~w(-f lavfi -i testsrc2=size=1200x800 -frames:v 1) ++ [print])
      make(~w(-f lavfi -i sine=frequency=220:duration=8 -c:a aac) ++ [music])
      :ok = Titles.render(%{"text" => "Ferry", "style" => "title"}, title)

      timeline = %{
        "clips" => [
          %{
            "id" => "c-a",
            "kind" => "take",
            "media" => 1,
            "in" => 500,
            "out" => 2_500,
            "gain" => -2.0
          },
          %{
            "id" => "c-b",
            "kind" => "still",
            "frame" => "065/6",
            "duration" => 1_500,
            "move" => "pan-right"
          },
          %{
            "id" => "c-c",
            "kind" => "take",
            "media" => 2,
            "in" => 0,
            "out" => 1_000,
            "gain" => 0.0
          }
        ],
        "titles" => [
          %{
            "id" => "t-a",
            "text" => "Ferry",
            "at" => 200,
            "duration" => 1_500,
            "style" => "title"
          }
        ],
        "sounds" => [
          %{
            "id" => "s-a",
            "media" => 3,
            "at" => 0,
            "in" => 0,
            "out" => 6_000,
            "gain" => -10.0,
            "fade_in" => 300,
            "fade_out" => 500,
            "duck" => true
          }
        ]
      }

      files = %{
        media: %{
          1 => %{path: take, has_audio: true},
          2 => %{path: quiet, has_audio: false},
          3 => %{path: music, has_audio: true}
        },
        stills: %{"065/6" => print},
        titles: %{"t-a" => title}
      }

      layout = Timeline.layout(timeline)
      output = Path.join(dir, "cut.mp4")
      args = Render.args(layout, files, output)

      {said, status} =
        System.cmd(@ffmpeg, ["-hide_banner", "-nostdin", "-y" | args], stderr_to_stdout: true)

      assert status == 0, said

      {json, 0} =
        System.cmd(
          @ffprobe,
          ~w(-v error -print_format json -show_format -show_streams) ++ [output]
        )

      %{"format" => %{"duration" => duration}, "streams" => streams} = Jason.decode!(json)
      assert_in_delta String.to_float(duration), layout.length / 1000, 0.15

      assert %{"width" => 1280, "height" => 720} =
               Enum.find(streams, &(&1["codec_type"] == "video"))

      assert Enum.find(streams, &(&1["codec_type"] == "audio"))
    end
  end
end
