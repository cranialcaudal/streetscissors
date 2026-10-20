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

  **Cross-links** are refs too: a post's `related:` frontmatter
  (`refs/1`) and a log's `post_ref`. `related_to/1` answers the other way:
  what names a piece.
  """

  alias Web.{Blog, Logs, Negatives}
  alias Web.Logs.Log

  @type ref :: String.t()
  @type piece :: %{
          kind: :post | :log | :frame,
          title: String.t(),
          path: String.t(),
          date: Date.t() | nil,
          image: String.t() | nil
        }

  def post(slug), do: "post:" <> slug
  def log(slug), do: "log:" <> slug
  def frame(roll, n), do: "frame:#{pad(roll)}/#{n}"

  @doc "The piece a ref names, if it exists and is public."
  @spec resolve(ref() | nil) :: {:ok, piece()} | :error
  def resolve("post:" <> slug) do
    case Blog.get_post(slug) do
      {:ok, post} ->
        {:ok,
         %{kind: :post, title: post.title, path: "/blog/#{post.slug}", date: post.date, image: nil}}

      _ ->
        :error
    end
  end

  def resolve("log:" <> slug) do
    case Logs.get_ready_log_by_slug(slug) do
      {:ok, log} ->
        {:ok,
         %{
           kind: :log,
           title: Log.title(log),
           path: "/logs/#{log.slug}",
           date: log.recorded_on,
           image: nil
         }}

      _ ->
        :error
    end
  end

  def resolve("frame:" <> rest) do
    with [roll, n] <- String.split(rest, "/", parts: 2),
         {frame, ""} <- Integer.parse(n),
         %{url: url} <- Enum.find(Negatives.list_frames(roll), &(&1.frame == frame)) do
      padded = pad(roll)

      {:ok,
       %{
         kind: :frame,
         title: "Roll #{padded}, frame #{frame}",
         path: "/negatives/roll/#{padded}/frame/#{frame}",
         date: roll_date(roll),
         image: url
       }}
    else
      _ -> :error
    end
  end

  def resolve(_), do: :error

  @doc """
  The refs a post's `related:` line names, canonical and in order:
  `"frame:12/3, log:2026-09-18"` (or a list) to `["frame:012/3",
  "log:2026-09-18"]`. Anything that is not a ref is left out.
  """
  def refs(nil), do: []
  def refs(list) when is_list(list), do: list |> Enum.flat_map(&refs/1) |> Enum.uniq()

  def refs(text) when is_binary(text) do
    text
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.flat_map(fn
      "frame:" <> rest ->
        case String.split(rest, "/", parts: 2) do
          [roll, n] -> with({:ok, ref} <- frame_ref(roll, n), do: [ref], else: (_ -> []))
          _ -> []
        end

      "post:" <> slug when slug != "" ->
        [post(slug)]

      "log:" <> slug when slug != "" ->
        [log(slug)]

      _ ->
        []
    end)
    |> Enum.uniq()
  end

  @doc """
  What names `ref`, the other way round from `refs/1`: the published posts
  whose `related:` lists it, and the published logs whose `post_ref` is it.
  `%{posts: [piece], logs: [piece]}`.
  """
  def related_to(ref) do
    posts =
      for post <- Blog.list_posts(), ref in Map.get(post, :related, []) do
        %{kind: :post, title: post.title, path: "/blog/#{post.slug}", date: post.date, image: nil}
      end

    logs =
      for log <- Logs.list_logs_for_post(ref) do
        %{kind: :log, title: Log.title(log), path: "/logs/#{log.slug}", date: log.recorded_on, image: nil}
      end

    %{posts: posts, logs: logs}
  end

  @doc "Each ref resolved, the ones that exist and are public, in order."
  def resolve_all(refs) do
    for ref <- refs, {:ok, piece} <- [resolve(ref)], do: piece
  end

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

  defp pad(roll), do: Web.Negatives.Roll.pad(roll)
end
