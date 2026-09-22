defmodule Web.Media.FFmpegTest do
  use ExUnit.Case, async: true

  alias Web.Media.FFmpeg

  describe "video_args/3" do
    test "pins 30 fps, so a 1 ms-timebase recording is not padded out to 1000" do
      args = FFmpeg.video_args("in.webm", "/out", audio?: true)

      [filter] = for {"-vf", f} <- Enum.zip(args, tl(args)), do: f
      assert filter =~ ~r/^fps=30,scale=/

      # A level every H.264 decoder handles, stated rather than guessed from a frame rate.
      assert "-level:v" in args
      assert Enum.at(args, Enum.find_index(args, &(&1 == "-level:v")) + 1) == "4.0"
      assert Enum.at(args, Enum.find_index(args, &(&1 == "-g")) + 1) == "60"
    end

    test "writes one faststart MP4 into the entry directory" do
      args = FFmpeg.video_args("in.webm", "/out", audio?: true)

      assert Enum.at(args, Enum.find_index(args, &(&1 == "-movflags")) + 1) == "+faststart"
      assert List.last(args) == "/out/video.mp4"
      refute "-var_stream_map" in args
      refute "hls" in args
    end

    test "maps and encodes audio only when the source has some" do
      with_audio = FFmpeg.video_args("in.webm", "/out", audio?: true)
      without = FFmpeg.video_args("in.webm", "/out", audio?: false)

      assert "0:a:0" in with_audio and "aac" in with_audio
      refute "0:a:0" in without
      refute "aac" in without
    end

    test "trims before the input, as a start and a duration" do
      args = FFmpeg.video_args("in.webm", "/out", trim_start: 1.5, trim_duration: 9.0)

      assert Enum.take(args, 6) == ["-ss", "1.500", "-t", "9.000", "-i", "in.webm"]
    end
  end
end
