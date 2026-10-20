defmodule Web.Frontmatter do
  @moduledoc """
  Where a Markdown file's frontmatter ends and its body begins: the one
  splitter the blog, the fitness vault (days, wiki, blocks), the week, the
  changelog and the homepage share.

  A file saved on Windows, or by a tool that writes `\\r\\n`, used to lose its
  frontmatter in every reader but the blog's, silently: each had its own
  `\\A---\\n` pattern. This one takes `\\n` or `\\r\\n`, and spaces after the
  fences.

  Reading the lines inside is left to each reader on purpose: the blog folds
  `- item` lists into a scalar, the vault keeps only `key: value` lines, and
  changing either would change what an existing file means.
  """

  @fence ~r/\A---[ \t]*\r?\n(.*?)\r?\n---[ \t]*(?:\r?\n|\z)(.*)\z/s

  @doc "`{frontmatter_text, body}`; `{\"\", text}` when the file has none."
  def split(text) when is_binary(text) do
    case Regex.run(@fence, text) do
      [_, meta, body] -> {meta, body}
      nil -> {"", text}
    end
  end

  @doc "The body alone."
  def strip(text), do: text |> split() |> elem(1)

  @doc "The frontmatter's lines, `\\r` removed, for a reader's own parsing."
  def lines(meta_text), do: String.split(meta_text, ~r/\r?\n/)
end
