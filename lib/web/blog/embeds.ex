defmodule Web.Blog.Embeds do
  @moduledoc """
  Expands Obsidian-style `![[...]]` photo embeds in rendered blog HTML.

  Runs after Earmark — the syntax passes through markdown untouched:

    * `![[roll012]]` / `![[12]]` / `![[roll012_2026-07-31_120_bw]]` —
      whole contact sheet: preview image linked to the full-size scan
    * `![[roll012/3]]` — individual frame scan from the roll folder
    * `![[roll012/3|Caption]]` — same, with a caption
    * `![[ride:123]]` — a Komoot ride card (name, stats, thumbnail)
      linking to the ride page; private rides stay literal

  Unresolvable targets (unknown roll/frame/ride, negatives dir missing, or
  ordinary `![[wikilinks]]`) are left as literal text, so posts never
  render broken images. The pattern also matches inside code blocks —
  avoid the syntax there.
  """

  alias Web.Negatives
  alias Web.Rides
  alias Web.Rides.Units

  @embed_re ~r/!\[\[([^\]\|\n]+?)(?:\|([^\]\n]*))?\]\]/
  @ride_re ~r/\Aride:(\d+)\z/
  @frame_re ~r/\A(?:roll)?0*(\d{1,4})\s*\/\s*0*(\d{1,4})\z/
  @sheet_re ~r/\A(?:roll)?0*(\d{1,4})(?:_[\w-]+)?\z/

  def transform(html) do
    Regex.replace(@embed_re, html, fn full, target, caption ->
      target = String.trim(target)

      cond do
        Regex.match?(@ride_re, target) -> ride_html(target, caption, full)
        Regex.match?(@frame_re, target) -> frame_html(target, caption, full)
        Regex.match?(@sheet_re, target) -> sheet_html(target, caption, full)
        true -> full
      end
    end)
  end

  defp ride_html(target, caption, full) do
    [_, id] = Regex.run(@ride_re, target)

    case Rides.get_public_ride(id) do
      nil ->
        full

      ride ->
        thumb =
          if Rides.Thumbs.exists?(ride) do
            ~s(<img src="/fitness/rides/#{ride.id}/thumb" alt="" loading="lazy" />)
          else
            ""
          end

        meta =
          [
            Units.date(ride.started_at),
            Units.distance(ride.distance_m),
            Units.duration(ride.time_in_motion_s || ride.duration_s),
            Units.elevation(ride.ascent_m) <> " ↑"
          ]
          |> Enum.join(" · ")

        inner =
          ~s(<a href="/fitness/rides/#{ride.id}">) <>
            thumb <>
            ~s(<span class="blog-embed-ride-body">) <>
            ~s(<span class="blog-embed-ride-name">#{escape(ride.name || "Untitled ride")}</span>) <>
            ~s(<span class="blog-embed-ride-meta">#{escape(meta)}</span>) <>
            ~s(</span></a>)

        figure(inner, caption, "blog-embed-ride")
    end
  end

  defp frame_html(target, caption, full) do
    [_, roll, frame] = Regex.run(@frame_re, target)

    case Negatives.frame_path(roll, frame) do
      {:ok, _path} ->
        src = "/negatives/frame/roll#{String.pad_leading(roll, 3, "0")}/#{frame}"

        figure(
          ~s(<img src="#{src}" alt="#{alt(caption)}" loading="lazy" />),
          caption,
          "blog-embed-frame"
        )

      :error ->
        full
    end
  end

  defp sheet_html(target, caption, full) do
    case Negatives.sheet_for_roll(target) do
      {:ok, filename} ->
        inner =
          ~s(<a href="/negatives/image/#{filename}">) <>
            ~s(<img src="/negatives/preview/#{filename}" alt="#{alt(caption)}" loading="lazy" /></a>)

        figure(inner, caption, "blog-embed-sheet")

      :error ->
        full
    end
  end

  defp figure(inner, caption, class) do
    caption_html =
      case String.trim(caption) do
        "" -> ""
        text -> "<figcaption>#{escape(text)}</figcaption>"
      end

    ~s(<figure class="blog-embed #{class}">#{inner}#{caption_html}</figure>)
  end

  defp alt(caption) do
    case String.trim(caption) do
      "" -> "photograph"
      text -> escape(text)
    end
  end

  defp escape(text), do: Plug.HTML.html_escape(text)
end
