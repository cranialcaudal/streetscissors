defmodule Web.Writing.Export do
  @moduledoc """
  A piece of writing out through Pandoc as Word, PDF, LaTeX or Pandoc markdown, its citations formatted by citeproc.

  **What goes in** is the prose as `Web.Writing.Outline.strip/1` leaves it
  (no reading list, beats or thoughts), with `[@key]` citations left for
  Pandoc to format, and Obsidian's wiki links reduced to their words and its
  embeds left out. Images under `/uploads/` are read from the uploads root.

  **The bibliography** is CSL JSON for the keys cited: from the piece's
  Zotero folder (`zotero:` in its frontmatter) when Zotero is configured, so
  volume, pages and DOI come out exact; else from the reading-list lines
  (`Web.Writing.Citations.csl_items/3`).

  **The style** is `csl:` in the frontmatter, a `.csl` file beside the piece
  or in the styles folder (`config :web, :csl_path`, default `styles/` beside
  the blog folder in the vault). Without one, Pandoc's own Chicago
  author-date.

  **The title page** reads `title`, `subtitle`, `author`, `affiliation`,
  `date` and `abstract` from the frontmatter.

  Pandoc is `config :web, :pandoc` if set, else the `pandoc` on the `PATH`
  (`~/.local/bin` for the service). A PDF is made with xelatex.
  """

  alias Web.Writing.{Citations, Document, Outline, Zotero}

  @formats %{
    "docx" => %{
      ext: "docx",
      mime: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
      label: "Word"
    },
    "pdf" => %{ext: "pdf", mime: "application/pdf", label: "PDF"},
    "tex" => %{ext: "tex", mime: "application/x-tex", label: "LaTeX"},
    "md" => %{ext: "md", mime: "text/markdown", label: "Pandoc markdown"}
  }

  @timeout 120_000

  @doc "The formats, as `{format, label}`, in the order the workbench offers them."
  def formats, do: Enum.map(~w(docx pdf tex md), &{&1, @formats[&1].label})

  @doc "The MIME type a format downloads as."
  def mime(format), do: @formats |> Map.fetch!(format) |> Map.fetch!(:mime)

  @doc "Whether Pandoc can be found."
  def available?, do: pandoc() != nil

  @doc """
  Exports `text` (a piece's whole file, frontmatter included) as `format`.
  `dir` is the piece's folder, where a `csl:` file named relatively is looked
  for. Returns `{:ok, binary, filename}` or `{:error, reason}`, where reason
  is `:no_pandoc`, `:unknown_format` or `{:pandoc, message}`.
  """
  def export(text, slug, format, dir \\ nil) when is_binary(text) and is_binary(slug) do
    cond do
      not Map.has_key?(@formats, format) -> {:error, :unknown_format}
      is_nil(pandoc()) -> {:error, :no_pandoc}
      true -> run(text, slug, format, dir)
    end
  end

  defp run(text, slug, format, dir) do
    {meta, raw_body} = Document.split(text)
    outline = Outline.analyze(raw_body, meta)
    prose = raw_body |> Outline.strip() |> for_pandoc()
    cited = prose |> Citations.citations() |> Enum.map(& &1.key) |> Enum.uniq()
    csl = Citations.csl_items(outline.research.items, cited, zotero_csl(meta))

    work = Path.join(System.tmp_dir!(), "writing-export-#{System.unique_integer([:positive])}")
    File.mkdir_p!(work)

    try do
      File.write!(Path.join(work, "in.md"), prose)
      File.write!(Path.join(work, "refs.json"), Jason.encode!(csl))
      File.write!(Path.join(work, "meta.json"), Jason.encode!(metadata(meta, slug, csl != [])))
      out = Path.join(work, "out." <> @formats[format].ext)

      args =
        ["in.md", "--from", "markdown", "--standalone", "--metadata-file", "meta.json", "-o", out] ++
          if(csl != [], do: ["--citeproc", "--bibliography", "refs.json"], else: []) ++
          style_args(meta, dir) ++
          resource_args() ++
          if(format == "pdf", do: ["--pdf-engine", "xelatex"], else: []) ++
          if(format == "md", do: ["--to", "markdown"], else: [])

      task = Task.async(fn -> System.cmd(pandoc(), args, cd: work, stderr_to_stdout: true) end)

      case Task.yield(task, @timeout) || Task.shutdown(task, :brutal_kill) do
        {:ok, {_output, 0}} -> {:ok, File.read!(out), "#{slug}.#{@formats[format].ext}"}
        {:ok, {output, _}} -> {:error, {:pandoc, String.slice(output, -2000, 2000)}}
        nil -> {:error, {:pandoc, "Pandoc took longer than #{div(@timeout, 1000)} s."}}
      end
    after
      File.rm_rf(work)
    end
  end

  @doc """
  The prose as Pandoc should read it: embeds (`![[roll012/3]]`) left out,
  wiki links (`[[slug|Name]]`, `[[slug]]`) as their words, `/uploads/`
  pictures as files.
  """
  def for_pandoc(prose) when is_binary(prose) do
    uploads = Web.Uploads.root()

    prose
    |> String.replace(~r/!\[\[[^\]\n]*\]\]/, "")
    |> String.replace(~r/\[\[(?:[^\]|\n]*\|)?([^\]\n]*)\]\]/, "\\1")
    |> String.replace(~r/\]\(\/uploads\//, "](" <> Path.join(uploads, "") <> "/")
  end

  defp metadata(meta, slug, refs?) do
    title = meta["title"] || slug

    %{
      "title" => title,
      "subtitle" => meta["subtitle"],
      "author" => split_list(meta["author"]),
      "institute" => meta["affiliation"],
      "date" => meta["date"],
      "abstract" => meta["abstract"],
      "lang" => meta["lang"] || "en-US",
      "link-citations" => true,
      "reference-section-title" => if(refs?, do: meta["references_title"] || "References"),
      "geometry" => "margin=1in",
      "fontsize" => "12pt",
      "linestretch" => meta["linestretch"]
    }
    |> Enum.reject(fn {_k, v} -> v in [nil, "", []] end)
    |> Map.new()
  end

  defp split_list(nil), do: nil

  defp split_list(value) do
    value |> String.split(~r/\s*;\s*/, trim: true)
  end

  defp style_args(meta, dir) do
    case Document.project(meta).csl do
      nil ->
        []

      name ->
        [dir, styles_path()]
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&Path.expand(name, &1))
        |> Enum.find(&File.regular?/1)
        |> case do
          nil -> []
          path -> ["--csl", path]
        end
    end
  end

  defp resource_args, do: ["--resource-path", Web.Uploads.root()]

  @doc "Where `.csl` styles named by `csl:` are looked for after the piece's own folder."
  def styles_path do
    Application.get_env(:web, :csl_path) ||
      Path.join(Path.dirname(Web.Blog.base_path()), "styles")
  end

  # Zotero's CSL JSON for the piece's folder, when there is one to ask.
  defp zotero_csl(meta) do
    with name when is_binary(name) <- Document.project(meta).zotero,
         true <- Zotero.configured?(),
         {:ok, collections} <- Zotero.list_collections(),
         %{key: key} <- Zotero.find_collection(collections, name),
         {:ok, items} <- Zotero.fetch_csl(key) do
      items
    else
      _ -> []
    end
  end

  defp pandoc do
    case Application.get_env(:web, :pandoc) do
      path when is_binary(path) -> if File.regular?(path), do: path
      _ -> System.find_executable("pandoc")
    end
  end
end
