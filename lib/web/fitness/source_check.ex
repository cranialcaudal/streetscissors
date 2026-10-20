defmodule Web.Fitness.SourceCheck do
  @moduledoc """
  The fitness vault's hand-written files that the admin edits whole
  (`/admin/fitness?tab=files`): `week.md`, each block in `blocks/`, and
  `changelog.md`. Each is read by its own lenient parser, which skips what it
  cannot read; `check/2` runs that parser on the editor's text *before* it is
  saved and says what it found, or what it would have skipped, so a typo
  cannot quietly drop a block or a training day.
  """

  alias Web.Fitness.{Block, Changelog, Vault, Week}

  @doc "The files on offer: `[%{id, label, path}]`, blocks by name."
  def files do
    base = Vault.base_path()

    blocks =
      Path.join([base, "blocks", "*.md"])
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.map(fn path ->
        slug = Path.basename(path, ".md")
        %{id: "block:" <> slug, label: "Block: " <> slug, path: path}
      end)

    [%{id: "week", label: "The week (week.md)", path: Path.join(base, "week.md")}] ++
      blocks ++
      [%{id: "changelog", label: "Changelog (changelog.md)", path: Changelog.path()}]
  end

  @doc "The file with this id, or nil (an id from the browser is checked here)."
  def file(id), do: Enum.find(files(), &(&1.id == id))

  @doc """
  What `text` reads as, for the file `id`: `{:ok, summary}` or
  `{:error, reason}`, both in words.
  """
  def check("week", text) do
    week = Week.parse(text)
    blocks = Enum.sum(Enum.map(week.days, &length(&1.blocks)))
    skipped = Enum.reject(block_lines(text), &block?/1)

    cond do
      week.days == [] ->
        {:error, "no days: each day starts with a heading like “## Monday”"}

      skipped != [] ->
        {:error,
         "#{length(skipped)} line(s) are not read as blocks, first “#{hd(skipped)}”. " <>
           "A block reads “- 07:15-08:00 strength Lower day”."}

      true ->
        {:ok, "#{length(week.days)} days, #{blocks} blocks"}
    end
  end

  def check("changelog", text) do
    headings = Regex.scan(~r/^##\s.*$/mu, text) |> length()
    entries = Changelog.parse(text)

    cond do
      headings > length(entries) ->
        {:error,
         "#{headings - length(entries)} heading(s) are not read as entries. " <>
           "An entry's heading reads “## 2026-10-20 — What changed”."}

      true ->
        {:ok, "#{length(entries)} entries"}
    end
  end

  def check("block:" <> _slug, text) do
    meta = Vault.parse_frontmatter_text(text)

    case Block.validate(meta) do
      :ok -> {:ok, "#{meta["title"]}: #{meta["weeks"]} weeks from #{meta["start"]}"}
      {:error, reason} -> {:error, reason}
    end
  end

  def check(_id, _text), do: {:error, "not a file this editor knows"}

  # The lines under a day heading that look meant as blocks ("- …").
  defp block_lines(text) do
    text
    |> Web.Frontmatter.strip()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.drop_while(&(not String.starts_with?(&1, "## ")))
    |> Enum.filter(&String.starts_with?(&1, "- "))
  end

  defp block?(line) do
    case Week.parse("## Day\n" <> line).days do
      [%{blocks: [_]}] -> true
      _ -> false
    end
  end
end
