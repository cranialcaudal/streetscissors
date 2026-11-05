defmodule WebWeb.AdminLive.ZoteroReader do
  @moduledoc """
  A Zotero document read on a page of its own: the reader (`WebWeb.AdminLive.ZoteroReaderComponent`) at the full width of the screen.

  `/admin/zotero/:item` opens an item's first readable attachment (`?a=`
  picks another; `?back=` is the admin page to return to, usually the draft
  the reading is for). The writing workbench opens the same reader in its
  first panel, beside the draft; its **Full page** comes here.
  """

  use WebWeb, :live_view

  import WebWeb.AdminComponents

  alias Web.Writing.Zotero.Reader

  def mount(%{"item" => key}, _session, socket) do
    if Reader.key?(key) do
      {:ok, assign(socket, page_title: "Reading | Admin", title: "Opening…", item_key: key)}
    else
      {:ok,
       socket
       |> put_flash(:error, "That is not a Zotero item.")
       |> push_navigate(to: ~p"/admin/blog")}
    end
  end

  def handle_params(params, _uri, socket) do
    {:noreply,
     assign(socket,
       back: safe_back(params["back"]),
       attachment_key: if(Reader.key?(params["a"]), do: params["a"])
     )}
  end

  # A return address inside the admin, never somewhere else.
  defp safe_back(back) when is_binary(back) do
    if String.starts_with?(back, "/admin/") and not String.contains?(back, ["//", "\\"]),
      do: back,
      else: "/admin/blog"
  end

  defp safe_back(_), do: "/admin/blog"

  def handle_info({:reader_opened, title}, socket) do
    {:noreply, assign(socket, title: title, page_title: "#{title} | Reading | Admin")}
  end

  def handle_info({:workbench_flash, kind, message}, socket) do
    {:noreply, put_flash(socket, kind, message)}
  end

  def render(assigns) do
    ~H"""
    <.page_head slug="Writing / Zotero / Read" title={@title}>
      <:actions>
        <.link navigate={@back} class="adm-btn adm-btn--quiet">Back</.link>
        <a href={"zotero://select/library/items/#{@item_key}"} class="adm-btn adm-btn--quiet">
          Open in Zotero
        </a>
      </:actions>
    </.page_head>

    <.live_component
      module={WebWeb.AdminLive.ZoteroReaderComponent}
      id={"reader-#{@item_key}-#{@attachment_key}"}
      item_key={@item_key}
      attachment_key={@attachment_key}
      full_page
    />
    """
  end
end
