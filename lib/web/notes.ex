defmodule Web.Notes do
  @moduledoc """
  A thought caught on the way past (`WebWeb.AdminLive.QuickAdd`): one dated
  line appended to `content/notes/inbox.md`, the private planning folder no
  public page renders (CLAUDE.md, "Private by default"). Obsidian shows it
  like any other note, and it is in the nightly content backup.

  The folder is `config :web, :notes_path`, or `notes/` beside the blog's
  folder in the vault.
  """

  alias Web.Keywords

  def inbox_path do
    dir =
      Application.get_env(:web, :notes_path) ||
        Path.join(Path.dirname(Web.Blog.base_path()), "notes")

    Path.join(dir, "inbox.md")
  end

  @doc """
  Appends `text` as `- YYYY-MM-DD text #keyword …` (keywords normalised by
  `Web.Keywords`). Blank text adds nothing. Returns `:ok` or the write's error.
  """
  def append(text, keywords \\ "") do
    case String.trim(to_string(text)) do
      "" ->
        {:error, :blank}

      text ->
        tags = keywords |> Keywords.parse() |> Enum.map_join(&" ##{&1}")
        line = "- #{Date.to_iso8601(Web.Clock.local_today())} #{one_line(text)}#{tags}\n"
        path = inbox_path()

        with :ok <- File.mkdir_p(Path.dirname(path)) do
          File.write(path, line, [:append])
        end
    end
  end

  # A note is one line of the list, however it was typed.
  defp one_line(text), do: text |> String.split(~r/\s*\n\s*/, trim: true) |> Enum.join(" — ")
end
