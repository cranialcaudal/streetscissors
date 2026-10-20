defmodule Web.Blog.Cache do
  @moduledoc """
  Each post as `Web.Blog` last parsed it, so a page that lists posts (the
  index, search and its suggestions, the feed, the sitemap, the daybook, a
  post's neighbours and related pieces) stats the folder instead of reading
  and parsing every file again.

  An ETS table of `{path, stamp, post}`. The stamp is the file's mtime, size
  and inode: an edit in Obsidian moves the first two, and every save through
  the site is written beside and renamed over (`Web.SourceFile`), which moves
  the inode, so nothing needs telling. A missing table (a mix task, say) just
  means no cache.
  """

  use GenServer

  @table :blog_posts

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, nil}
  end

  @doc "The post cached for `path` at `stamp`, else `build.()`'s, kept for next time."
  def fetch(path, stamp, build) do
    case table() do
      nil ->
        build.()

      table ->
        case :ets.lookup(table, path) do
          [{^path, ^stamp, post}] ->
            post

          _ ->
            post = build.()
            :ets.insert(table, {path, stamp, post})
            post
        end
    end
  end

  @doc "Forgets everything (tests that rewrite fixtures in place)."
  def clear do
    if t = table(), do: :ets.delete_all_objects(t)
    :ok
  end

  defp table do
    case :ets.whereis(@table) do
      :undefined -> nil
      ref -> ref
    end
  end
end
