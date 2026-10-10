defmodule Web.Author do
  @moduledoc """
  What the site says about the person who makes it, where the code needs to
  say it: the structured data on `/about`, the description a link to that
  page unfurls with, a profile linked from the homepage.

  None of it is the code's to know. It is read from `content/about.json`,
  beside `about.md` in the vault that git ignores, and every key is optional:

      {
        "job_title": "Researcher",
        "works_for": "A University",
        "description": "researcher, writer and photographer",
        "spotify_profile": "https://open.spotify.com/user/…"
      }

  The author's *name* is `AUTHOR_NAME` in the environment (`WebWeb.SEO`), as
  it was already. A clone with neither still builds, boots and renders: the
  pages simply say less.
  """

  @path "content/about.json"

  @doc "The file as a map of its string keys; empty when it is absent or unreadable."
  def profile do
    with {:ok, body} <- File.read(path()),
         {:ok, %{} = profile} <- Jason.decode(body) do
      profile
    else
      _ -> %{}
    end
  end

  @doc "One key of it, as trimmed text, or nil."
  def get(key) do
    case profile()[key] do
      value when is_binary(value) ->
        if String.trim(value) == "", do: nil, else: String.trim(value)

      _ ->
        nil
    end
  end

  @doc "A key that is a link: kept only when it is an https address."
  def link(key) do
    case get(key) do
      "https://" <> _ = url -> url
      _ -> nil
    end
  end

  defp path, do: Application.get_env(:web, :about_json_path, @path)
end
