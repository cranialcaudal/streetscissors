defmodule Web.Manuscripts do
  @moduledoc """
  Context for listing and reading markdown manuscripts.
  """

  @default_base_path "/home/cesar/streetscissors/content/blogs"

  @doc """
  Root directory on disk where manuscript markdown and audio live.

  Configurable via `config :web, :manuscripts_path` (sourced from the
  `MANUSCRIPTS_PATH` env var in `config/runtime.exs`). Falls back to a local
  development default when unset.
  """
  def base_path, do: Application.get_env(:web, :manuscripts_path, @default_base_path)

  @doc """
  Resolves an audio file path inside a category's `audio/` directory, guarding
  against directory-traversal. Returns `{:ok, absolute_path}` only when the
  resolved path is a real `.mp3` file that stays within the manuscripts root.
  """
  def audio_path(category, filename) do
    with true <- String.ends_with?(filename, ".mp3"),
         {:ok, rel} <- Path.safe_relative(Path.join([category, "audio", filename])) do
      path = Path.join(base_path(), rel)
      if File.regular?(path), do: {:ok, path}, else: :error
    else
      _ -> :error
    end
  end

  def list_categories do
    # Only these categories for manuscripts
    ["latent-sensus", "another-blog", "fitness-blog", "sports-blog"]
  end

  def list_files(category) do
    path = Path.join([base_path(), category])

    if File.exists?(path) do
      path
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".md"))
      |> Enum.map(fn filename ->
        full_path = Path.join(path, filename)
        stat = File.stat!(full_path)

        %{
          slug: String.replace(filename, ".md", ""),
          title: format_title(filename),
          mtime: NaiveDateTime.from_erl!(stat.mtime)
        }
      end)
      # Sort descending by time
      |> Enum.sort_by(& &1.mtime, :desc)
    else
      []
    end
  end

  @doc """
  Lists manuscripts with paired audio files, excerpts, and metadata.
  Audio files should live in priv/manuscripts/<category>/audio/<slug>.mp3
  """
  def list_files_with_audio(category) do
    base = Path.join([base_path(), category])
    audio_dir = Path.join(base, "audio")

    audio_set =
      if File.exists?(audio_dir) do
        audio_dir
        |> File.ls!()
        |> Enum.filter(&String.ends_with?(&1, ".mp3"))
        |> Enum.map(&String.replace(&1, ".mp3", ""))
        |> MapSet.new()
      else
        MapSet.new()
      end

    list_files(category)
    |> Enum.map(fn file ->
      audio_path =
        if MapSet.member?(audio_set, file.slug),
          do: "/manuscripts/#{category}/audio/#{file.slug}.mp3",
          else: nil

      # Load excerpt + metadata from file content
      full_path = Path.join(base, file.slug <> ".md")
      {excerpt, word_count} = extract_excerpt_and_words(full_path)
      read_min = max(1, div(word_count, 200))

      file
      |> Map.put(:audio_url, audio_path)
      |> Map.put(:excerpt, excerpt)
      |> Map.put(:word_count, word_count)
      |> Map.put(:read_min, read_min)
    end)
  end

  defp extract_excerpt_and_words(path) do
    case File.read(path) do
      {:ok, content} ->
        words = content |> String.split(~r/\s+/, trim: true) |> length()

        # Find first substantial paragraph: skip blank lines, headers, and short lines
        excerpt =
          content
          |> String.split("\n")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(fn line ->
            line == "" or
              String.starts_with?(line, "#") or
              String.length(line) < 40
          end)
          |> List.first("")
          |> String.slice(0, 280)
          |> then(fn text ->
            if String.length(text) >= 275, do: text <> "…", else: text
          end)

        {excerpt, words}

      _ ->
        {"", 0}
    end
  end

  def get_manuscript(category, slug) do
    filename = slug <> ".md"
    path = Path.join([base_path(), category, filename])

    if File.exists?(path) do
      content = File.read!(path)
      {:ok, content}
    else
      {:error, :not_found}
    end
  end

  def format_title(filename) do
    filename
    |> String.replace(".md", "")
    |> String.replace("-", " ")
    |> String.split(" ")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  def create_manuscript(category, slug, content) do
    dir = Path.join([base_path(), category])
    File.mkdir_p!(dir)

    path = Path.join(dir, slug <> ".md")
    File.write(path, content)
  end

  def update_manuscript(category, slug, content) do
    create_manuscript(category, slug, content)
  end

  def delete_manuscript(category, slug) do
    path = Path.join([base_path(), category, slug <> ".md"])
    File.rm(path)
  end

  def get_title_from_slug(slug), do: format_title(slug <> ".md")

  def list_popular_files(category, limit \\ 7) do
    popular_slugs = Web.Analytics.top_manuscripts(category, limit)

    if Enum.empty?(popular_slugs) do
      # Fallback to recent if no hits tracked yet
      list_files(category) |> Enum.take(limit)
    else
      # Get all files for category once
      all_files = list_files(category) |> Map.new(fn f -> {f.slug, f} end)

      popular_slugs
      |> Enum.map(fn {slug, count} ->
        case Map.get(all_files, slug) do
          nil -> nil
          file -> Map.put(file, :hit_count, count)
        end
      end)
      |> Enum.reject(&is_nil/1)
    end
  end
end
