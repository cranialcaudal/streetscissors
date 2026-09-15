defmodule Web.Keywords do
  @moduledoc """
  Shared keyword handling for the two content systems.

  Blog posts keep their keywords in markdown frontmatter (authored in the
  Obsidian vault) while captain's logs keep theirs in a column on
  `audio_logs`. Both funnel through here so a keyword typed in the admin and a
  keyword typed in Obsidian normalize to the same token and filter the same
  way — `"New York"`, `"new-york"` and `"NEW YORK "` are all `"new-york"`.

  Keywords are stored canonically as a comma-separated string and handed
  around as an ordered, de-duplicated list.
  """

  @doc """
  Parses a raw keyword value into a normalized list.

  Accepts everything the vault is likely to contain: a comma-separated
  scalar (`"film, ferry"`), an inline YAML list (`"[film, ferry]"`), a
  already-split list, or `nil`. Order is the author's; duplicates are dropped.

      iex> Web.Keywords.parse("Film, Bowling Green , film")
      ["film", "bowling-green"]
  """
  @spec parse(String.t() | [String.t()] | nil) :: [String.t()]
  def parse(nil), do: []

  def parse(values) when is_list(values) do
    values
    |> Enum.map(&normalize/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  def parse(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.trim_leading("[")
    |> String.trim_trailing("]")
    |> String.split(",")
    |> parse()
  end

  @doc """
  Normalizes one keyword to its canonical token: downcased, internal
  whitespace hyphenated, punctuation dropped. Letters outside ASCII survive.
  """
  @spec normalize(String.t()) :: String.t()
  def normalize(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.trim("\"")
    |> String.trim("'")
    |> String.downcase()
    # Underscores survive the punctuation strip so the next step can turn them
    # into hyphens rather than closing "night_walk" up into "nightwalk".
    |> String.replace(~r/[^\p{L}\p{N}\s_-]/u, "")
    |> String.replace(~r/[\s_]+/u, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end

  @doc """
  Renders a keyword list back to the canonical stored form.

      iex> Web.Keywords.format(["film", "ferry"])
      "film, ferry"
  """
  @spec format([String.t()]) :: String.t()
  def format(keywords) when is_list(keywords), do: Enum.join(keywords, ", ")

  @doc """
  Slugifies a title into a URL segment. Same normalization as a keyword —
  a slug is just a keyword that happens to name a whole piece.
  """
  @spec slugify(String.t()) :: String.t()
  def slugify(title) when is_binary(title), do: normalize(title)

  @doc """
  Counts keyword usage across many items' keyword lists, most-used first and
  alphabetical within a tie. Powers the filter bars on `/blog` and `/logs`.

      iex> Web.Keywords.tally([["film", "nyc"], ["film"]])
      [{"film", 2}, {"nyc", 1}]
  """
  @spec tally([[String.t()]]) :: [{String.t(), pos_integer()}]
  def tally(keyword_lists) do
    keyword_lists
    |> List.flatten()
    |> Enum.frequencies()
    |> Enum.sort_by(fn {keyword, count} -> {-count, keyword} end)
  end

  @doc """
  True when `keywords` contains `keyword`. A blank or `nil` filter matches
  everything, so callers can pass a query param straight through.
  """
  @spec match?([String.t()], String.t() | nil) :: boolean()
  def match?(_keywords, nil), do: true
  def match?(_keywords, ""), do: true
  def match?(keywords, keyword), do: normalize(keyword) in keywords
end
