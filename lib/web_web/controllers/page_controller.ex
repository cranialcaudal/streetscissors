defmodule WebWeb.PageController do
  use WebWeb, :controller

  def home(conn, _params) do
    conn
    |> assign(:is_home, true)
    |> render(:home)
  end

  def about(conn, params) do
    vault_path = "/home/cesar/Documents/Obsidian Vault/About.md"

    markdown =
      case File.read(vault_path) do
        {:ok, content} -> content
        {:error, _} -> "Could not find About.md in Obsidian Vault at: " <> vault_path
      end

    html_content =
      case Earmark.as_html(markdown) do
        {:ok, html, _} -> html
        {:error, html, _} -> html
      end

    {return_to, return_label} = get_return_context(params["from"])

    render(conn, :about,
      return_to: return_to,
      return_label: return_label,
      html_content: html_content
    )
  end

  defp get_return_context(from) do
    case from do
      "latent-sensus" -> {"/blog/latent-sensus", "return to latent sensus"}
      "another-blog" -> {"/blog/another-blog", "return to another blog"}
      _ -> {"/", "return to homepage"}
    end
  end
end
