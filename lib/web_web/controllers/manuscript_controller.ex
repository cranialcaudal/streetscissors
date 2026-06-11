defmodule WebWeb.ManuscriptController do
  use WebWeb, :controller

  alias Web.Manuscripts
  import WebWeb.Navigation, only: [return_context: 1]

  def index(conn, params) do
    # Filter categories as requested:
    allowed = ["latent-sensus", "another-blog", "fitness-blog", "sports-blog"]

    categories =
      Manuscripts.list_categories()
      |> Enum.filter(&(&1 in allowed))

    manuscripts =
      Map.new(categories, fn category ->
        {category, Manuscripts.list_files(category)}
      end)

    {return_to, return_label} = return_context(params["from"])

    render(conn, :index,
      categories: categories,
      manuscripts: manuscripts,
      return_to: return_to,
      return_label: return_label
    )
  end

  def show(conn, %{"category" => category, "slug" => slug} = params) do
    case Manuscripts.get_manuscript(category, slug) do
      {:ok, content} ->
        html_content = Earmark.as_html!(content)
        title = Manuscripts.get_title_from_slug(slug)

        # Context for portal UI if applicable
        recent_files =
          if category in ["sensus", "reflections"] do
            Manuscripts.list_files(category) |> Enum.take(10)
          else
            []
          end

        {return_to, return_label} = return_context(params["from"] || category)

        render(conn, :show,
          content: html_content,
          category: category,
          slug: slug,
          title: title,
          recent_files: recent_files,
          return_to: return_to,
          return_label: return_label
        )

      {:error, _} ->
        conn
        |> put_status(:not_found)
        |> put_view(WebWeb.ErrorHTML)
        |> render("404.html")
    end
  end

  def category_index(conn, %{"category" => category} = params) do
    folder = category

    files = Manuscripts.list_files_with_audio(folder)
    hit_counts = Web.Analytics.all_hits_by_prefix("/manuscripts/#{folder}/%")

    files =
      Enum.map(files, fn file ->
        Map.put(file, :hit_count, Map.get(hit_counts, file.slug, 0))
      end)

    sort = params["sort"] || "recent"

    sorted_files =
      case sort do
        "most-read" ->
          Enum.sort_by(files, & &1.hit_count, :desc)

        "least-read" ->
          Enum.sort_by(files, & &1.hit_count, :asc)

        "recent" ->
          Enum.sort_by(files, & &1.mtime, :desc)

        _ ->
          Enum.sort_by(files, & &1.mtime, :desc)
      end

    popular_files = Manuscripts.list_popular_files(folder, 7)
    {return_to, return_label} = return_context(params["from"])

    title =
      case category do
        "latent-sensus" -> "The Latent Sensus"
        "another-blog" -> "Another Blog"
        _ -> String.capitalize(category)
      end

    template =
      case category do
        "latent-sensus" -> :latent_sensus
        "another-blog" -> :another_blog
        _ -> :index
      end

    conn
    |> assign(:page_title, title)
    |> render(template,
      files: sorted_files,
      popular_files: popular_files,
      return_to: return_to,
      return_label: return_label,
      category: category,
      sort: sort
    )
  end

  def upload(conn, %{"file" => upload}) do
    extension = Path.extname(upload.filename)
    filename = "upload_#{DateTime.utc_now() |> DateTime.to_unix()}#{extension}"
    dest = Path.join([:code.priv_dir(:web), "static", "uploads", filename])

    # Ensure directory exists
    File.mkdir_p!(Path.dirname(dest))

    case File.cp(upload.path, dest) do
      :ok ->
        json(conn, %{status: "ok", path: "/uploads/#{filename}"})

      {:error, reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: inspect(reason)})
    end
  end

  def serve_audio(conn, %{"category" => category, "filename" => filename}) do
    # Manuscripts.audio_path validates the extension and guards against
    # directory-traversal before touching the filesystem.
    case Manuscripts.audio_path(category, filename) do
      {:ok, path} ->
        conn
        |> put_resp_content_type("audio/mpeg")
        |> send_file(200, path)

      :error ->
        conn |> put_status(:not_found) |> text("Not found")
    end
  end
end
