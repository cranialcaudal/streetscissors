defmodule Web.BlogCoverTest do
  # The negatives fixtures (config/test.exs) hold roll 001 with its sheet and
  # frame 1 printed, and roll 002 with frame 3 printed and no sheet.
  use ExUnit.Case, async: true

  alias Web.Blog

  defp cover(image, body), do: Blog.cover(%{image: image, body: body})

  describe "cover/1, from the post's image: line" do
    test "a frame, written either way" do
      for ref <- ["001/1", "roll001/1", "frame:001/1"] do
        assert %{url: "/negatives/frame/roll001/1?w=960", alt: "Roll 001, frame 1"} =
                 cover(ref, "")
      end
    end

    test "a roll is its contact sheet" do
      assert %{url: "/negatives/preview/roll001_2026-01-01_120_bw.png" <> _, srcset: srcset} =
               cover("roll001", "")

      assert srcset =~ "480w"
    end

    test "an uploaded image, as it is" do
      assert %{url: "/uploads/images/gull.jpg", srcset: nil} =
               cover("/uploads/images/gull.jpg", "")
    end

    test "it wins over what the body embeds" do
      assert %{alt: "Roll 001, frame 1"} = cover("001/1", "![[002/3]]")
    end
  end

  describe "cover/1, without one" do
    test "the first frame or sheet the post embeds, with its caption as the words" do
      assert %{url: "/negatives/frame/roll002/3?w=960", alt: "Low tide"} =
               cover(nil, "Words.\n\n![[roll002/3|Low tide]]\n\n![[roll001]]")
    end

    test "an embed naming nothing, a ride or a figure is passed over" do
      body = "![[roll999/1]] ![[ride:12]] ![[figure:emissions]] ![[roll001]]"

      assert %{url: "/negatives/preview/roll001_" <> _, alt: "Roll 001, the contact sheet"} =
               cover(nil, body)
    end

    test "else the first uploaded image" do
      assert %{url: "/uploads/images/gull.jpg", alt: "A gull"} =
               cover(nil, "Text ![A gull](/uploads/images/gull.jpg) and more.")
    end

    test "else nothing, and the card sets the title" do
      assert cover(nil, "Only words, and a [link](/blog/x).") == nil
      assert cover(nil, "![[roll999/1]]") == nil
    end
  end
end
