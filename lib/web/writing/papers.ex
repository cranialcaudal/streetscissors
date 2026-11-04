defmodule Web.Writing.Papers do
  @moduledoc """
  The pieces of writing that are not blog posts (papers, reviews, grants), as markdown files in one folder, never published.

  The folder is `Web.Writing.papers_path/0`. A paper is a file like a post,
  with the same outline, reading list and citations; its frontmatter holds
  its project settings (`Web.Writing.Document`). Saving is
  `Web.SourceFile.write/4`, which refuses to write over a file that changed
  on disk since it was opened; a save forced over one keeps the replaced
  version in the vault's `.trash/`.

  Implements the store the workbench reads and writes through
  (`read_source/1`, `write_source/4`, `preview/2`, `to_html/1`), as
  `Web.Blog` does for posts.
  """

  alias Web.SourceFile
  alias Web.Writing.{Document, Outline}

  @doc "Every paper, without its text, newest first by date then file time."
  def list do
    path = Web.Writing.papers_path()

    if File.dir?(path) do
      path
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".md"))
      |> Enum.map(fn file ->
        full = Path.join(path, file)
        mtime = full |> File.stat!() |> Map.fetch!(:mtime) |> NaiveDateTime.from_erl!()

        Path.basename(file, ".md")
        |> Document.build(File.read!(full), mtime)
        |> Map.drop([:body, :raw_body])
      end)
      |> Enum.sort_by(&{&1.date, &1.mtime}, :desc)
    else
      []
    end
  end

  @doc "A paper's file as it is on disk: `{:ok, %{content, revision}}` or `{:error, :not_found}`."
  def read_source(slug) do
    with {:ok, path} <- resolve(slug) do
      content = File.read!(path)
      {:ok, %{content: content, revision: SourceFile.revision(content)}}
    end
  end

  @doc "Saves a paper over the revision it was opened at (see `Web.Blog.write_source/4`)."
  def write_source(slug, content, revision, opts \\ []) do
    with {:ok, path} <- resolve(slug) do
      trash = Path.join(Path.dirname(Web.Writing.papers_path()), ".trash")

      SourceFile.write(
        path,
        content,
        revision,
        Keyword.merge(opts, trash: trash, trash_name: slug)
      )
    end
  end

  @doc "The paper `text` would be, saved under `slug` (`Web.Writing.Document.build/3`)."
  def preview(slug, text), do: Document.build(slug, text)

  @doc "A paper's body as the preview shows it."
  def to_html(body), do: Web.Markdown.to_html(body)

  @doc "Where a paper's file is, for its export's `csl:` lookup."
  def dir, do: Web.Writing.papers_path()

  @doc """
  Starts a paper titled `title` from the skeleton of `kind`
  (`Web.Writing.kinds/0`). Returns `{:ok, slug}`, `{:error, :exists}` or
  `{:error, :blank}`.
  """
  def create(title, kind \\ "essay", today \\ Web.Clock.local_today()) do
    title = String.trim(to_string(title))
    slug = Web.Keywords.slugify(title)

    cond do
      slug == "" ->
        {:error, :blank}

      true ->
        frontmatter =
          [
            "---",
            ~s(title: "#{String.replace(title, "\"", "'")}"),
            "author: ",
            ~s(date: "#{Date.to_iso8601(today)}"),
            "kind: #{kind}",
            "zotero: ",
            "csl: ",
            "---"
          ]
          |> Enum.join("\n")

        write_new(slug, frontmatter <> "\n\n" <> Web.Writing.skeleton(kind))
    end
  end

  @doc "Starts a paper from a pasted markdown blueprint (`Web.Writing.Outline.from_blueprint/2`)."
  def create_from_blueprint(blueprint, today \\ Web.Clock.local_today()) do
    with {:ok, %{slug: slug, content: content}} <- Outline.from_blueprint(blueprint, today) do
      # A paper is never published: the blueprint's draft line means nothing here.
      write_new(slug, String.replace(content, ~r/^draft: true\n/m, ""))
    end
  end

  defp write_new(slug, content) do
    path = Path.join(Web.Writing.papers_path(), slug <> ".md")

    if File.exists?(path) do
      {:error, :exists}
    else
      File.mkdir_p!(Path.dirname(path))

      with :ok <- SourceFile.write_atomic(path, content) do
        {:ok, slug}
      end
    end
  end

  defp resolve(slug) do
    with {:ok, rel} <- Path.safe_relative(to_string(slug) <> ".md"),
         path = Path.join(Web.Writing.papers_path(), rel),
         true <- File.regular?(path) do
      {:ok, path}
    else
      _ -> {:error, :not_found}
    end
  end
end
