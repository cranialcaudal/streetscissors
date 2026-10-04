defmodule Web.Backup.Tree do
  @moduledoc """
  Copies a file tree onto the external drive with rsync.

  The negatives archive and the captain's logs' media are both trees that only
  ever grow, and both are copied the same way, so the copying lives here and
  `Web.Backup.Photos` and `Web.Backup.Uploads` each say only what to copy and
  where to.

  **Why rsync and not an Elixir file walk.** rsync already solves incremental
  copying, partial transfers and permissions, and after the first run it moves
  only what changed. Reimplementing that badly for a few hundred files is not a
  good trade.

  **`--delete` is deliberately absent.** A backup that propagates local
  deletions is not a backup — it would faithfully reproduce the accident you
  most want protection from. The mirror accumulates.
  """

  require Logger

  @doc """
  Copies the contents of `source` into `dest`. `opts[:label]` names the tree in
  the log, and `opts[:exclude]` lists rsync patterns to leave behind.

  Returns `{:ok, %{files: n, bytes: n}}` describing the destination, or
  `{:error, {:rsync_failed, code}}`. The caller decides whether `dest` is
  there to write to; this never creates it.
  """
  @spec sync(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def sync(source, dest, opts \\ []) do
    label = Keyword.get(opts, :label, "tree")
    excludes = for pattern <- Keyword.get(opts, :exclude, []), do: "--exclude=#{pattern}"

    # Trailing slash on the source: copy the *contents* of the tree into the
    # destination, rather than nesting its directory inside it on every run.
    args =
      ["-a", "--no-perms", "--no-owner", "--no-group"] ++ excludes ++ [source <> "/", dest <> "/"]

    case System.cmd("rsync", args, stderr_to_stdout: true) do
      {_out, 0} ->
        summary = %{files: count_files(dest), bytes: total_bytes(dest)}
        Logger.info("#{label} backup: #{summary.files} files on #{dest}")
        {:ok, summary}

      {out, code} ->
        Logger.error("#{label} backup: rsync exited #{code}: #{String.trim(out)}")
        {:error, {:rsync_failed, code}}
    end
  end

  @doc "Number of regular files under a directory, at any depth."
  @spec count_files(String.t()) :: non_neg_integer()
  def count_files(dir) do
    dir |> walk() |> Enum.count()
  end

  @doc "Total size in bytes of every regular file under a directory."
  @spec total_bytes(String.t()) :: non_neg_integer()
  def total_bytes(dir) do
    dir
    |> walk()
    |> Enum.reduce(0, fn path, acc ->
      case File.stat(path) do
        {:ok, %{size: size}} -> acc + size
        _ -> acc
      end
    end)
  end

  @doc "Every regular file under a directory, at any depth, as full paths."
  @spec walk(String.t()) :: [String.t()]
  def walk(dir) do
    case File.ls(dir) do
      {:ok, entries} ->
        Enum.flat_map(entries, fn entry ->
          full = Path.join(dir, entry)
          if File.dir?(full), do: walk(full), else: [full]
        end)

      _ ->
        []
    end
  end
end
