defmodule Web.Daybook.Book do
  @moduledoc """
  The year as a book: the year's essays, in order, each a chapter with its
  frames in place, as an EPUB and a PDF, beside the printable year page
  (`/daybook/:year/book.epub`, `/book.pdf`).

  **Built with Quarto**, which the fitness report already uses
  (`Web.Fitness.Report`): one Markdown file is written, and Quarto renders it
  `--to epub` and `--to typst` (its bundled typst makes the PDF, so no TeX
  is needed). An embedded frame (`![[012/3|Caption]]`) or sheet
  (`![[roll012]]`) becomes a JPEG beside it, made by ImageMagick, since typst
  reads no WebP; rides and figures are left out of print.

  Kept in `year-books/` beside the uploads root (never under it: the proxy
  serves that), named `<year>.epub` and `<year>.pdf`. Nightly
  (`run_scheduled/0`), a year is rendered again only when one of its posts
  changed, by a fingerprint of their names and file times. One render at a
  time. Drafts are never in it: `Blog.list_posts/0` never sees one.
  """

  require Logger

  alias Web.{Blog, Negatives}

  @embed_re ~r/!\[\[([^\]\|\n]+?)(?:\|([^\]\n]*))?\]\]/
  @frame_re ~r/\A(?:roll)?0*(\d{1,4})\s*\/\s*0*(\d{1,4})\z/
  @sheet_re ~r/\A(?:roll)?0*(\d{1,4})(?:_[\w-]+)?\z/
  @formats [epub: "epub", pdf: "typst"]

  def dir do
    Application.get_env(:web, :year_books_path) ||
      Web.Uploads.root() |> Path.expand() |> Path.dirname() |> Path.join("year-books")
  end

  defp quarto, do: Application.get_env(:web, :quarto_bin) || "quarto"

  @doc "Where a year's book is, as `:epub` or `:pdf`, when it has been built; else nil."
  def path(year, format) when format in [:epub, :pdf] do
    file = Path.join(dir(), "#{year}.#{format}")
    if File.regular?(file), do: file
  end

  @doc "The Quantum entry: every year with essays, rendered when they changed."
  def run_scheduled do
    for year <- years(), fingerprint(year) != stored(year) do
      case render(year) do
        {:ok, _} -> Logger.info("year book: #{year}")
        {:error, reason} -> Logger.warning("year book #{year}: #{inspect(reason)}")
      end
    end

    :ok
  end

  defp years, do: Blog.list_posts() |> Enum.map(& &1.date.year) |> Enum.uniq() |> Enum.sort()

  defp posts(year) do
    Blog.list_posts()
    |> Enum.filter(&(&1.date.year == year))
    |> Enum.sort_by(&{Date.to_gregorian_days(&1.date), &1.slug})
  end

  defp fingerprint(year),
    do:
      year |> posts() |> Enum.map(&{&1.slug, &1.mtime}) |> :erlang.phash2() |> Integer.to_string()

  defp fingerprint_path(year), do: Path.join(dir(), ".#{year}.fingerprint")

  defp stored(year) do
    case File.read(fingerprint_path(year)) do
      {:ok, text} -> String.trim(text)
      _ -> nil
    end
  end

  @doc """
  Renders a year's book in both formats: `{:ok, [epub_path, pdf_path]}` or
  `{:error, reason}`. Never raises. A second render while one runs is `:busy`.
  """
  def render(year) when is_integer(year) do
    :global.trans({__MODULE__, :render}, fn -> do_render(year) end, [node()], 0) ||
      {:error, :busy}
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp do_render(year) do
    build = Path.join(dir(), ".build-#{year}")
    out = Path.join(build, "out")

    with posts when posts != [] <- posts(year),
         _ = File.rm_rf(build),
         :ok <- File.mkdir_p(out),
         :ok <- File.chmod(dir(), 0o700),
         :ok <- File.write(Path.join(build, "book.md"), markdown(year, posts, build)),
         {:ok, made} <- render_formats(build, out, year) do
      File.write(fingerprint_path(year), fingerprint(year))
      File.rm_rf(build)
      {:ok, made}
    else
      [] -> {:error, :no_posts}
      {:error, _} = error -> error
      other -> {:error, other}
    end
  catch
    :exit, {:enoent, _} -> {:error, :no_quarto}
  end

  defp render_formats(build, out, year) do
    Enum.reduce_while(@formats, {:ok, []}, fn {ext, to}, {:ok, made} ->
      case System.cmd(quarto(), ["render", "book.md", "--to", to, "--output-dir", out],
             stderr_to_stdout: true,
             cd: build
           ) do
        {_, 0} ->
          case Path.wildcard(Path.join(out, "*.#{ext}")) do
            [file | _] ->
              target = Path.join(dir(), "#{year}.#{ext}")
              :ok = File.rename(file, target)
              {:cont, {:ok, made ++ [target]}}

            [] ->
              {:halt, {:error, {:quarto, "no .#{ext} was made"}}}
          end

        {output, status} ->
          {:halt, {:error, {:quarto, status, String.slice(output, -600, 600)}}}
      end
    end)
  end

  # One document: the title page's words, then a chapter per essay.
  defp markdown(year, posts, build) do
    author = Application.get_env(:web, :author_name)

    front =
      [
        "---",
        "title: #{Jason.encode!("streetscissors · #{year}")}",
        author && "author: #{Jason.encode!(author)}",
        "lang: en",
        "toc: true",
        "---",
        ""
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")

    chapters =
      posts
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {post, n} ->
        "# #{post.title}\n\n*#{Calendar.strftime(post.date, "%-d %B %Y")}*\n\n" <>
          embeds(body(post), build, n)
      end)

    front <> "\n" <> chapters <> "\n"
  end

  # The post list carries no bodies (`Blog.list_all_posts/0` drops them), so
  # each chapter reads its own post whole.
  defp body(%{body: body}) when is_binary(body), do: body

  defp body(%{slug: slug}) do
    case Blog.get_post(slug) do
      {:ok, %{body: body}} -> body
      _ -> ""
    end
  end

  # Obsidian embeds as plain Markdown images, each a JPEG made beside the book.
  defp embeds(body, build, chapter) do
    {text, _} =
      Regex.split(@embed_re, body, include_captures: true)
      |> Enum.map_reduce(0, fn part, i ->
        case Regex.run(@embed_re, part) do
          [^part, target | caption] ->
            case picture(String.trim(target)) do
              {:ok, source, alt} ->
                name = "img-#{chapter}-#{i}.jpg"
                caption = caption |> List.first() |> to_string() |> String.trim()

                if jpeg(source, Path.join(build, name)) == :ok,
                  do: {"![#{escape(if caption == "", do: alt, else: caption)}](#{name})", i + 1},
                  else: {"", i + 1}

              :none ->
                {"", i}
            end

          _ ->
            {part, i}
        end
      end)

    Enum.join(text)
  end

  defp picture(target) do
    cond do
      match = Regex.run(@frame_re, target) ->
        [_, roll, frame] = match

        case Negatives.frame_path(roll, frame) do
          {:ok, path} -> {:ok, path, "Roll #{roll}, frame #{frame}"}
          _ -> :none
        end

      match = Regex.run(@sheet_re, target) ->
        [_, roll | _] = match

        case Negatives.sheet_for_roll(roll) do
          {:ok, file} -> {:ok, Path.join(Negatives.contact_sheets_path(), file), "Roll #{roll}"}
          _ -> :none
        end

      true ->
        :none
    end
  end

  defp jpeg(source, target) do
    case System.cmd(
           Negatives.magick_bin(),
           [source <> "[0]", "-resize", "1600x1600>", "-quality", "85", target],
           stderr_to_stdout: true
         ) do
      {_, 0} -> :ok
      _ -> :error
    end
  catch
    :exit, _ -> :error
  end

  defp escape(text), do: String.replace(text, ~r/([\[\]])/, "\\\\\\1")
end
