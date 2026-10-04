defmodule Web.Keywords.Index do
  @moduledoc """
  Where each keyword is used, across both sections, and the one place a
  keyword is changed everywhere at once.

  Keywords live in two kinds of home: a post's frontmatter, in a file, and a
  log's `keywords` column, in the database. `Web.Keywords` makes them one
  vocabulary by normalizing both; this module is what lets that vocabulary be
  *tended* as one. Without it, correcting `nyc` to `new-york` meant opening
  every post and every log that carried it, and the two spellings sat side by
  side on the filter bars until someone did.

  `usage/0` is the admin's view: every post and every log, drafts and
  unpublished entries included, because a rename that skipped them would
  leave the old spelling to resurface the day they are published.

  `rename/2` is also how two keywords are **merged**: renaming one to a name
  already in use folds it into that one, and a piece that carried both keeps
  a single copy, in the place the first of them stood.
  """

  alias Web.Audio
  alias Web.Audio.Log
  alias Web.Blog
  alias Web.Keywords

  @type entry :: %{
          keyword: String.t(),
          posts: [map()],
          logs: [Log.t()],
          count: non_neg_integer()
        }

  @doc """
  Every keyword in use with the posts and logs that carry it, most-used first
  and alphabetical within a tie.
  """
  @spec usage() :: [entry()]
  def usage do
    posts = for post <- Blog.list_all_posts(), keyword <- post.keywords, do: {keyword, post}
    logs = for log <- Audio.list_logs(), keyword <- Log.keyword_list(log), do: {keyword, log}

    by_post = Enum.group_by(posts, &elem(&1, 0), &elem(&1, 1))
    by_log = Enum.group_by(logs, &elem(&1, 0), &elem(&1, 1))

    (Map.keys(by_post) ++ Map.keys(by_log))
    |> Enum.uniq()
    |> Enum.map(fn keyword ->
      posts = Map.get(by_post, keyword, [])
      logs = Map.get(by_log, keyword, [])
      %{keyword: keyword, posts: posts, logs: logs, count: length(posts) + length(logs)}
    end)
    |> Enum.sort_by(&{-&1.count, &1.keyword})
  end

  @doc """
  Keywords carried by exactly one piece. A filter that finds one thing is
  usually a misspelling of a filter that finds several, or a keyword still
  waiting for company.
  """
  @spec singletons([entry()]) :: [entry()]
  def singletons(usage \\ usage()), do: Enum.filter(usage, &(&1.count == 1))

  @doc """
  Renames `from` to `to` in every post and log that carries it, or merges it
  into `to` when that keyword already exists.

  Both names are normalized first, so `"New York"` renames to `new-york`.
  Returns `{:ok, %{keyword: to, posts: n, logs: n, merged: boolean}}`, or
  `{:error, :blank}` for a name that normalizes to nothing, `{:error, :same}`
  when the two are one keyword, and `{:error, :unknown}` when nothing carries
  `from`.
  """
  @spec rename(String.t(), String.t()) :: {:ok, map()} | {:error, :blank | :same | :unknown}
  def rename(from, to) do
    from = Keywords.normalize(from)
    to = Keywords.normalize(to)
    usage = usage()

    cond do
      from == "" or to == "" ->
        {:error, :blank}

      from == to ->
        {:error, :same}

      true ->
        case Enum.find(usage, &(&1.keyword == from)) do
          nil ->
            {:error, :unknown}

          %{posts: posts, logs: logs} ->
            for post <- posts, do: Blog.set_keywords(post.slug, swap(post.keywords, from, to))

            for log <- logs do
              keywords = log |> Log.keyword_list() |> swap(from, to) |> Keywords.format()
              Audio.update_log(log, %{keywords: keywords})
            end

            {:ok,
             %{
               keyword: to,
               posts: length(posts),
               logs: length(logs),
               merged: Enum.any?(usage, &(&1.keyword == to))
             }}
        end
    end
  end

  # `to` takes the place `from` stood in; a piece that already had `to` keeps
  # whichever of the two came first.
  defp swap(keywords, from, to) do
    keywords
    |> Enum.map(&if(&1 == from, do: to, else: &1))
    |> Enum.uniq()
  end
end
