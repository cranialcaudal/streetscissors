defmodule WebWeb.AdminLive.PaperEditor do
  @moduledoc """
  One paper's file (`Web.Writing.Papers`) on the full page of `WebWeb.AdminLive.Workbench`, with Export.
  """

  use WebWeb, :live_view

  alias Web.Writing.Papers

  def mount(%{"slug" => slug}, _session, socket) do
    case Papers.read_source(slug) do
      {:ok, _} ->
        {:ok,
         socket
         |> assign(page_title: "#{slug}.md | Writing | Admin", slug: slug)
         |> WebWeb.AdminLive.Workbench.attach()}

      _ ->
        {:ok,
         socket
         |> put_flash(:error, "There is no #{slug}.md in the writing folder.")
         |> push_navigate(to: ~p"/admin/writing")}
    end
  end

  def handle_info({:workbench_saved, _slug}, socket), do: {:noreply, socket}

  def render(assigns) do
    ~H"""
    <.live_component
      module={WebWeb.AdminLive.Workbench}
      id="workbench"
      slug={@slug}
      mode="paper"
      store={Papers}
    />
    """
  end
end
