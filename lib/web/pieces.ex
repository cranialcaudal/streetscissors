defmodule Web.Pieces do
  @moduledoc """
  One name for "a piece of work on the site", whichever section it lives in.

  Letters, webmentions and the admin all need to say *which* post, log or
  frame they are about, check that it exists, and link back to it. A piece is
  a short string ref:

    * `"post:<slug>"` — a blog post
    * `"log:<slug>"` — a captain's log (published and transcoded only)
    * `"frame:<roll>/<n>"` — a finished print, roll padded to three digits

  Refs are what get stored, so they are canonical: `frame/2` pads the roll
  the way `/negatives/roll/013` does, and `from_path/1` accepts the same
  aliases the routes do (`13`, `roll013`) and answers the canonical ref.
  """

  alias Web.{Audio, Blog, Negatives}
  alias Web.Audio.Log

  @type ref :: String.t()
  @type piece :: %{
          kind: :post | :log | :frame,
          title: String.t(),
          path: String.t(),
          date: Date.t() | nil
        }

  def post(slug), do: "post:" <> slug
  def log(slug), do: "log:" <> slug
  def frame(roll, n), do: "frame:#{pad(roll)}/#{n}"

  @doc "The piece a ref names, if it exists and is public."
  @spec resolve(ref() | nil) :: {:ok, piece()} | :error
  def resolve("post:" <> slug) do
    case Blog.get_post(slug) do
      {:ok, post} ->
        {:ok, %{kind: :post, title: post.title, path: "/blog/#{post.slug}", date: post.date}}

      _ ->
        :error
    end
  end

  def resolve("log:" <> slug) do
    case Audio.get_ready_log_by_slug(slug) do
      {:ok, log} ->
        {:ok,
         %{kind: :log, title: Log.title(log), path: "/logs/#{log.slug}", date: log.recorded_on}}

      _ ->
        :error
    end
  end

  def resolve("frame:" <> rest) do
    with [roll, n] <- String.split(rest, "/", parts: 2),
         {frame, ""} <- Integer.parse(n),
         true <- Enum.any?(Negatives.list_frames(roll), &(&1.frame == frame)) do
      padded = pad(roll)

      {:ok,
       %{
         kind: :frame,
         title: "Roll #{padded}, frame #{frame}",
         path: "/negatives/roll/#{padded}/frame/#{frame}",
         date: roll_date(roll)
       }}
    else
      _ -> :error
    end
  end

  def resolve(_), do: :error

  @doc """
  The ref for a path on this site — `/blog/<slug>`, `/logs/<slug>`,
  `/negatives/roll/<roll>/frame/<n>` — or `:error`. Only the path is read;
  checking the host is the caller's business.
  """
  @spec from_path(String.t()) :: {:ok, ref()} | :error
  def from_path(path) when is_binary(path) do
    path = path |> String.trim_trailing("/")

    case String.split(path, "/", trim: true) do
      ["blog", slug] -> {:ok, post(slug)}
      ["logs", slug] -> {:ok, log(slug)}
      ["negatives", "roll", roll, "frame", n] -> frame_ref(roll, n)
      _ -> :error
    end
  end

  def from_path(_), do: :error

  defp frame_ref(roll, n) do
    case Integer.parse(n) do
      {frame, ""} -> {:ok, frame(roll, frame)}
      _ -> :error
    end
  end

  defp roll_date(roll) do
    with {num, ""} <- roll |> pad() |> Integer.parse(),
         %{date: date} when is_binary(date) <-
           Enum.find(Negatives.list_contact_sheets(), &(&1.roll_num == num)),
         {:ok, date} <- Date.from_iso8601(date) do
      date
    else
      _ -> nil
    end
  end

  # The same padding /negatives/roll/013 uses (NegativesLive.Format.pad/1).
  defp pad(roll) do
    case Regex.run(~r/\A(?:roll)?0*(\d{1,4})\z/i, to_string(roll)) do
      [_, digits] -> String.pad_leading(digits, 3, "0")
      _ -> to_string(roll)
    end
  end
end
