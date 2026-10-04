defmodule WebWeb.PageController do
  use WebWeb, :controller

  import WebWeb.Navigation, only: [return_context: 1]

  alias WebWeb.SEO

  def home(conn, _params) do
    # Random contact sheet for the photo hero card; nil when the
    # negatives directory is unavailable so the card degrades to its
    # gradient background.
    hero_sheet =
      case Web.Negatives.list_contact_sheets() do
        [] -> nil
        sheets -> Enum.random(sheets)
      end

    author = SEO.author_name()
    title = if author, do: "streetscissors · #{author}", else: "streetscissors"

    desc =
      if author,
        do: "Photographs, essays and recordings from the streetscissors darkroom by #{author}.",
        else: "Photographs, essays and recordings from the streetscissors darkroom."

    conn
    |> assign(:is_home, true)
    |> assign(:hero_sheet, hero_sheet)
    |> assign(:page_title, title)
    |> assign(:og_title, title)
    |> assign(:og_description, desc)
    |> assign(:canonical_path, ~p"/")
    |> render(:home)
  end

  def about(conn, params) do
    # Internal path within the project repository
    path = "content/about.md"

    markdown =
      case File.read(path) do
        {:ok, content} -> content
        {:error, _} -> "Could not find about.md in the content directory."
      end

    html_content =
      case Earmark.as_html(markdown) do
        {:ok, html, _} -> html
        {:error, html, _} -> html
      end

    {return_to, return_label} = return_context(params["from"])
    author = SEO.author_name() || "Cesar Anthony Moreno"
    crumbs = [{"Home", ~p"/"}, {"About", ~p"/about"}]

    profile_json_ld = %{
      "@context" => "https://schema.org",
      "@type" => "ProfilePage",
      "mainEntity" => %{
        "@type" => "Person",
        "name" => author,
        "url" => SEO.absolute("/about"),
        "jobTitle" => "Researcher",
        "worksFor" => %{
          "@type" => "Organization",
          "name" => "UC Davis"
        }
      }
    }

    conn
    |> assign(:page_title, "About · #{author}")
    |> assign(:og_title, "About · #{author}")
    |> assign(
      :og_description,
      "About #{author} — researcher at UC Davis studying cognitive science, writer, and photographer behind streetscissors."
    )
    |> assign(:canonical_path, ~p"/about")
    |> assign(:json_ld, [profile_json_ld, SEO.breadcrumb_json_ld(crumbs)])
    |> render(:about,
      return_to: return_to,
      return_label: return_label,
      html_content: html_content
    )
  end

  @how_to_path "docs/how-to.md"
  @how_to_description "How the streetscissors site and the film pipeline behind it actually work: written for beginners, in parts."

  def how_to(conn, params) do
    # `docs/`, not `content/`: the manual documents the software and is licensed
    # with it, and the same file is what GitHub renders. Read off disk at
    # request time like every other file-based page here — which works in
    # production because the systemd unit pins its working directory to the
    # checkout.
    {html_content, contents} =
      case File.read(@how_to_path) do
        {:ok, markdown} ->
          Web.Docs.render(markdown)

        {:error, _} ->
          {"<p>The manual could not be read from <code>#{@how_to_path}</code>.</p>", []}
      end

    {return_to, return_label} = return_context(params["from"])

    conn
    |> assign(:page_title, "How this is made")
    |> assign(:og_description, @how_to_description)
    |> assign(:meta_description, @how_to_description)
    |> assign(:canonical_path, ~p"/how-to")
    |> render(:how_to,
      html_content: html_content,
      contents: contents,
      return_to: return_to,
      return_label: return_label
    )
  end

  @roadmap_path "docs/roadmap.md"
  @roadmap_description "The plan for finishing the streetscissors site: what already stands, what gets built next, and in what order."

  def roadmap(conn, params) do
    # Same shell as the manual: docs/roadmap.md is read off disk at request
    # time, so edits go live without a redeploy.
    {html_content, contents} =
      case File.read(@roadmap_path) do
        {:ok, markdown} ->
          Web.Docs.render(markdown)

        {:error, _} ->
          {"<p>The roadmap could not be read.</p>", []}
      end

    {return_to, return_label} = return_context(params["from"])

    conn
    |> assign(:page_title, "Roadmap")
    |> assign(:og_description, @roadmap_description)
    |> assign(:meta_description, @roadmap_description)
    |> assign(:canonical_path, ~p"/roadmap")
    |> render(:how_to,
      html_content: html_content,
      contents: contents,
      return_to: return_to,
      return_label: return_label
    )
  end

  def food(conn, _params) do
    # `content/`, not `docs/`: the kitchen is the author's own diet, so both its
    # plan (meals.md) and its week strip and description (meals-week.json) live
    # in the fitness vault rather than in code. They sit at the vault's *root*,
    # where Web.Fitness.Vault ignores them — the Vault only reads weekly/,
    # additional/, modules/, exercise-wiki/ and references.md. That matters,
    # because Vault.checklist_only/1 would strip every table and every line of
    # method out of meals.md if it ever did pick it up.
    week = meals_week()

    {html_content, contents} =
      case File.read(Path.join(Web.Fitness.Vault.base_path(), "meals.md")) do
        {:ok, markdown} -> Web.Docs.render(markdown)
        {:error, _} -> {"<p>The meal plan could not be read.</p>", []}
      end

    conn
    |> assign(:page_title, "The Kitchen")
    |> assign(:og_description, week.description)
    |> assign(:meta_description, week.description)
    |> assign(:canonical_path, ~p"/food")
    # Unlisted rather than public: nothing links here, so the only way a crawler
    # arrives is by guessing the path or following a pasted link. This is what
    # stops it being indexed if one does.
    |> assign(:robots, "noindex, nofollow")
    |> render(:food, html_content: html_content, contents: contents, week_days: week.days)
  end

  # The week strip mirrors "The week, Sunday to Sunday" in meals.md — one entry
  # per day, in the order its h3s appear, so the strip and the anchors it jumps
  # to never drift apart. Each `id` has to match Web.Keywords.slugify/1 of that
  # heading ("Sunday" -> "sunday"), since that's what Web.Docs anchors with.
  defp meals_week do
    path = Path.join(Web.Fitness.Vault.base_path(), "meals-week.json")

    with {:ok, json} <- File.read(path),
         {:ok, %{} = week} <- Jason.decode(json) do
      %{
        description: week["description"] || "The kitchen.",
        days:
          Enum.map(week["days"] || [], fn day ->
            %{
              id: day["id"],
              name: day["name"],
              icon: day["icon"],
              label: day["label"],
              kcal: day["kcal"]
            }
          end)
      }
    else
      _ -> %{description: "The kitchen.", days: []}
    end
  end

  # Admin only. A plain `get` inside `live_session :admin` is not covered by
  # the session's on_mount hooks, so the check is made here.
  def calendar(conn, _params) do
    if get_session(conn, "admin_user") do
      markdown =
        case File.read("content/notes/calendar.md") do
          {:ok, content} -> content
          {:error, _} -> "Could not find notes/calendar.md in the content directory."
        end

      conn
      |> assign(:page_title, "Calendar Reference")
      |> assign(:robots, "noindex, nofollow")
      |> render(:calendar, html_content: Earmark.as_html!(markdown, gfm: true))
    else
      conn
      |> put_status(:not_found)
      |> put_view(WebWeb.ErrorHTML)
      |> put_root_layout(false)
      |> put_layout(false)
      |> render("404.html")
    end
  end
end
