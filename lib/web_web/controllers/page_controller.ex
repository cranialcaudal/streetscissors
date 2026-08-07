defmodule WebWeb.PageController do
  use WebWeb, :controller

  import WebWeb.Navigation, only: [return_context: 1]

  def home(conn, _params) do
    # Random contact sheet for the photo hero card; nil when the
    # negatives directory is unavailable so the card degrades to its
    # gradient background.
    hero_sheet =
      case Web.Negatives.list_contact_sheets() do
        [] -> nil
        sheets -> Enum.random(sheets)
      end

    conn
    |> assign(:is_home, true)
    |> assign(:hero_sheet, hero_sheet)
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

    render(conn, :about,
      return_to: return_to,
      return_label: return_label,
      html_content: html_content
    )
  end

  def calendar_markdown(conn, _params) do
    path = "content/calendar-markdown.md"

    markdown =
      case File.read(path) do
        {:ok, content} -> content
        {:error, _} -> "Could not find calendar-markdown.md in the content directory."
      end

    html_content = Earmark.as_html!(markdown, gfm: true)

    conn
    |> assign(:page_title, "Calendar Reference")
    |> render(:calendar_markdown, html_content: html_content)
  end
end
