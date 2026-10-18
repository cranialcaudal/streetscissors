defmodule Web.Cuts.TimelineTest do
  use ExUnit.Case, async: true

  alias Web.Cuts.{Render, Timeline}

  @take %{id: 1, kind: "video", status: "ready", duration_ms: 10_000, has_audio: true}
  @song %{id: 2, kind: "audio", status: "ready", duration_ms: 60_000, has_audio: true}
  @busy %{id: 3, kind: "video", status: "processing", duration_ms: nil, has_audio: false}
  @media %{1 => @take, 2 => @song, 3 => @busy}

  describe "normalize/2" do
    test "drops what refers to nothing, and holds every number to its range" do
      timeline = %{
        "clips" => [
          %{
            "id" => "c-one",
            "kind" => "take",
            "media" => 1,
            "in" => -50,
            "out" => 99_999,
            "gain" => 40
          },
          %{"kind" => "take", "media" => 3, "in" => 0, "out" => 1000},
          %{"kind" => "take", "media" => 2, "in" => 0, "out" => 1000},
          %{"kind" => "still", "frame" => "065/6", "duration" => 10, "move" => "spin"},
          %{"kind" => "still", "frame" => "../../etc", "duration" => 1000}
        ],
        "titles" => [
          %{"text" => "   "},
          %{"text" => String.duplicate("a", 200), "at" => -5, "style" => "huge"}
        ],
        "sounds" => [
          %{"media" => "2", "in" => 0, "out" => 70_000, "fade_in" => 99_999, "duck" => "true"}
        ]
      }

      result = Timeline.normalize(timeline, @media)

      assert [take, still] = result["clips"]
      assert %{"id" => "c-one", "in" => 0, "out" => 10_000, "gain" => 12.0} = take
      assert %{"duration" => 500, "move" => "in"} = still
      assert [%{"at" => 0, "style" => "title", "text" => text}] = result["titles"]
      assert String.length(text) == 120

      assert [%{"media" => 2, "out" => 60_000, "fade_in" => 10_000, "duck" => true}] =
               result["sounds"]
    end

    test "a take's in point never passes its out point" do
      clip = %{"kind" => "take", "media" => 1, "in" => 9_990, "out" => 50}

      assert [%{"in" => 9_900, "out" => 10_000}] =
               Timeline.normalize(%{"clips" => [clip]}, @media)["clips"]
    end

    test "a timeline with no tracks lays out as nothing" do
      assert %{clips: [], titles: [], sounds: [], length: 0} = Timeline.layout(%{})
    end

    test "anything else is an empty timeline" do
      assert Timeline.normalize("rubbish", @media) == Timeline.empty()
      assert Timeline.normalize(%{"clips" => "x"}, @media) == Timeline.empty()
    end
  end

  describe "editing" do
    setup do
      timeline =
        Timeline.empty()
        |> Timeline.add_take(%{id: 1, duration_ms: 10_000})
        |> Timeline.add_still("065/6")
        |> Timeline.add_title(2_000)
        |> Timeline.add_sound(%{id: 2, duration_ms: 60_000}, 0)

      %{timeline: timeline}
    end

    test "clips play one after another, and the cut is as long as they are", %{timeline: t} do
      layout = Timeline.layout(t)

      assert [%{"start" => 0, "length" => 10_000}, %{"start" => 10_000, "length" => 4_000}] =
               layout.clips

      assert layout.length == 14_000
    end

    test "a clip is cut in two at the playhead, and nothing moves", %{timeline: t} do
      split = Timeline.split(t, 4_000)

      assert [
               %{"in" => 0, "out" => 4_000},
               %{"in" => 4_000, "out" => 10_000},
               %{"kind" => "still"}
             ] = split["clips"]

      assert Timeline.layout(split).length == 14_000

      assert Timeline.split(t, 12_000)["clips"] |> Enum.map(&Timeline.length_of/1) == [
               10_000,
               2_000,
               2_000
             ]

      # Too near an end, or off the cut: nothing happens.
      assert Timeline.split(t, 50) == t
      assert Timeline.split(t, 20_000) == t
    end

    test "moving a clip moves the others along; taking one out closes the gap", %{timeline: t} do
      [take, still] = t["clips"]
      assert Timeline.move(t, still["id"], 0)["clips"] == [still, take]

      shorter = Timeline.remove(t, take["id"])
      assert [%{"start" => 0}] = Timeline.layout(shorter).clips
    end

    test "an item is found on its track and changed in place", %{timeline: t} do
      [title] = t["titles"]
      changed = Timeline.update(t, title["id"], %{"text" => "Ferry"})
      assert Timeline.find(changed, title["id"])["text"] == "Ferry"
    end
  end

  describe "the render" do
    @files %{
      media: %{
        1 => %{path: "/bin/m1.mov", has_audio: true},
        4 => %{path: "/bin/m4.mp4", has_audio: false},
        2 => %{path: "/bin/m2.mp3", has_audio: true}
      },
      stills: %{"065/6" => "/archive/065/frames/06.png"},
      titles: %{"t-a" => "/work/t-a.png"}
    }

    defp layout(clips, titles \\ [], sounds \\ []) do
      Timeline.layout(%{"clips" => clips, "titles" => titles, "sounds" => sounds})
    end

    defp graph(args) do
      [_, graph] = Enum.drop_while(args, &(&1 != "-filter_complex")) |> Enum.take(2)
      graph
    end

    test "each clip is read for its length and joined; the film is 720p at 30" do
      clips = [
        %{
          "id" => "c-a",
          "kind" => "take",
          "media" => 1,
          "in" => 1_500,
          "out" => 4_000,
          "gain" => -3.0
        },
        %{
          "id" => "c-b",
          "kind" => "still",
          "frame" => "065/6",
          "duration" => 2_000,
          "move" => "in"
        },
        %{"id" => "c-c", "kind" => "take", "media" => 4, "in" => 0, "out" => 1_000, "gain" => 0.0}
      ]

      args = Render.args(layout(clips), @files, "/out/cut.mp4")

      assert Enum.take(args, 6) == ["-ss", "1.500", "-t", "2.500", "-i", "/bin/m1.mov"]
      assert ["-i", "/archive/065/frames/06.png"] -- args == []
      assert List.last(args) == "/out/cut.mp4"
      assert ["-t", "5.500"] -- args == []

      graph = graph(args)
      assert graph =~ "[0:a]aresample=48000"
      assert graph =~ "volume=-3.000dB"
      # A still is moved by zoompan over its 60 frames, scaled up first.
      assert graph =~ "scale=2560:1440,zoompan=z='1+0.12*on/60'"
      # A take with no sound and a still each get silence of their length.
      assert graph =~ "atrim=duration=2.000[a1]"
      assert graph =~ "atrim=duration=1.000[a2]"
      assert graph =~ "[v0][a0][v1][a1][v2][a2]concat=n=3:v=1:a=1[vc][ac]"
      assert graph =~ "[vc]null[vout]"
      assert graph =~ "[ac]anull[aout]"
    end

    test "titles are laid over in their time, and ducked sounds drop under speech" do
      clips = [
        %{
          "id" => "c-a",
          "kind" => "take",
          "media" => 1,
          "in" => 0,
          "out" => 10_000,
          "gain" => 0.0
        }
      ]

      titles = [
        %{
          "id" => "t-a",
          "text" => "Ferry",
          "at" => 1_000,
          "duration" => 3_000,
          "style" => "title"
        }
      ]

      sounds = [
        %{
          "id" => "s-a",
          "media" => 2,
          "at" => 500,
          "in" => 0,
          "out" => 8_000,
          "gain" => -12.0,
          "fade_in" => 0,
          "fade_out" => 1_000,
          "duck" => true
        },
        %{
          "id" => "s-b",
          "media" => 2,
          "at" => 0,
          "in" => 0,
          "out" => 2_000,
          "gain" => 0.0,
          "fade_in" => 0,
          "fade_out" => 0,
          "duck" => false
        }
      ]

      args = Render.args(layout(clips, titles, sounds), @files, "/out/cut.mp4")
      graph = graph(args)

      assert ["-loop", "1", "-framerate", "30", "-t", "10.000", "-i", "/work/t-a.png"] -- args ==
               []

      assert graph =~ "fade=t=in:st=1.000:d=0.400:alpha=1"
      assert graph =~ "[vc][t0]overlay=0:0:enable='between(t,1.000,4.000)'[vout]"
      assert graph =~ "adelay=500:all=1[s0]"
      assert graph =~ "afade=t=out:st=7.000:d=1.000"
      assert graph =~ "[ac]asplit=2[voice][key]"
      assert graph =~ "[s0]anull[bus]"
      assert graph =~ "[bus][key]sidechaincompress"
      assert graph =~ "[voice][ducked][s1]amix=inputs=3:normalize=0:duration=first[mixed]"
      assert graph =~ "[mixed]atrim=duration=10.000[aout]"
    end
  end
end
