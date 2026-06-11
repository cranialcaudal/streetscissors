defmodule WebWeb.PageController do
  use WebWeb, :controller

  import WebWeb.Navigation, only: [return_context: 1]

  def home(conn, _params) do
    conn
    |> assign(:is_home, true)
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
end
