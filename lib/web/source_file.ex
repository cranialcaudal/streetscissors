defmodule Web.SourceFile do
  @moduledoc """
  Writing a file the author also edits by hand (the vault is open in
  Obsidian), without ever losing either edit.

  * **A revision** is the SHA-256 of a file's text (`revision/1`). An editor
    keeps the revision it opened, and `write/4` refuses to save over a file
    whose revision has moved on since: `{:error, :conflict, %{content,
    revision}}` with what is on disk now, for the author to choose.
  * **`force: true`** saves anyway, first copying the version it replaces into
    `trash` (the vault's `.trash/`, where Obsidian keeps what it deletes).
  * **Every write is atomic** (`write_atomic/2`): beside the file, then
    renamed over it, so nothing reading at that moment (Obsidian, a request)
    sees half a file.

  `Web.Blog` saves posts through this, and the fitness vault's files
  (`Web.Fitness.Vault`, the admin's Week, Blocks and Changelog editors) do too.
  """

  @doc "A text's revision: the lowercase hex SHA-256."
  def revision(content), do: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)

  @doc """
  A file's text and revision: `{:ok, %{content, revision}}`, or the read's
  error. A missing file reads as empty, so a new file can be written over
  revision `revision("")`.
  """
  def read(path) do
    case File.read(path) do
      {:ok, content} -> {:ok, %{content: content, revision: revision(content)}}
      {:error, :enoent} -> {:ok, %{content: "", revision: revision("")}}
      error -> error
    end
  end

  @doc """
  Saves `content` to `path`, but only over `revision`. Returns `{:ok,
  new_revision}`, `{:error, :conflict, %{content, revision}}`, or a write's
  error. Options: `force: true` (save anyway, keeping the replaced text in
  `:trash`, a directory), `trash_name` (the kept copy's name, without its
  timestamp).
  """
  def write(path, content, revision, opts \\ []) do
    {:ok, %{content: on_disk, revision: current}} = read(path)

    cond do
      current == revision ->
        save(path, content)

      Keyword.get(opts, :force, false) ->
        keep(on_disk, opts[:trash], opts[:trash_name] || Path.basename(path, Path.extname(path)))
        save(path, content)

      true ->
        {:error, :conflict, %{content: on_disk, revision: current}}
    end
  end

  defp save(path, content) do
    with :ok <- write_atomic(path, content), do: {:ok, revision(content)}
  end

  @doc "Writes beside `path` and renames over it."
  def write_atomic(path, content) do
    tmp = path <> ".saving"

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(tmp, content),
         :ok <- File.rename(tmp, path) do
      :ok
    else
      error ->
        File.rm(tmp)
        error
    end
  end

  defp keep(_content, nil, _name), do: :ok
  defp keep("", _trash, _name), do: :ok

  defp keep(content, trash, name) do
    stamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d-%H%M%S")
    File.mkdir_p!(trash)
    File.write!(Path.join(trash, "#{name} (replaced #{stamp}).md"), content)
  end
end
