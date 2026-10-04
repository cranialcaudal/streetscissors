defmodule WebWeb.ErrorHTML do
  @moduledoc """
  What the site says when it has no page to give.

  **The 404 is a whole document.** It is drawn in three situations, and only
  one of them has a layout to offer: a controller that looked for a post and
  found none has been through the browser pipeline, but an address no route
  matches has not — no session was fetched, no assigns were set — and a
  LiveView that raises on mount is rendered by the endpoint's error handler
  with layouts off. The old template was a block meant to be wrapped, so in
  the last two cases it went out as a bare `<div>` with no stylesheet, which
  is what anyone who mistyped an address actually saw. `not_found/1` now
  carries its own `<head>`, and `WebWeb.NotFound.render/1` turns the layouts
  off for the controllers, so every 404 is the same page.

  **It says what was nearby.** The address that missed nearly always names
  the section and roughly the thing, so the page offers the closest real
  pieces (`Web.Nearby`) and then the ways in.

  Every other status keeps Phoenix's plain line of text.
  """
  use WebWeb, :html

  embed_templates "error_html/*"

  @max_path 120

  def render("404.html", assigns) do
    path = request_path(assigns)

    assigns
    |> Map.new()
    |> Map.merge(%{path: path && shorten(path), suggestions: Web.Nearby.suggest(path)})
    |> not_found()
  end

  # The default is to render a plain text page based on
  # the template name. For example, "500.html" becomes
  # "Internal Server Error".
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end

  defp request_path(%{conn: %Plug.Conn{request_path: path}}), do: path
  defp request_path(_assigns), do: nil

  # A scanner's address can run to kilobytes. The page quotes enough of it
  # to be recognised.
  defp shorten(path) do
    if String.length(path) > @max_path, do: String.slice(path, 0, @max_path) <> "…", else: path
  end
end
