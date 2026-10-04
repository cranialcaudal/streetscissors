defmodule Web.ContentHealth do
  @moduledoc """
  What is wrong with the written content, found by reading it the way the site
  does.

  A site whose pages are files has no database to enforce that a link points
  at something. A post renamed in the vault leaves every link to it dangling;
  a roll renumbered leaves an embed as literal text; a module nobody lists is
  a page nobody will ever see. Each of these is invisible until a reader finds
  it. `report/0` finds them first:

    * **Broken links** — every internal link and image in the posts, the
      about page, the manual and roadmap, and the fitness vault.
    * **Embeds that point at nothing** — `![[roll012]]`, `![[ride:123]]` and
      the rest, where `Web.Blog.Embeds` found no such thing.
    * **Posts missing a description or keywords** — published ones only; a
      draft is allowed to be unfinished.
    * **Files nothing uses** — library images no page embeds, and regimen
      modules no day lists.
    * **The archive** — rolls whose grease-pencil marks are withheld, why,
      and the command that fixes each (`Web.Negatives.Sheet.status/1`).

  **A link is checked by asking the site.** Rather than keep a second opinion
  about which paths exist — one more thing to drift from the router — each
  internal target is dispatched through `WebWeb.Endpoint` exactly as a
  request would be, and judged by the status that comes back. A page that
  exists answers 200, a retired address answers with its redirect, and a
  link to nothing answers 404, whichever of the site's sections it lands in.
  Nothing is counted as a visit: the request comes from loopback under a bot
  user agent, and `WebWeb.Plugs.Analytics` skips both.

  Links to other sites are counted and not followed. Checking them means
  dozens of requests to other people's servers on every look at this page,
  and a link that is down today is not thereby wrong.

  The report takes a second or two — it renders every page it checks — so the
  admin page builds it off the socket's process rather than in `mount/3`.
  """

  alias Web.Blog
  alias Web.Blog.Embeds
  alias Web.Fitness.Vault
  alias Web.Negatives
  alias Web.Negatives.Sheet

  @agent "streetscissors-content-health (bot)"
  @attr_re ~r/\s(?:href|src)="([^"]+)"/
  @wikilink_re ~r/\[\[([^\]\|\n]+?)(?:\|[^\]\n]*)?\]\]/

  @type source :: %{label: String.t(), where: String.t(), edit: String.t() | nil}

  @doc """
  The whole report:

      %{
        checked_at: DateTime.t(),
        broken: [%{source: source, target: String.t(), problem: String.t()}],
        embeds: [%{source: source, target: String.t()}],
        posts: [%{post: map, missing: [:description | :keywords]}],
        unused: [%{kind: :image | :module | :day, name: String.t(), detail: String.t()}],
        archive: [%{roll: String.t(), format: String.t(), prints: integer,
                    reason: String.t(), fix: String.t()}],
        external: non_neg_integer()
      }
  """
  def report do
    posts = Blog.list_all_posts()
    pages = sources(posts)
    {internal, external} = links(pages)
    verdicts = Map.new(Enum.uniq_by(internal, & &1.path), &{&1.path, ask(&1.path)})

    %{
      checked_at: DateTime.utc_now(),
      broken:
        broken_links(internal, verdicts) ++
          relative_links(pages) ++
          vault_links() ++
          vault_modules(),
      embeds:
        for(
          %{embeds: embeds, source: source} <- pages,
          target <- embeds,
          do: %{source: source, target: target}
        ),
      posts: undescribed(posts),
      unused: unused_images(pages) ++ unused_vault_files(),
      archive: archive(),
      external: external
    }
  end

  @doc "How many things in a report want attention. The archive's rolls count only when they have prints."
  def count(report) do
    length(report.broken) + length(report.embeds) + length(report.posts) + length(report.unused) +
      Enum.count(report.archive, &(&1.prints > 0))
  end

  # --- What is read ----------------------------------------------------------

  # One entry per page: where it came from, its text as written, and the HTML
  # the site makes of it. Posts go through `Blog.to_html/1`, so a link an
  # embed generates is checked along with the ones the author typed.
  defp sources(posts) do
    post_pages =
      for %{slug: slug} <- posts, {:ok, post} <- [Blog.get_post(slug, drafts: true)] do
        html = Blog.to_html(post.body)

        %{
          source: %{label: post.title, where: "blog/#{slug}.md", edit: "/admin/blog/#{slug}/edit"},
          text: post.body,
          html: html,
          embeds: Embeds.unresolved(html)
        }
      end

    file_pages =
      for {label, path} <- [
            {"About", Path.join(Path.dirname(Blog.base_path()), "about.md")},
            {"The manual", "docs/how-to.md"},
            {"The roadmap", "docs/roadmap.md"}
          ],
          {:ok, text} <- [File.read(path)] do
        %{
          source: %{label: label, where: Path.basename(path), edit: nil},
          text: text,
          html: markdown(text),
          embeds: []
        }
      end

    post_pages ++ file_pages ++ vault_pages()
  end

  defp vault_pages do
    base = Vault.base_path()

    for path <- Web.Backup.Tree.walk(base),
        String.ends_with?(path, ".md"),
        {:ok, text} <- [File.read(path)] do
      where = Path.join("fitness", Path.relative_to(path, base))

      %{
        source: %{label: where, where: where, edit: nil},
        text: text,
        html: markdown(text),
        embeds: []
      }
    end
  end

  defp markdown(text) do
    case Earmark.as_html(text, gfm: true) do
      {:ok, html, _} -> html
      {:error, html, _} -> html
    end
  end

  # --- Links -----------------------------------------------------------------

  # Every href and src, sorted into the ones this site answers for and a
  # count of the ones it does not.
  defp links(pages) do
    targets =
      for %{html: html, source: source} <- pages,
          [target] <- Regex.scan(@attr_re, html, capture: :all_but_first),
          do: {source, html_unescape(target)}

    internal =
      for {source, target} <- targets, path = internal_path(target), path != nil do
        %{source: source, target: target, path: path}
      end

    external =
      Enum.count(targets, fn {_source, target} ->
        target =~ ~r{^(https?:)?//} and internal_path(target) == nil
      end)

    {internal, external}
  end

  # The path a target names on this site, or nil when it names somewhere
  # else. The admin is left out: asked without a session it redirects home,
  # which says nothing about the link.
  defp internal_path(target) do
    uri = URI.parse(target)

    cond do
      uri.scheme in ["http", "https"] and uri.host in own_hosts() ->
        clean(uri.path || "/", uri.query)

      uri.scheme != nil or uri.host != nil ->
        nil

      String.starts_with?(target, "/admin") ->
        nil

      String.starts_with?(target, "/") ->
        clean(uri.path, uri.query)

      true ->
        nil
    end
  end

  defp clean(path, nil), do: path
  defp clean(path, query), do: path <> "?" <> query

  defp own_hosts do
    host = WebWeb.Endpoint.config(:url)[:host]
    [host, "www." <> host]
  end

  defp broken_links(internal, verdicts) do
    for %{source: source, target: target, path: path} <- internal,
        problem = problem(Map.fetch!(verdicts, path)),
        problem != nil,
        uniq: true do
      %{source: source, target: target, problem: problem}
    end
  end

  defp problem(:ok), do: nil
  defp problem(:missing), do: "there is nothing at that address"
  defp problem({:moved, to}), do: "an old address: it now redirects to #{to}"
  defp problem({:error, status}), do: "the page answers with an error (#{status})"

  # A link with no scheme and no leading slash is relative to the file in the
  # vault, where Obsidian resolves it. On the site it resolves against the
  # page's address and lands nowhere.
  defp relative_links(pages) do
    for %{html: html, source: source} <- pages,
        [target] <- Regex.scan(@attr_re, html, capture: :all_but_first),
        target = html_unescape(target),
        relative?(target),
        uniq: true do
      %{
        source: source,
        target: target,
        problem: "a relative link: it works in Obsidian, not on the site"
      }
    end
  end

  defp relative?(target) do
    uri = URI.parse(target)

    uri.scheme == nil and uri.host == nil and target != "" and
      not String.starts_with?(target, ["/", "#", "?"])
  end

  @doc """
  What the site answers for a path: `:ok`, `:missing`, `{:moved, to}` or
  `{:error, status}`. The request goes through the endpoint — static files,
  the router, a LiveView's first render — and nowhere near the network.
  """
  def ask(path) do
    conn =
      :get
      |> Plug.Test.conn(path)
      |> Plug.Conn.put_req_header("user-agent", @agent)
      |> WebWeb.Endpoint.call(WebWeb.Endpoint.init([]))

    verdict(conn.status, conn)
  rescue
    # The endpoint renders an error page and then re-raises, as it would for
    # a real request. The exception knows the status it stands for.
    error -> verdict(Plug.Exception.status(error), nil)
  end

  defp verdict(status, _conn) when status in 200..299, do: :ok
  defp verdict(404, _conn), do: :missing
  defp verdict(410, _conn), do: :missing

  defp verdict(status, conn) when status in 300..399 and conn != nil do
    {:moved, conn |> Plug.Conn.get_resp_header("location") |> List.first("somewhere else")}
  end

  defp verdict(status, _conn), do: {:error, status}

  defp html_unescape(text) do
    text
    |> String.replace("&amp;", "&")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
  end

  # --- The fitness vault -----------------------------------------------------

  # `[[slug|Label]]` in the vault is a link to an exercise's wiki page, and
  # the renderer writes that link whether or not the exercise exists.
  defp vault_links do
    known = Vault.exercise_slugs()
    base = Vault.base_path()

    for path <- Web.Backup.Tree.walk(base),
        String.ends_with?(path, ".md"),
        {:ok, text} <- [File.read(path)],
        [slug] <- Regex.scan(@wikilink_re, text, capture: :all_but_first),
        slug = String.trim(slug),
        not MapSet.member?(known, slug),
        uniq: true do
      where = Path.join("fitness", Path.relative_to(path, base))

      %{
        source: %{label: where, where: where, edit: nil},
        target: "[[#{slug}]]",
        problem: "there is no exercise by that name in the wiki"
      }
    end
  end

  defp vault_modules do
    for {day, module} <- Vault.audit().missing_modules do
      %{
        source: %{
          label: "fitness: #{day}",
          where: "fitness/#{day}.md",
          edit: "/admin/fitness?tab=regimen"
        },
        target: "modules/#{module}.md",
        problem: "the day lists this module and there is no such file, so it renders as nothing"
      }
    end
  end

  defp unused_vault_files do
    audit = Vault.audit()

    for(
      module <- audit.unused_modules,
      do: %{kind: :module, name: "fitness/modules/#{module}.md", detail: "no day lists it"}
    ) ++
      for day <- audit.unlisted_days do
        %{
          kind: :day,
          name: "fitness/#{day}.md",
          detail: "not in the regimen's day order, so the site never shows it"
        }
      end
  end

  # --- Posts and images ------------------------------------------------------

  defp undescribed(posts) do
    for post <- posts,
        not post.draft,
        missing =
          Enum.reject([!post.described && :description, post.keywords == [] && :keywords], &(!&1)),
        missing != [] do
      %{post: post, missing: missing}
    end
  end

  # A library image is used if its address appears anywhere in anything read.
  defp unused_images(pages) do
    everything = Enum.map_join(pages, "\n", & &1.text)

    for %{name: name, path: path} <- Web.Blog.Images.list(),
        not String.contains?(everything, path) do
      %{kind: :image, name: name, detail: "no page embeds #{path}"}
    end
  end

  # --- The archive -----------------------------------------------------------

  # Rolls whose marks are withheld, the ones with prints first: those are the
  # rolls where a visitor should be seeing rings and is not.
  defp archive do
    for sheet <- Negatives.list_contact_sheets(),
        {:withheld, reason} <- [Sheet.status(sheet)] do
      {text, fix} = explain(reason, sheet)

      %{
        roll: sheet.roll,
        format: sheet.format,
        prints: length(Negatives.list_frames(sheet.roll)),
        reason: text,
        fix: fix
      }
    end
    |> Enum.sort_by(&{-&1.prints, &1.roll})
  end

  defp explain(:no_folder, sheet) do
    {"the roll's folder is missing, or it is not in catalog.csv",
     "negatives --list (roll #{sheet.roll} should be there)"}
  end

  defp explain(:not_analysed, sheet) do
    {"it has never been analysed: there is no frames.json", "negatives --analyze #{sheet.roll}"}
  end

  defp explain(:stale_analysis, sheet) do
    {"the analysis is stale: frames.json describes other strips than are in the folder",
     "negatives --analyze #{sheet.roll}"}
  end

  defp explain(:no_sheet, _sheet) do
    {"the sheet's image could not be read", "check the file in Contact Sheets/"}
  end

  defp explain(:size_mismatch, sheet) do
    dir =
      case Negatives.roll_dir(sheet.roll) do
        {:ok, dir} -> dir
        _ -> "<the roll's folder>"
      end

    {"the sheet's size matches no paper layout, so it was not built the way the marks assume",
     ~s(digital-contact-sheet-maker "#{dir}")}
  end
end
