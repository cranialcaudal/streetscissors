defmodule WebWeb.AdminLive.BlogEditor do
  @moduledoc """
  One post's file in the admin, edited on the full page of `WebWeb.AdminLive.Workbench`.

  The page only checks that the file is there; the workbench owns the text,
  the save and its conflict, the reading list, Zotero and the preview.
  """

  use WebWeb, :live_view

  alias Web.Blog

  def mount(%{"slug" => slug}, session, socket) do
    cond do
      !session["admin_user"] ->
        {:ok, push_navigate(socket, to: "/")}

      match?({:ok, _}, Blog.read_source(slug)) ->
        {:ok,
         socket
         |> assign(page_title: "#{slug}.md | Admin", slug: slug)
         |> WebWeb.AdminLive.Workbench.attach()}

      true ->
        {:ok,
         socket
         |> put_flash(:error, "There is no #{slug}.md in the blog.")
         |> push_navigate(to: ~p"/admin/blog")}
    end
  end

  def handle_info({:workbench_saved, _slug}, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <.live_component module={WebWeb.AdminLive.Workbench} id="workbench" slug={@slug} mode="editor" />
    """
  end
end
